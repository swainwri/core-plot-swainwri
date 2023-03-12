//
//  CPTContourPlot.m
//  CorePlot Mac
//
//  Created by Steve Wainwright on 19/12/2020.
//
// CPTContourPlot exploits the CPTContours Class  generate contour lines
//
//        IMPLEMENTATION OF
//        AN IMPROVED CONTOUR
//        PLOTTING ALGORITHM
//        BY
//
//        MICHAEL JOSEPH ARAMINI
//
//        B.S., Stevens Institute of Technology, 1980
// See http://www.ultranet.com/~aramini/thesis.html
//
// Ported to C++ by Jonathan de Halleux.
// Ported to ObjC by Steve Wainwright 2021.
//
//#if TARGET_OS_OSX
//#import <CGPathIntersections Mac/CGPathIntersections.h>
//#else
//#import <CGPathIntersections iOS/CGPathIntersections.h>
//#endif

#import "CPTContourPlot.h"

#import "CPTExceptions.h"
#import "CPTFill.h"
#import "CPTLegend.h"
#import "CPTLegendEntry.h"
#import "CPTColor.h"
#import "CPTLineStyle.h"
#import "CPTMutableLineStyle.h"
#import "CPTMutableNumericData.h"
#import "CPTMutableTextStyle.h"
#import "CPTPathExtensions.h"
#import "CPTPlotArea.h"
#import "CPTPlotRange.h"
#import "CPTPlotSpace.h"
#import "CPTPlotSpaceAnnotation.h"
#import "CPTShadow.h"
#import "CPTTextLayer.h"
#import "CPTUtilities.h"
#import "CPTXYPlotSpace.h"
#import "CPTMutablePlotRange.h"
#import "NSCoderExtensions.h"
#import "CPTFieldFunctionDataSource.h"
#import "_CPTContours.h"
#import "_CPTHull.h"
#import "_CPTContourMemoryManagement.h"
#import "_CPTContourEnumerations.h"
#import "_CPTContourGraph.h"
#import "GWKMeansCluster/_GWCluster.h"
#import "GWKMeansCluster/_GWPointCluster.h"
#import "GWKMeansCluster/_GWPoint.h"
#import "CGPathIntersections/CGPathPlusIntersections.h"
#import "GMMCluster/GMMCluster.h"
#import "tgmath.h"

#if TARGET_OS_OSX
#import "CPTPlatformSpecificCategories.h"
#import "NSBezierPath+CGPath.h"
#endif

#include <math.h>
#include <assert.h>
#include "kd3/kdtree.h"

int signValue(double a);

int signValue(double a) {
    return ((!signbit(a)) << 1) - 1;
}

CGPoint GetCenterPointOfCGPath (CGPathRef aPath);
NSUInteger GetNoVerticesCGPath (CGPathRef aPath);
static void convertToListOfPoints(void* info, const CGPathElement* element);
double polygonArea(NSMutableArray* points);
double polygonAreaCGPoints(CGPoint* points, NSUInteger N);
double cgpathArea(CGPathRef aPath);
CGPoint centroid(NSMutableArray* points);
CGPoint centroidCGPoints(CGPoint* points, NSUInteger N);
CGPoint pointInCGPath(CGPathRef outerPath, CGPathRef innerPath);

CGPoint GetCenterPointOfCGPath (CGPathRef aPath) {
    // Convert path to an array
    NSMutableArray* a = [NSMutableArray new];
    CGPathApply(aPath, (__bridge void *)(a), convertToListOfPoints);
    return centroid(a);
}

NSUInteger GetNoVerticesCGPath (CGPathRef aPath) {
    // Convert path to an array
    NSMutableArray* a = [NSMutableArray new];
    CGPathApply(aPath, (__bridge void *)(a), convertToListOfPoints);
    return a.count;
}

static void convertToListOfPoints(void* info, const CGPathElement* element) {
    NSMutableArray* a = (__bridge NSMutableArray*) info;

    switch (element->type) {
        case kCGPathElementMoveToPoint:
        {
#if TARGET_OS_OSX
            [a addObject:[NSValue valueWithPoint:element->points[0]]];
#else
            [a addObject:[NSValue valueWithCGPoint:element->points[0]]];
#endif
        }
        break;
        case kCGPathElementAddLineToPoint:
        {
#if TARGET_OS_OSX
            [a addObject:[NSValue valueWithPoint:element->points[0]]];
#else
            [a addObject:[NSValue valueWithCGPoint:element->points[0]]];
#endif
        }
        break;
        case kCGPathElementAddQuadCurveToPoint:
        {
            for (int i=0; i<2; i++) {
#if TARGET_OS_OSX
                [a addObject:[NSValue valueWithPoint:element->points[i]]];
#else
                [a addObject:[NSValue valueWithCGPoint:element->points[i]]];
#endif
            }
        }
        break;
        case kCGPathElementAddCurveToPoint:
        {
            for (int i=0; i<3; i++) {
#if TARGET_OS_OSX
                [a addObject:[NSValue valueWithPoint:element->points[i]]];
#else
                [a addObject:[NSValue valueWithCGPoint:element->points[i]]];
#endif
            }
        }
        break;
        case kCGPathElementCloseSubpath:
        break;
    }
}

double polygonArea(NSMutableArray* points) {
    double area = 0;
    NSUInteger N = [points count];

    NSUInteger j;
    for (NSUInteger i = 0; i < N; i++) {
        j = (i + 1) % N;
#if TARGET_OS_OSX
        NSPoint pii =  [(NSValue*)[points objectAtIndex:i] pointValue];
        NSPoint pjj =  [(NSValue*)[points objectAtIndex:j] pointValue];
#else
        CGPoint pii =  [(NSValue*)[points objectAtIndex:i] CGPointValue];
        CGPoint pjj =  [(NSValue*)[points objectAtIndex:j] CGPointValue];
#endif
        area += pii.x * pjj.y;
        area -= pii.y * pjj.x;
    }

    area /= 2;
    return area;
}

double polygonAreaCGPoints(CGPoint* points, NSUInteger N) {
    double area = 0;

    NSUInteger j;
    for (NSUInteger i = 0; i < N; i++) {
        j = (i + 1) % N;
        CGPoint pii =  points[i];
        CGPoint pjj =  points[j];
        area += pii.x * pjj.y;
        area -= pii.y * pjj.x;
    }

    area /= 2;
    return area;
}

double cgpathArea(CGPathRef aPath) {
    NSMutableArray* a = [NSMutableArray new];
    CGPathApply(aPath, (__bridge void *)(a), convertToListOfPoints);
    return polygonArea(a);
}

CGPoint centroid(NSMutableArray* points) {
    double cx = 0, cy = 0;
    double area = polygonArea(points);

    NSUInteger i, j, n = [points count];

    if ( area == 0 ) {
        for (i = 0; i < n; i++) {
#if TARGET_OS_OSX
            NSPoint pii =  [(NSValue*)[points objectAtIndex:i] pointValue];
#else
            CGPoint pii =  [(NSValue*)[points objectAtIndex:i] CGPointValue];
#endif
            cx += pii.x;
            cy += pii.y;
        }
        cx /= (CGFloat)n;
        cy /= (CGFloat)n;
    }
    else {
        double factor = 0;
        for (i = 0; i < n; i++) {
            j = (i + 1) % n;
#if TARGET_OS_OSX
            NSPoint pii =  [(NSValue*)[points objectAtIndex:i] pointValue];
            NSPoint pjj =  [(NSValue*)[points objectAtIndex:j] pointValue];
#else
            CGPoint pii =  [(NSValue*)[points objectAtIndex:i] CGPointValue];
            CGPoint pjj =  [(NSValue*)[points objectAtIndex:j] CGPointValue];
#endif
            factor = (pii.x * pjj.y - pjj.x * pii.y);
            cx += (pii.x + pjj.x) * factor;
            cy += (pii.y + pjj.y) * factor;
        }
        
        cx *= 1 / (6.0 * area);
        cy *= 1 / (6.0 * area);
    }

    return CGPointMake(cx, cy);
}

CGPoint centroidCGPoints(CGPoint* points, NSUInteger N) {
    double cx = 0, cy = 0;
    double area = polygonAreaCGPoints(points, N);

    NSUInteger i, j;

    if ( area == 0 ) {
        for (i = 0; i < N; i++) {
            CGPoint pii = points[i];
            cx += pii.x;
            cy += pii.y;
        }
        cx /= (CGFloat)N;
        cy /= (CGFloat)N;
    }
    else {
        double factor = 0;
        for (i = 0; i < N; i++) {
            j = (i + 1) % N;
            CGPoint pii =  points[i];
            CGPoint pjj =  points[j];
            factor = (pii.x * pjj.y - pjj.x * pii.y);
            cx += (pii.x + pjj.x) * factor;
            cy += (pii.y + pjj.y) * factor;
        }
        
        cx *= 1 / (6.0 * area);
        cy *= 1 / (6.0 * area);
    }

    return CGPointMake(cx, cy);
}

//  Globals which should be set before calling these functions:
//
//  int    polyCorners  =  how many corners the polygon has (no repeats)
//  float  polyX[]      =  horizontal coordinates of corners
//  float  polyY[]      =  vertical coordinates of corners
//  float  x, y         =  point to be tested
//
//  The following global arrays should be allocated before calling these functions:
//
//  float  constant[] = storage for precalculated constants (same size as polyX)
//  float  multiple[] = storage for precalculated multipliers (same size as polyX)
//
//  (Globals are used in this example for purposes of speed.  Change as
//  desired.)
//
//  USAGE:
//  Call precalc_values() to initialize the constant[] and multiple[] arrays,
//  then call pointInPolygon(x, y) to determine if the point is in the polygon.
//
//  The function will return YES if the point x,y is inside the polygon, or
//  NO if it is not.  If the point is exactly on the edge of the polygon,
//  then the function may return YES or NO.
//
//  Note that division by zero is avoided because the division is protected
//  by the "if" clause which surrounds it.

CGPoint pointInCGPath(CGPathRef outerPath, CGPathRef innerPath) {
    CGPoint pts[2];
    pts[0] = GetCenterPointOfCGPath(outerPath);
    pts[1] = CGPathGetCurrentPoint(outerPath);
    // get constants in Ax + By + c = 0 equation
    //  𝐴=𝑦1−𝑦2, 𝐵=𝑥2−𝑥1 and 𝐶=𝑥1𝑦2−𝑥2𝑦1.
    double a = pts[1].y - pts[0].y;
    double b = pts[0].x - pts[1].x;
    double c = pts[1].x * pts[0].y - pts[0].x * pts[1].y;
    double m = a / b;
    c /= b;

    // Convert path to an array of points
    NSMutableArray* points = [NSMutableArray new];
    CGPathApply(innerPath, (__bridge void *)(points), convertToListOfPoints);
    
    CGFloat *constant = (CGFloat*)calloc((size_t)points.count, sizeof(CGFloat));
    CGFloat *multiple = (CGFloat*)calloc((size_t)points.count, sizeof(CGFloat));
    NSUInteger j = points.count - 1;
    for (NSUInteger i = 0; i < points.count; i++) {
#if TARGET_OS_OSX
        NSPoint pii =  [(NSValue*)[points objectAtIndex:i] pointValue];
        NSPoint pjj =  [(NSValue*)[points objectAtIndex:j] pointValue];
#else
        CGPoint pii =  [(NSValue*)[points objectAtIndex:i] CGPointValue];
        CGPoint pjj =  [(NSValue*)[points objectAtIndex:j] CGPointValue];
#endif
        if ( pjj.y == pii.y ) {
            constant[i] = pii.x;
            multiple[i] = 0;
        }
        else {
            constant[i] = pii.x - (pii.y * pjj.x) / (pjj.y - pii.y) + (pii.y * pii.x) / (pjj.y - pii.y);
            multiple[i] = (pjj.x - pii.x) / (pjj.y - pii.y);
        }
        j = i;
    }
  
    CGFloat dX = fabs(pts[1].x - pts[0].x) / 40.0;
    CGPoint pt;
    if ( pts[0].x < pts[1].x ) {
        pt.x = pts[1].x - dX;
    }
    else {
        pt.x = pts[1].x + dX;
    }
    pt.y = -m * pt.x - c;
    
    BOOL oddNode = NO;
//    BOOL samePaths = CGPathEqualToPath(outerPath, innerPath);
    while ( (pts[0].x < pts[1].x && pt.x >= pts[0].x) || (pts[0].x > pts[1].x && pt.x <= pts[0].x) ) {
//    while ( (!samePaths && !CGPathContainsPoint(outerPath, NULL, pt, YES) && CGPathContainsPoint(innerPath, NULL, pt, YES)) || (samePaths && !CGPathContainsPoint(outerPath, NULL, pt, YES)) ) {
        j = points.count - 1;
        for (NSUInteger i = 0; i < points.count; i++) {
#if TARGET_OS_OSX
            NSPoint pii =  [(NSValue*)[points objectAtIndex:i] pointValue];
            NSPoint pjj =  [(NSValue*)[points objectAtIndex:j] pointValue];
#else
            CGPoint pii =  [(NSValue*)[points objectAtIndex:i] CGPointValue];
            CGPoint pjj =  [(NSValue*)[points objectAtIndex:j] CGPointValue];
#endif
            if ( ( pii.y < pt.y && pjj.y > pt.y ) || ( pjj.y < pt.y && pii.y >= pt.y ) ) {
                oddNode ^= (pt.y * multiple[i] + constant[i] < pt.x);
            }
            j = i;
        }
        if (oddNode) {
            break;
        }
        if ( pts[0].x < pts[1].x ) {
            pt.x -= dX;
        }
        else {
            pt.x += dX;
        }
        pt.y = -m * pt.x - c;
    }
    
    free(constant);
    free(multiple);
    
    return pt;
}

#pragma mark -
#pragma mark Colour Conversions

static void ColorRGBtoHSL(CGFloat red, CGFloat green, CGFloat blue, CGFloat *hue, CGFloat *saturation, CGFloat *lightness);

static void ColorRGBtoHSL(CGFloat red, CGFloat green, CGFloat blue, CGFloat *hue, CGFloat *saturation, CGFloat *lightness) {
    CGFloat r = red;
    CGFloat g = green;
    CGFloat b = blue;

    CGFloat max = MAX(r, g);
    max = MAX(max, b);
    CGFloat min = MIN(r, g);
    min = MIN(min, b);

    CGFloat h = 0;
    CGFloat s = 0;
    CGFloat l = (max + min) / 2.0;

    if (max == min) {
        h = 0.0;
        s = 0.0;
    }

    else {
        CGFloat d = max - min;
        s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);

        if (max == r) {
            h = (g - b) / d + (g < b ? 6.0 : 0.0);
        }

        else if (max == g) {
            h = (b - r) / d + 2.0;
        }

        else if (max == b) {
            h = (r - g) / d + 4.0;
        }

        h /= 6.0;
    }

    if (hue) {
        *hue = h;
    }

    if (saturation) {
        *saturation = s;
    }

    if (lightness) {
        *lightness = l;
    }
}

//#import "DelaunayTriangle.h"
//#import "DelaunayTriangulation.h"
//#import "DelaunayEdge.h"
//#import "DelaunayPoint.h"

#include <search.h>

#define MAXISOCURVES 21

#pragma mark -
#pragma mark CPTContourFill Class

@implementation CPTContourFill

@synthesize fill;
@synthesize firstValue;
@synthesize secondValue;

@end


/** @defgroup plotAnimationContourPlot Contour Plot
 *  @brief Contour plot properties that can be animated using Core Animation.
 *  @ingroup plotAnimation
 **/

/** @if MacOnly
 *  @defgroup plotBindingsContourPlot Range Plot Bindings
 *  @brief Binding identifiers for contour plots.
 *  @ingroup plotBindings
 *  @endif
 **/

CPTContourPlotBinding const CPTContourPlotBindingXValues       = @"xValues";       ///< X values.
CPTContourPlotBinding const CPTContourPlotBindingYValues       = @"yValues";       ///< Y values.
CPTContourPlotBinding const CPTContourPlotBindingFunctionValues    = @"functionValues"; //< Contour base point function values.
CPTContourPlotBinding const CPTContourPlotBindingPlotSymbols = @"plotSymbols"; ///< Plot symbols.

/// @cond


@interface CPTContourPlot()

@property (nonatomic, readwrite, assign) NSUInteger noColumnsFirst;
@property (nonatomic, readwrite, assign) NSUInteger noRowsFirst;
@property (nonatomic, readwrite, assign) NSUInteger noColumnsSecondary;
@property (nonatomic, readwrite, assign) NSUInteger noRowsSecondary;
@property (nonatomic, readwrite, assign) NSUInteger noActualIsoCurves;

@property (nonatomic, readwrite, copy, nullable) CPTNumberArray *xValues;
@property (nonatomic, readwrite, copy, nullable) CPTNumberArray *yValues;
@property (nonatomic, readwrite, copy, nullable) CPTMutableNumericData *functionValues;
@property (nonatomic, readwrite, strong, nullable) CPTPlotSymbolArray *plotSymbols;
@property (nonatomic, readwrite, assign) NSUInteger pointingDeviceDownIndex;
@property (nonatomic, readwrite, assign) BOOL pointingDeviceDownOnLine;

@property (nonatomic, readwrite, assign) BOOL needsIsoCurvesUpdate;
@property (nonatomic, readwrite, assign) BOOL needsIsoCurvesRelabel;
@property (nonatomic, readwrite, assign) NSRange isoCurvesLabelIndexRange;
@property (nonatomic, readwrite, strong, nullable) CPTMutableNumberArray *isoCurvesIndices;
@property (nonatomic, readwrite, strong, nullable) NSMutableArray<CPTMutableAnnotationArray*> *isoCurvesLabelAnnotations;
@property (nonatomic, readwrite, strong, nullable) CPTMutableLineStyleArray *isoCurvesLineStyles;
@property (nonatomic, readwrite, strong, nullable) CPTMutableFillArray *isoCurvesFills;
@property (nonatomic, readwrite, strong, nullable) NSMutableArray<CPTContourFill*> *isoCurvesFillings;
@property (nonatomic, readwrite, strong, nullable) CPTMutableLayerArray *isoCurvesLabels;
@property (nonatomic, readwrite, strong, nullable) CPTMutableNumberArray *isoCurvesValues;
@property (nonatomic, readwrite, strong, nullable) CPTMutableNumberArray *isoCurvesNoStrips;
@property (nonatomic, readwrite, strong, nullable) NSMutableArray<CPTMutableValueArray*> *isoCurvesLabelsPositions;
@property (nonatomic, readwrite, strong, nullable) NSMutableArray<NSMutableArray*> *isoCurvesLabelsRotations;
@property (nonatomic, readwrite, strong, nullable) NSMutableArray<NSMutableArray*> *isoCurvesOuterLimits;
@property (nonatomic, readwrite, strong, nullable) CPTMutableValueArray *drawnIsoCurvesLabelsPositions;

@property (nonatomic, readwrite, assign) double stepX;
@property (nonatomic, readwrite, assign) double stepY;
@property (nonatomic, readwrite, assign) double maxWidthPixels;
@property (nonatomic, readwrite, assign) double maxHeightPixels;
@property (nonatomic, readwrite, assign) BOOL hasDiscontinuity;
@property (nonatomic, readwrite, assign) BOOL hasNans;
@property (nonatomic, readwrite, assign) BOOL hasInfinities;
@property (nonatomic, readwrite, assign) BOOL hasNegInfinities;
@property (nonatomic, readwrite, assign) CGRect greatestContourBox;
@property (nonatomic, readwrite, strong, nullable) CPTPlotRange *initialXRange;
@property (nonatomic, readwrite, strong, nullable) CPTPlotRange *initialYRange;
@property (nonatomic, readwrite, strong, nullable) CPTMutableNumberArray *previousLimits;
@property (nonatomic, readwrite, assign) BOOL firstRendition;
@property (nonatomic, readwrite, assign) BOOL previousFillIsoCurves;
@property (nonatomic, readwrite, assign) CGPoint originOfContext;
@property (nonatomic, readwrite, assign) CGFloat scaleOfContext;
#if TARGET_OS_OSX
@property (nonatomic, readwrite, strong, nullable) NSImage *macOSImage;
#endif

-(void)calculatePointsToDraw:(nonnull BOOL *)pointDrawFlags forPlotSpace:(nonnull CPTXYPlotSpace *)xyPlotSpace includeVisiblePointsOnly:(BOOL)visibleOnly numberOfPoints:(NSUInteger)dataCount;
-(void)calculateViewPoints:(nonnull CGPoint*)viewPoints withDrawPointFlags:(nonnull BOOL *)drawPointFlags numberOfPoints:(NSUInteger)dataCount;
-(NSUInteger)calculateDiscontinuousPoints:(nonnull CGPoint*)discontinuousPoints withDrawPointFlags:(nonnull BOOL *)drawPointFlags numberOfPoints:(NSUInteger)dataCount;
-(void)alignViewPointsToUserSpace:(nonnull CGPoint*)viewPoints withContext:(nonnull CGContextRef)context /*drawPointFlags:(nonnull BOOL *)drawPointFlag*/ numberOfPoints:(NSUInteger)dataCounts;
-(NSInteger)extremeDrawnPointIndexForFlags:(nonnull BOOL *)pointDrawFlags numberOfPoints:(NSUInteger)dataCount extremeNumIsLowerBound:(BOOL)isLowerBound;

-(CPTLineStyle *)isoCurveLineStyleForIndex:(NSUInteger)idx;

@end

/// @endcond

#pragma mark -

/** @brief A plot class representing a contour of values in one coordinate,
 *  such as typically used to show contours.
 *  @see See @ref plotAnimationContourPlot "Contour Plot" for a list of animatable properties.
 *  @if MacOnly
 *  @see See @ref plotBindingsContourPlot "Contour Plot Bindings" for a list of supported binding identifiers.
 *  @endif
 **/
@implementation CPTContourPlot

@dynamic xValues;
@dynamic yValues;
@dynamic functionValues;
@dynamic plotSymbols;

/** @property int noColumnsFirst
 *  @brief no columns in the first pass grid for contours
 *  Default is 32
 **/
@synthesize noColumnsFirst;

/** @property NSUInteger noRowsFirst
 *  @brief no rows in the first pass grid for contours
 *  Default is 32
 **/
@synthesize noRowsFirst;

/** @property NSUInteger noColumnsSecondary
 *  @brief no columns in the secondary pass grid for contours
 *  Default is 512
 **/
@synthesize noColumnsSecondary;

/** @property NSUInteger noRowsSecondary
 *  @brief no rows in the secondary pass grid for contours
 *  Default is 512
 **/
@synthesize noRowsSecondary;

/** @property NSUInteger noActualIsoCurves
 *  @brief no actual used isoCurves, nb, noIsoCurves is the number asked of the package
 *  Default is 21
 **/
@synthesize noActualIsoCurves;

/** @property nullable CPTPlotSymbol *plotSymbol
 *  @brief The plot symbol drawn at each point if the data source does not provide symbols.
 *  If @nil, no symbol is drawn.
 **/
@synthesize plotSymbol;

/** @property CPTLineStyle *isoCurveLineStyle
 *  @brief The line style of the contours.
 *  Set to @nil to have no Contours. Default is a black line style.
 **/
@synthesize isoCurveLineStyle;

/** @property CPTFill *isoCurveFill
 *  @brief The fill of the contours.
 *  Set to @nil to have no contour fill. Default is a white fill.
 **/
@synthesize isoCurveFill;

/** @property double minFunctionValue
 *  @brief The minimum value of the Contour Function.
 **/
@synthesize minFunctionValue;

/** @property double maxFunctionValue
 *  @brief The maximum value of the Contour Function.
 **/
@synthesize maxFunctionValue;

/** @property NSUInteger  noIsoCurves
 *  @brief The number of isocurves to look for.
 **/
@synthesize noIsoCurves;

/** @property CPTContourPlotInterpolation interpolation
 *  @brief The interpolation algorithm used for lines between data points.
 *  Default is #CPTContourPlotInterpolationLinear.
 **/
@synthesize interpolation;

/** @property CPTContourPlotCurvedInterpolationOption curvedInterpolationOption
 *  @brief The interpolation method used to generate the curved plot line (@ref interpolation = #CPTContourPlotInterpolationCurved)
 *  Default is #CPTContourPlotCurvedInterpolationNormal
 **/
@synthesize curvedInterpolationOption;

/** @property CGFloat curvedInterpolationCustomAlpha
 *  @brief The custom alpha value used when the #CPTContourPlotCurvedInterpolationCatmullCustomAlpha interpolation is selected.
 *  Default is @num{0.5}.
 *  @note Must be between @num{0.0} and @num{1.0}.
 **/
@synthesize curvedInterpolationCustomAlpha;

/** @internal
 *  @property NSUInteger pointingDeviceDownIndex
 *  @brief The index that was selected on the pointing device down event.
 **/
@synthesize pointingDeviceDownIndex;

/** @internal
 *  @property BOOL pointingDeviceDownOnLine
 *  @brief @YES if the pointing device down event occured on the plot line.
 **/
@synthesize pointingDeviceDownOnLine;

/** @property BOOL needsIsoCurvesUpdate
 *  @brief If @YES, the plot needs to have isoCurves recalculated before the layer content is drawn, else read from disk the saved contours and indices
 **/
@synthesize needsIsoCurvesUpdate;

/** @property BOOL adjustIsoCurvesLabelAnchors
 *  @brief If @YES, contour labels anchor points are adjusted automatically when the labels are positioned. If @NO, data labels anchor points do not change.
 **/
@synthesize adjustIsoCurvesLabelAnchors;

/** @property BOOL needsIsoCurveRelabel
 *  @brief If @YES, the plot needs to have isoCurves relabeled before the layer content is drawn.
 **/
@synthesize needsIsoCurvesRelabel;

/** @property NSRange isoCurvesLabelIndexRange
 *  @brief Range of isoCurves to be relabeled.
 **/
@synthesize isoCurvesLabelIndexRange;

/** @property CPTMutableNumberArray isoCurvesIndices
 *  @brief Indices of contours with actual strips.
 *     since number of isoCurves yoiu have ask to break the plot down to may no have contour strips for each plane
 **/
@synthesize isoCurvesIndices;

/** @property CPTMutableAnnotationArray *isoCurvesLabelAnnotations
 *  @brief Mutable annotation array for isoCurves labels.
 *  count should equal count of isoCurvesIndices
 **/
@synthesize isoCurvesLabelAnnotations;

/** @property CPTMutableLayerArray *isoCurvesLabels
 *  @brief CPTLayer array for isoCurves annotation content.
 *  count should equal count of isoCurvesValues
 **/
@synthesize isoCurvesLabels;

/** @property NSMutableArray<CPTMutableValueArray*> *isoCurvesLabelsPositions;
 *  @brief a mutable Array of NSValue CGPoint arrays for positions of isoCurves label annotation.
 *  count should equal count of isoCurvesValues
 **/
@synthesize isoCurvesLabelsPositions;

/** @property NSMutableArray<CPTMutableNumberArray*> *isoCurvesLabelsRotations;
 *  @brief a mutable Array of NSNumber  arrays for rotations of isoCurves label annotation.
 *  count should equal count of isoCurvesValues
 **/
@synthesize isoCurvesLabelsRotations;

/** @property NSMutableArray<CPTMutableNumberArray*> *isoCurvesOuterLimits;
 *  @brief a mutable Array of NSNumber  arrays for max, min range values on each boundary
 **/
@synthesize isoCurvesOuterLimits;

/** @property CPTMutableNumberArray *drawnIsoCurvesLabelsPositions;
 *  @brief a mutable Array of NSValues of CGPoints to collate positions isoCurvesLabels have been drawn
 *  can't have 2 labels on top of eache other
 **/
@synthesize drawnIsoCurvesLabelsPositions;

/** @property CPTMutableLineStyleArray *isoCurvesLineStyles
 *  @brief Mutable line style array for isoCurves line styles.
 *  count should equal noActualIsoCurves
 **/
@synthesize isoCurvesLineStyles;

/** @property CPTMutableFillArray *isoCurvesFills
 *  @brief Mutable fill array for isoCurves fills for all noActualIsoCurves
 *  count should equal noActualIsoCurves
 **/
@synthesize isoCurvesFills;

/** @property NSMutableArray<CPTContourFill*> *isoCurvesFillings
 *  @brief Mutable CPTContourFills array for isoCurves fills calculated internally
 *  count could be more than noActualIsoCurves
 **/
@synthesize isoCurvesFillings;

/** @property CPTMutableNumberArray *isoCurvesValues
 *  @brief Mutable number array to store the value of an isoCurve contour for all noActualIsoCurves.
 *  count should equal noIsoActualCurves
 **/
@synthesize isoCurvesValues;

/** @property CPTMutableNumberArray *isoCurvesNoStrips
 *  @brief Mutable number array to store the number of strips per isoCurve contour.
 *  count should equal noActualIsoCurves
 **/
@synthesize isoCurvesNoStrips;

/** @property CGFloat isoCurveLabelOffset
 *  @brief The distance that labels should be offset from their anchor points. The direction of the offset is defined by subclasses.
 *  count should equal count of isoCurvesIndices
 *  @ingroup plotAnimationAllPlots
 **/
@synthesize isoCurvesLabelOffset;

/** @property CGFloat isoCurveLabelRotation
 *  @brief The rotation of the data labels in radians.
 *  Set this property to @num{π/2} to have labels read up the screen, for example.
 *  @ingroup plotAnimationAllPlots
 **/
@synthesize isoCurvesLabelRotation;

/** @property CGPoint isoCurveLabelContentAnchorPoint
 *  @brief The anchor point for the content layer.
 **/
@synthesize isoCurvesLabelContentAnchorPoint;

/** @property nullable CPTTextStyle *isoCurveLabelTextStyle
 *  @brief The text style used to draw the data labels.
 *  Set this property to @nil to hide the isoCurve labels.
 **/
@synthesize isoCurvesLabelTextStyle;

/** @property nullable NSFormatter *isoCurveLabelFormatter
 *  @brief The number formatter used to format the data labels.
 *  Set this property to @nil to hide the data labels.
 *  If you need a non-numerical label, such as a date, you can use a formatter than turns
 *  the numerical plot coordinate into a string (e.g., @quote{Jan 10, 2010}).
 *  The CPTCalendarFormatter and CPTTimeFormatter classes are useful for this purpose.
 **/
@synthesize isoCurvesLabelFormatter;

/** @property nullable CPTShadow *isoCurveLabelShadow
 *  @brief The shadow applied to each isoCurve label.
 **/
@synthesize isoCurvesLabelShadow;

/** @property BOOL showIsoCurveLabels
 *  @brief If @YES, the plot will label the isoCurves.
 **/
@synthesize showIsoCurvesLabels;

/** @property CGFloat plotSymbolMarginForHitDetection
 *  @brief A margin added to each side of a symbol when determining whether it has been hit.
 *
 *  Default is zero. The margin is set in plot area view coordinates.
 **/
@synthesize plotSymbolMarginForHitDetection;

/** @property CGFloat plotLineMarginForHitDetection
 *  @brief A margin added to each side of a plot line when determining whether it has been hit.
 *
 *  Default is four points to each side of the line. The margin is set in plot area view coordinates.
 **/
@synthesize plotLineMarginForHitDetection;

/** @property BOOL allowSimultaneousSymbolAndPlotSelection
 *  @brief @YES if both symbol selection and line selection can happen on the same upEvent. If @NO
 *  then when an upEvent occurs on a symbol only the symbol will be selected, otherwise the line
 *  will be selected if the upEvent occured on the line.
 *
 *  Default is @NO.
 **/
@synthesize allowSimultaneousSymbolAndPlotSelection;

/** @property CPTContourDataSourceBlock  dataSourceBlock
 *  @brief block to supply contours with function evaluator.
 **/
@synthesize dataSourceBlock;

/** @property BOOL  functionPlot
 *  @brief contour plots can be function plots or actual data which has interpolated data
 *  to fill in gaps calling a dataSourceBlock also, this parameter distiguishes appropriate case.
 **/
@synthesize functionPlot;

/** @property CPTMutableNumberArray *limits
 *  @brief limits of the plot range
 **/
@synthesize limits;

/** @property BOOL easyOnTheEye
 *  @brief flag to generate easy on the eye contouring rather than max - min divided by no contours
 **/
@synthesize easyOnTheEye;

/** @property BOOL extrapolateToLimits
 *  @brief flag to indicating whether contours are extrapolated to the limits
 **/
@synthesize extrapolateToLimits;

/** @property BOOL fillIsoCurves
 *  @brief flag to indicating whether contours are filled
 **/
@synthesize fillIsoCurves;

/** @property BOOL joinContourLineStartToEnd
 *  @brief flag to indicating whether contours have the start point joined to end point
 *    default is YES
 **/
@synthesize joinContourLineStartToEnd;


@synthesize stepX;
@synthesize stepY;
@synthesize scaleX;
@synthesize scaleY;
@synthesize maxWidthPixels;
@synthesize maxHeightPixels;
@synthesize hasDiscontinuity;
@synthesize hasNans;
@synthesize hasInfinities;
@synthesize hasNegInfinities;

/** @property CGRect greatestContourBox
 *  @brief track the biggest contour size
 *    default is CGRectZero
 **/
@synthesize greatestContourBox;

/** @property CPTXYPlotRange  initialXRange
 *  @brief track the initialXRange
 **/
@synthesize initialXRange;

/** @property CPTXYPlotRange  initialYRange
 *  @brief track the initialYRange
 **/
@synthesize initialYRange;

/** @property CPTMutableNumberArray  previousLimits
 *  @brief track the previous limits (4 elements)
 **/
@synthesize previousLimits;

/** @property BOOL  firstRendition
 *  @brief keep track of whether first time rendering the contour plot
 *    default is YES
 **/
@synthesize firstRendition;

/** @property BOOL  previousFillIsoCurves
 *  @brief keep track of the previous fillIsoCurves
 *  determines if new contour calculations are required or can use previous
 *    default is fillIsoCurves
 **/
@synthesize previousFillIsoCurves;

/** @property CGPoint originOfContext
 *  @brief origin point of  current Drawing context
 *    default is CGPointZero
 **/
@synthesize originOfContext;

/** @property CGFloat scaleOfContext
 *  @brief scaleof  current Drawing context
 *    default is CGFloat 1
 **/
@synthesize scaleOfContext;

#if TARGET_OS_OSX
@synthesize macOSImage;
#endif

/// @cond

#if TARGET_OS_SIMULATOR || TARGET_OS_IPHONE
#else
+(void)initialize {
    if ( self == [CPTContourPlot class] ) {
        [self exposeBinding:CPTContourPlotBindingXValues];
        [self exposeBinding:CPTContourPlotBindingYValues];
        [self exposeBinding:CPTContourPlotBindingFunctionValues];
        [self exposeBinding:CPTContourPlotBindingPlotSymbols];
    }
}

#endif

/// @endcond

#pragma mark -
#pragma mark Initialisation & Cleanup

/// @name Initialization
/// @{

/** @brief Initializes a newly allocated CPTContourPlot object with the provided frame rectangle.
 *
 *  This is the designated initializer. The initialized layer will have the following properties:
 *  - @ref isoCurveLineStyle = default line style
 *  - @ref labelField = #CPTContourPlotFieldX
 *
 *  @param newFrame The frame rectangle.
 *  @return The initialized CPTContourPlot object.
 **/
-(nonnull instancetype)initWithFrame:(CGRect)newFrame {
    
    if ( (self = [super initWithFrame:newFrame]) ) {
        
        needsIsoCurvesUpdate = YES;
        
        plotSymbol               = nil;
        isoCurveLineStyle        = [[CPTLineStyle alloc] init];
        noIsoCurves = MAXISOCURVES;
        
        noColumnsFirst = 64;
        noRowsFirst = 64;
        noColumnsSecondary = 1024;
        noRowsSecondary = 1024;
        greatestContourBox = CGRectZero;
        firstRendition = YES;
        
        plotSymbolMarginForHitDetection = (CGFloat)0.0;
        plotLineMarginForHitDetection   = (CGFloat)4.0;
        pointingDeviceDownOnLine        = NO;

        scaleX = CPTDecimalDoubleValue(self.plotArea.widthDecimal);
        scaleY = CPTDecimalDoubleValue(self.plotArea.heightDecimal);
        maxWidthPixels = CPTDecimalDoubleValue(self.plotArea.widthDecimal);
        maxHeightPixels = CPTDecimalDoubleValue(self.plotArea.heightDecimal);
        limits = [CPTMutableNumberArray arrayWithObjects:@0, @0, @0, @0, nil];
        maxFunctionValue = 0.0;
        minFunctionValue = 0.0;
        joinContourLineStartToEnd = YES;
        hasDiscontinuity = NO;
        
        self.labelField = CPTContourPlotFieldX; // but also need CPTContourPlotFieldY as 2 dimensional
        self.isoCurvesLabelContentAnchorPoint = CGPointMake(0.5, 0.5);
    }
    return self;
}

/// @}

/// @cond

-(nonnull instancetype)initWithLayer:(nonnull id)layer {
    if ( (self = [super initWithLayer:layer]) ) {
        CPTContourPlot *theLayer = (CPTContourPlot*)layer;
        
        needsIsoCurvesUpdate = YES;

        plotSymbol              = theLayer->plotSymbol;
        isoCurvesIndices        = theLayer->isoCurvesIndices;
        isoCurvesValues          = theLayer->isoCurvesValues;
        isoCurveLineStyle        = theLayer->isoCurveLineStyle;
        isoCurvesFills           = theLayer->isoCurvesFills;
        isoCurvesFillings        = theLayer->isoCurvesFillings;
        isoCurvesLabels          = theLayer->isoCurvesLabels;
        isoCurvesLabelAnnotations = theLayer->isoCurvesLabelAnnotations;
        isoCurvesLabelsPositions = theLayer->isoCurvesLabelsPositions;
        isoCurvesLabelsRotations = theLayer->isoCurvesLabelsRotations;
        isoCurvesNoStrips        = theLayer->isoCurvesNoStrips;
        
        noIsoCurves = theLayer->noIsoCurves;
        noColumnsFirst = theLayer->noColumnsFirst;
        noRowsFirst = theLayer->noRowsFirst;
        noColumnsSecondary = theLayer->noColumnsSecondary;
        noRowsSecondary = theLayer->noRowsSecondary;
        firstRendition = YES;

        plotSymbolMarginForHitDetection = theLayer->plotSymbolMarginForHitDetection;
        plotLineMarginForHitDetection   = theLayer->plotLineMarginForHitDetection;
        pointingDeviceDownOnLine = theLayer->pointingDeviceDownOnLine;
        pointingDeviceDownIndex = NSNotFound;
    }
    return self;
}

- (void)dealloc {
    [self clearOut];
    
    if(self.isoCurvesIndices != nil) {
        [self.isoCurvesIndices removeAllObjects];
        self.isoCurvesIndices = nil;
    }
    
    if(self.isoCurvesLabelAnnotations != nil) {
        [self.isoCurvesLabelAnnotations removeAllObjects];
        self.isoCurvesLabelAnnotations = nil;
    }
    
#if TARGET_OS_OSX
    self.macOSImage = nil;
#endif
}

- (void)clearOut {
    if(self.isoCurvesValues != nil) {
        [self.isoCurvesValues removeAllObjects];
        self.isoCurvesValues = nil;
    }
    if(self.isoCurvesLineStyles != nil) {
        [self.isoCurvesLineStyles removeAllObjects];
        self.isoCurvesLineStyles = nil;
    }
    if(self.isoCurvesFills != nil) {
        [self.isoCurvesFills removeAllObjects];
        self.isoCurvesFills = nil;
    }
    if(self.isoCurvesFillings != nil) {
        [self.isoCurvesFillings removeAllObjects];
        self.isoCurvesFillings = nil;
    }
    if(self.isoCurvesLabels != nil) {
        [self.isoCurvesLabels removeAllObjects];
        self.isoCurvesLabels = nil;
    }

    if(self.isoCurvesLabelsPositions != nil) {
        [self.isoCurvesLabelsPositions removeAllObjects];
        self.isoCurvesLabelsPositions = nil;
    }
    if(self.isoCurvesLabelsRotations != nil) {
        [self.isoCurvesLabelsRotations removeAllObjects];
        self.isoCurvesLabelsRotations = nil;
    }
    if(self.isoCurvesNoStrips != nil) {
        [self.isoCurvesNoStrips removeAllObjects];
        self.isoCurvesNoStrips = nil;
    }
    if(self.drawnIsoCurvesLabelsPositions != nil) {
        [self.drawnIsoCurvesLabelsPositions removeAllObjects];
        self.drawnIsoCurvesLabelsPositions = nil;
    }
}

#pragma mark -
#pragma mark NSCoding Methods

/// @cond

-(void)encodeWithCoder:(nonnull NSCoder *)coder {
    [super encodeWithCoder:coder];
    
    [coder encodeObject:self.isoCurveLineStyle forKey:@"CPTContourPlot.isoCurveLineStyle"];
    [coder encodeObject:self.isoCurveFill forKey:@"CPTContourPlot.isoCurveFill"];
    [coder encodeDouble:self.minFunctionValue forKey:@"CPTContourPlot.minFunctionValue"];
    [coder encodeDouble:self.maxFunctionValue forKey:@"CPTContourPlot.maxFunctionValue"];
    [coder encodeInteger:(NSInteger)self.noIsoCurves forKey:@"CPTContourPlot.noIsoCurves"];
    [coder encodeInteger:(NSInteger)self.interpolation forKey:@"CPTContourPlot.interpolation"];
    [coder encodeInteger:(NSInteger)self.curvedInterpolationOption forKey:@"CPTContourPlot.curvedInterpolationOption"];
    [coder encodeCGFloat:self.curvedInterpolationCustomAlpha forKey:@"CPTContourPlot.curvedInterpolationCustomAlpha"];
    [coder encodeCGFloat:self.isoCurvesLabelOffset forKey:@"CPTContourPlot.isoCurvesLabelOffset"];
    [coder encodeCGFloat:self.isoCurvesLabelRotation forKey:@"CPTContourPlot.isoCurvesLabelRotation"];
#if TARGET_OS_OSX
    [coder encodePoint:(NSPoint)self.isoCurvesLabelContentAnchorPoint forKey:@"CPTContourPlot.isoCurvesLabelContentAnchorPoint"];
#else
    [coder encodeCGPoint:self.isoCurvesLabelContentAnchorPoint forKey:@"CPTContourPlot.isoCurvesLabelContentAnchorPoint"];
#endif
    [coder encodeObject:self.isoCurvesLabelTextStyle forKey:@"CPTContourPlot.isoCurvesLabelTextStyle"];
    [coder encodeObject:self.isoCurvesLabelFormatter forKey:@"CPTContourPlot.isoCurvesLabelFormatter"];
    [coder encodeObject:self.isoCurvesLabelShadow forKey:@"CPTContourPlot.isoCurvesLabelShadow"];
    [coder encodeBool:self.showIsoCurvesLabels forKey:@"CPTContourPlot.showIsoCurvesLabels"];
    
    // No need to archive these properties:
    // pointingDeviceDownIndex
}

-(nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    if ( (self = [super initWithCoder:coder]) ) {
        isoCurveLineStyle = [[coder decodeObjectOfClass:[CPTLineStyle class]
                                            forKey:@"CPTContourPlot.isoCurveLineStyle"] copy];
        isoCurveFill = [[coder decodeObjectOfClass:[CPTFill class]
                                            forKey:@"CPTContourPlot.isoCurveFill"] copy];
        minFunctionValue = [coder decodeDoubleForKey:@"CPTContourPlot.minFunctionValue"];
        maxFunctionValue = [coder decodeDoubleForKey:@"CPTContourPlot.maxFunctionValue"];
        noIsoCurves = (NSUInteger)[coder decodeIntegerForKey:@"CPTContourPlot.noIsoCurves"];
        interpolation = (CPTContourPlotInterpolation)[coder decodeIntegerForKey:@"CPTContourPlot.interpolation"];
        curvedInterpolationOption = (CPTContourPlotCurvedInterpolationOption)[coder decodeIntegerForKey:@"CPTContourPlot.curvedInterpolationOption"];
        curvedInterpolationCustomAlpha = [coder decodeCGFloatForKey:@"CPTContourPlot.curvedInterpolationCustomAlpha"];
        isoCurvesLabelOffset = [coder decodeCGFloatForKey:@"CPTContourPlot.isoCurvesLabelOffset"];
        isoCurvesLabelRotation = [coder decodeCGFloatForKey:@"CPTContourPlot.isoCurvesLabelRotation"];
#if TARGET_OS_OSX
        isoCurvesLabelContentAnchorPoint = (CGPoint)[coder decodePointForKey:@"CPTContourPlot.isoCurvesLabelContentAnchorPoint"];
#else
        isoCurvesLabelContentAnchorPoint = [coder decodeCGPointForKey:@"CPTContourPlot.isoCurvesLabelContentAnchorPoint"];
#endif
        isoCurvesLabelTextStyle = [[coder decodeObjectOfClass:[CPTTextStyle class]
                                                       forKey:@"CPTContourPlot.isoCurvesLabelTextStyle"] copy];
        isoCurvesLabelFormatter = [coder decodeObjectForKey:@"CPTContourPlot.isoCurvesLabelFormatter"];
        isoCurvesLabelShadow = [[coder decodeObjectOfClass:[NSFormatter class]
                                                    forKey:@"CPTContourPlot.isoCurvesLabelShadow"] copy];
        showIsoCurvesLabels = [coder decodeBoolForKey:@"CPTContourPlot.showIsoCurvesLabels"];
        
        pointingDeviceDownIndex = NSNotFound;
    }
    return self;
}

/// @endcond

#pragma mark -
#pragma mark NSSecureCoding Methods

/// @cond

+(BOOL)supportsSecureCoding {
    return YES;
}

/// @endcond


#pragma mark -
#pragma mark Determining Which Points to Draw

/// @cond

-(void)calculatePointsToDraw:(nonnull BOOL *)pointDrawFlags forPlotSpace:(nonnull CPTXYPlotSpace *)xyPlotSpace includeVisiblePointsOnly:(BOOL)visibleOnly numberOfPoints:(NSUInteger)dataCount {
    if ( dataCount == 0 ) {
        return;
    }

    CPTPlotRangeComparisonResult *xRangeFlags = (CPTPlotRangeComparisonResult*)calloc(dataCount, sizeof(CPTPlotRangeComparisonResult));
    CPTPlotRangeComparisonResult *yRangeFlags = (CPTPlotRangeComparisonResult*)calloc(dataCount, sizeof(CPTPlotRangeComparisonResult));
    BOOL *nanFlags                            = (BOOL*)calloc(dataCount, sizeof(BOOL));

    CPTPlotRange *xRange = xyPlotSpace.xRange;
    CPTPlotRange *yRange = xyPlotSpace.yRange;

    // Determine where each point lies in relation to range
    if ( self.doublePrecisionCache ) {
        const double *xBytes = (const double *)[self cachedNumbersForField:CPTContourPlotFieldX].data.bytes;
        const double *yBytes = (const double *)[self cachedNumbersForField:CPTContourPlotFieldY].data.bytes;
//        const double *functionValueBytes   = (const double *)([self cachedNumbersForField:CPTContourPlotFieldFunctionValue].data.bytes);
        

        dispatch_apply(dataCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
            const double x = xBytes[i];
            const double y = yBytes[i];
//            const double functionValue  = functionValueBytes[i];

            xRangeFlags[i] = [xRange compareToDouble:x];
            yRangeFlags[i] = [yRange compareToDouble:y];
            nanFlags[i]    = isnan(x) || isnan(y) /*|| isnan(functionValue)*/;
        });
    }
    else {
        const NSDecimal *xBytes = (const NSDecimal *)[self cachedNumbersForField:CPTContourPlotFieldX].data.bytes;
        const NSDecimal *yBytes = (const NSDecimal *)[self cachedNumbersForField:CPTContourPlotFieldY].data.bytes;
//        const NSDecimal *functionValueBytes  = (const NSDecimal *)([self cachedNumbersForField:CPTContourPlotFieldFunctionValue].data.bytes);
        
        dispatch_apply(dataCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
            const NSDecimal x = xBytes[i];
            const NSDecimal y = yBytes[i];
//            const NSDecimal functionValue  = functionValueBytes[i];

            xRangeFlags[i] = [xRange compareToDecimal:x];
            yRangeFlags[i] = [yRange compareToDecimal:y];
            nanFlags[i]    = NSDecimalIsNotANumber(&x) || NSDecimalIsNotANumber(&y) /*|| NSDecimalIsNotANumber(&functionValue)*/;
        });
    }

    for ( NSUInteger i = 0; i < dataCount; i++ ) {
        BOOL drawPoint = (xRangeFlags[i] == CPTPlotRangeComparisonResultNumberInRange) &&
                         (yRangeFlags[i] == CPTPlotRangeComparisonResultNumberInRange) &&
                         !nanFlags[i];

        pointDrawFlags[i] = drawPoint;
    }

    free(xRangeFlags);
    free(yRangeFlags);
    free(nanFlags);
}

-(void)calculateViewPoints:(nonnull CGPoint*)viewPoints withDrawPointFlags:(nonnull BOOL *)drawPointFlags numberOfPoints:(NSUInteger)dataCount {
    CPTPlotSpace *thePlotSpace = self.plotSpace;

    // Calculate points
    if ( self.doublePrecisionCache ) {
        const double *xBytes     = (const double *)([self cachedNumbersForField:CPTContourPlotFieldX].data.bytes);
        const double *yBytes     = (const double *)([self cachedNumbersForField:CPTContourPlotFieldY].data.bytes);
        const double *functionValueBytes   = (const double *)([self cachedNumbersForField:CPTContourPlotFieldFunctionValue].data.bytes);
        self.minFunctionValue = DBL_MAX;
        self.maxFunctionValue = -DBL_MAX;
        
        dispatch_apply(dataCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
            const double x     = xBytes[i];
            const double y     = yBytes[i];
            double functionValue  = functionValueBytes[i];
            
//            if ( isnan(functionValue) ) {
//                functionValue = -0.0;
//            }
            
            if ( !drawPointFlags[i] || isnan(x) || isnan(y) || isnan(functionValue)/* functionValue == -0.0*/ ) {
                viewPoints[i].x = (CGFloat)NAN; // depending coordinates
                viewPoints[i].y = (CGFloat)NAN;
            }
            else {
                double plotPoint[2];
                plotPoint[CPTCoordinateX] = x;
                plotPoint[CPTCoordinateY] = y;
                CGPoint pos               = [thePlotSpace plotAreaViewPointForDoublePrecisionPlotPoint:plotPoint numberOfCoordinates:2];
                viewPoints[i].x           = pos.x;
                viewPoints[i].y           = pos.y;
                
                if( functionValue == -DBL_MAX || isinf(-functionValue) ) {
                    self.hasNegInfinities = YES;
                }
                else if( functionValue == DBL_MAX || isinf(functionValue) ) {
                    self.hasInfinities = YES;
                }
                else {
                    self.minFunctionValue = MIN(self.minFunctionValue, functionValue);
                    self.maxFunctionValue = MAX(self.maxFunctionValue, functionValue);
                }
            }
        });
    }
    else {
        const NSDecimal *xBytes     = (const NSDecimal *)([self cachedNumbersForField:CPTContourPlotFieldX].data.bytes);
        const NSDecimal *yBytes     = (const NSDecimal *)([self cachedNumbersForField:CPTContourPlotFieldY].data.bytes);
        const NSDecimal *functionValueBytes  = (const NSDecimal *)([self cachedNumbersForField:CPTContourPlotFieldFunctionValue].data.bytes);
        //__block NSDecimal negZero = [[NSDecimalNumber numberWithDouble:-0.0] decimalValue];
        
        dispatch_apply(dataCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
            const NSDecimal x     = xBytes[i];
            const NSDecimal y     = yBytes[i];
            NSDecimal functionValue  = functionValueBytes[i];
            
//            if ( NSDecimalIsNotANumber(&functionValue) ) {
//                functionValue = negZero;
//            }

            if ( !drawPointFlags[i] || NSDecimalIsNotANumber(&x) || NSDecimalIsNotANumber(&y) || NSDecimalIsNotANumber(&functionValue) /*|| NSDecimalCompare(&functionValue, &negZero)*/ ) {
                viewPoints[i].x = (CGFloat)NAN;//CPTNAN; // depending coordinates
                viewPoints[i].y = (CGFloat)NAN;
            }
            else {
                NSDecimal plotPoint[2];
                plotPoint[CPTCoordinateX] = x;
                plotPoint[CPTCoordinateY] = y;
                CGPoint pos               = [thePlotSpace plotAreaViewPointForPlotPoint:plotPoint numberOfCoordinates:2];
                viewPoints[i].x           = pos.x;
                viewPoints[i].y           = pos.y;
                
                if( CPTDecimalDoubleValue(functionValue) == -DBL_MAX || isinf(-CPTDecimalDoubleValue(functionValue)) ) {
                    self.hasNegInfinities = YES;
                }
                else if( CPTDecimalDoubleValue(functionValue) == DBL_MAX || isinf(CPTDecimalDoubleValue(functionValue)) ) {
                    self.hasInfinities = YES;
                }
                else {
                    self.minFunctionValue = MIN(self.minFunctionValue, CPTDecimalDoubleValue(functionValue));
                    self.maxFunctionValue = MAX(self.maxFunctionValue, CPTDecimalDoubleValue(functionValue));
                }
            }
        });
    }
}

-(NSUInteger)calculateDiscontinuousPoints:(nonnull CGPoint*)discontinuousPoints withDrawPointFlags:(nonnull BOOL *)drawPointFlags numberOfPoints:(NSUInteger)dataCount {
    CPTPlotSpace *thePlotSpace = self.plotSpace;
    size_t count = 0;
    
    // Calculate points
    if ( self.doublePrecisionCache ) {
        const double *xBytes     = (const double *)([self cachedNumbersForField:CPTContourPlotFieldX].data.bytes);
        const double *yBytes     = (const double *)([self cachedNumbersForField:CPTContourPlotFieldY].data.bytes);
        const double *functionValueBytes   = (const double *)([self cachedNumbersForField:CPTContourPlotFieldFunctionValue].data.bytes);
        
        for ( size_t i = 0; i < dataCount; i++ ) {
            const double x     = xBytes[i];
            const double y     = yBytes[i];
            const double functionValue  = functionValueBytes[i];
            
            if ( drawPointFlags[i] && (isinf(-functionValue) || isinf(functionValue) || isnan(functionValue) || (functionValue == 0.0 && signValue(functionValue) == -1)) ) {
                double plotPoint[2];
                plotPoint[CPTCoordinateX] = x;
                plotPoint[CPTCoordinateY] = y;
                CGPoint pos               = [thePlotSpace plotAreaViewPointForDoublePrecisionPlotPoint:plotPoint numberOfCoordinates:2];
                discontinuousPoints[count].x           = pos.x;
                discontinuousPoints[count].y           = pos.y;
                count++;
            }
        }
    }
    else {
        const NSDecimal *xBytes     = (const NSDecimal *)([self cachedNumbersForField:CPTContourPlotFieldX].data.bytes);
        const NSDecimal *yBytes     = (const NSDecimal *)([self cachedNumbersForField:CPTContourPlotFieldY].data.bytes);
        const NSDecimal *functionValueBytes  = (const NSDecimal *)([self cachedNumbersForField:CPTContourPlotFieldFunctionValue].data.bytes);
        NSDecimal negZero = [[NSDecimalNumber decimalNumberWithMantissa:0 exponent:1 isNegative:YES] decimalValue];
        
        for ( size_t i = 0; i < dataCount; i++ ) {
            const NSDecimal x     = xBytes[i];
            const NSDecimal y     = yBytes[i];
            const NSDecimal functionValue  = functionValueBytes[i];

            if ( !drawPointFlags[i] && (isinf(-CPTDecimalDoubleValue(functionValue)) || isinf(CPTDecimalDoubleValue(functionValue)) || NSDecimalIsNotANumber(&functionValue) || NSDecimalCompare(&functionValue, &negZero)) ) {
                NSDecimal plotPoint[2];
                plotPoint[CPTCoordinateX] = x;
                plotPoint[CPTCoordinateY] = y;
                CGPoint pos               = [thePlotSpace plotAreaViewPointForPlotPoint:plotPoint numberOfCoordinates:2];
                discontinuousPoints[count].x           = pos.x;
                discontinuousPoints[count].y           = pos.y;
                count++;
            }
        }
    }
    
    return (NSUInteger)count;
}

-(void)alignViewPointsToUserSpace:(nonnull CGPoint*)viewPoints withContext:(nonnull CGContextRef)context numberOfPoints:(NSUInteger)dataCount {
    // Align to device pixels if there is a data line.
    // Otherwise, align to view space, so fills are sharp at edges.
    if ( self.isoCurveLineStyle.lineWidth > (CGFloat)0.0 ) {
        dispatch_apply(dataCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
                CGFloat x       = viewPoints[i].x;
                CGFloat y       = viewPoints[i].y;
                CGPoint pos     = CPTAlignPointToUserSpace(context,  CGPointMake( (CGFloat)x, (CGFloat)y) );
                viewPoints[i].x = pos.x;
                viewPoints[i].y = pos.y;
        });
    }
    else {
        dispatch_apply(dataCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
//            if ( drawPointFlags[i] ) {
                CGFloat x       = viewPoints[i].x;
                CGFloat y       = viewPoints[i].y;
                CGPoint pos     = CPTAlignIntegralPointToUserSpace(context, CGPointMake( (CGFloat)x, (CGFloat)y) );
                viewPoints[i].x = pos.x;
                viewPoints[i].y = pos.y;
//            }
        });
    }
}

-(NSInteger)extremeDrawnPointIndexForFlags:(nonnull BOOL *)pointDrawFlags numberOfPoints:(NSUInteger)dataCount extremeNumIsLowerBound:(BOOL)isLowerBound {
    NSInteger result = NSNotFound;
    NSInteger delta  = (isLowerBound ? 1 : -1);

    if ( dataCount > 0 ) {
        NSUInteger initialIndex = (isLowerBound ? 0 : dataCount - 1);
        for ( NSInteger i = (NSInteger)initialIndex; i < (NSInteger)dataCount; i += delta ) {
            if ( pointDrawFlags[i] ) {
                result = i;
                break;
            }
            if ( (delta < 0) && (i == 0) ) {
                break;
            }
        }
    }
    return result;
}

/// @endcond

#pragma mark -
#pragma mark Data Loading

/// @cond

-(void)reloadDataInIndexRange:(NSRange)indexRange
{
    [super reloadDataInIndexRange:indexRange];
    
    // Contour line styles
    [self reloadContourLineStylesInIsoCurveIndexRange:NSMakeRange(0, self.isoCurvesIndices.count)];
}

-(void)reloadPlotDataInIndexRange:(NSRange)indexRange {
    [super reloadPlotDataInIndexRange:indexRange];

    if ( ![self loadNumbersForAllFieldsFromDataSourceInRecordIndexRange:indexRange] ) {
        id<CPTContourPlotDataSource> theDataSource = (id<CPTContourPlotDataSource>)self.dataSource;

        if ( theDataSource ) {
            id newXValues = [self numbersFromDataSourceForField:CPTContourPlotFieldX recordIndexRange:indexRange];
            [self cacheNumbers:newXValues forField:CPTContourPlotFieldX atRecordIndex:indexRange.location];
            id newYValues = [self numbersFromDataSourceForField:CPTContourPlotFieldY recordIndexRange:indexRange];
            [self cacheNumbers:newYValues forField:CPTContourPlotFieldY atRecordIndex:indexRange.location];
            id newFunctionValues = [self numbersFromDataSourceForField:CPTContourPlotFieldFunctionValue recordIndexRange:indexRange];
            [self cacheNumbers:newFunctionValues forField:CPTContourPlotFieldFunctionValue atRecordIndex:indexRange.location];
        }
//        else {
//            self.xValues     = nil;
//            self.yValues     = nil;
//            self.functionValues  = nil;
//        }
    }
}

/// @endcond

/**
 *  @brief Reload all plot symbols from the data source immediately.
 **/
-(void)reloadPlotSymbols
{
    [self reloadPlotSymbolsInIndexRange:NSMakeRange(0, self.cachedDataCount)];
}

/** @brief Reload plot symbols in the given index range from the data source immediately.
 *  @param indexRange The index range to load.
 **/
-(void)reloadPlotSymbolsInIndexRange:(NSRange)indexRange
{
    id<CPTContourPlotDataSource> theDataSource = (id<CPTContourPlotDataSource>)self.dataSource;

    BOOL needsLegendUpdate = NO;

    if ( [theDataSource respondsToSelector:@selector(symbolsForContourPlot:recordIndexRange:)] ) {
        needsLegendUpdate = YES;

        [self cacheArray:[theDataSource symbolsForContourPlot:self recordIndexRange:indexRange]
                  forKey:CPTContourPlotBindingPlotSymbols
           atRecordIndex:indexRange.location];
    }
    else if ( [theDataSource respondsToSelector:@selector(symbolForContourPlot:recordIndex:)] ) {
        needsLegendUpdate = YES;

        id nilObject                     = [CPTPlot nilData];
        CPTMutablePlotSymbolArray *array = [[NSMutableArray alloc] initWithCapacity:indexRange.length];
        NSUInteger maxIndex              = NSMaxRange(indexRange);

        for ( NSUInteger idx = indexRange.location; idx < maxIndex; idx++ ) {
            CPTPlotSymbol *symbol = [theDataSource symbolForContourPlot:self recordIndex:idx];
            if ( symbol ) {
                [array addObject:symbol];
            }
            else {
                [array addObject:nilObject];
            }
        }

        [self cacheArray:array forKey:CPTContourPlotBindingPlotSymbols atRecordIndex:indexRange.location];
    }

    // Legend
    if ( needsLegendUpdate ) {
        [[NSNotificationCenter defaultCenter] postNotificationName:CPTLegendNeedsRedrawForPlotNotification object:self];
    }

    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark Symbols

/** @brief Returns the plot symbol to use for a given index.
 *  @param idx The index of the record.
 *  @return The plot symbol to use, or @nil if no plot symbol should be drawn.
 **/
-(nullable CPTPlotSymbol *)plotSymbolForRecordIndex:(NSUInteger)idx
{
    CPTPlotSymbol *symbol = [self cachedValueForKey:CPTContourPlotBindingPlotSymbols recordIndex:idx];

    if ((symbol == nil) || (symbol == [CPTPlot nilData])) {
        symbol = self.plotSymbol;
    }

    return symbol;
}

#pragma mark -
#pragma mark Line Styles
/**
 *  @brief Reload all contour styles from the data source immediately.
 **/
-(void)reloadContourLineStyles {
    [self reloadContourLineStylesInIsoCurveIndexRange:NSMakeRange(0, self.isoCurvesValues.count)];
}

/** @brief Reload contour line styles in the given index range from the data source immediately.
 *  @param indexRange The index range to load.
 **/
-(void)reloadContourLineStylesInIsoCurveIndexRange:(NSRange)indexRange {
    id<CPTContourPlotDataSource> theDataSource = (id<CPTContourPlotDataSource>)self.dataSource;
    
    if ([theDataSource isKindOfClass:[CPTFieldFunctionDataSource class]]) {
        theDataSource = (id<CPTContourPlotDataSource>)self.appearanceDataSource;
    }

    BOOL needsLegendUpdate = NO;

    if ( [theDataSource respondsToSelector:@selector(lineStylesForContourPlot:isoCurveIndices:isoCurveIndicesSize:)] ) {
        needsLegendUpdate = YES;

        id nilObject                    = [CPTPlot nilData];
        NSUInteger maxIndex             = NSMaxRange(indexRange);
        NSUInteger *indices = (NSUInteger*)calloc(maxIndex - indexRange.location, sizeof(NSUInteger));
        for ( NSUInteger idx = indexRange.location; idx < maxIndex; idx++ ) {
            indices[idx - indexRange.location] = [[self.isoCurvesIndices objectAtIndex:idx] unsignedIntegerValue];
        }
        CPTLineStyleArray *dataSourceLineStyles = [theDataSource lineStylesForContourPlot:self isoCurveIndices:indices isoCurveIndicesSize:maxIndex - indexRange.location];
        for ( NSUInteger idx = 0; idx < maxIndex - indexRange.location; idx++ ) {
            CPTMutableLineStyle *dataSourceLineStyle = [CPTMutableLineStyle lineStyleWithStyle: [dataSourceLineStyles objectAtIndex:indices[idx]]];
            if ( dataSourceLineStyle ) {
                [self.isoCurvesLineStyles replaceObjectAtIndex:indices[idx] withObject:dataSourceLineStyle];
            }
            else {
                [self.isoCurvesLineStyles replaceObjectAtIndex:indices[idx] withObject:nilObject];
            }
        }
        free(indices);
    }
    else if ( [theDataSource respondsToSelector:@selector(lineStyleForContourPlot:isoCurveIndex:)] ) {
        needsLegendUpdate = YES;

        id nilObject                    = [CPTPlot nilData];
        NSUInteger maxIndex             = NSMaxRange(indexRange);
//        NSUInteger actualIndex;
        for ( NSUInteger idx = indexRange.location; idx < maxIndex; idx++ ) {
            //if ( idx - indexRange.location < self.isoCurvesIndices.count) {
//                actualIndex = [[self.isoCurvesIndices objectAtIndex:idx] unsignedIntegerValue];
                CPTMutableLineStyle *dataSourceLineStyle = [CPTMutableLineStyle lineStyleWithStyle: [theDataSource lineStyleForContourPlot:self isoCurveIndex:idx/*actualIndex*/]];
                if ( dataSourceLineStyle ) {
                    [self.isoCurvesLineStyles replaceObjectAtIndex:idx/*actualIndex*/ withObject:dataSourceLineStyle];
                }
                else {
                    [self.isoCurvesLineStyles replaceObjectAtIndex:idx/*actualIndex*/ withObject:nilObject];
                }
         //   }
        }
    }

    // Legend
    if ( needsLegendUpdate ) {
        [[NSNotificationCenter defaultCenter] postNotificationName:CPTLegendNeedsRedrawForPlotNotification object:self];
    }

    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark Fills
/**
 *  @brief Reload all fills  from the data source immediately.
 **/
-(void)reloadContourFills {
    [self reloadContourFillsInIsoCurveIndexRange:NSMakeRange(0, self.noActualIsoCurves+1)];
}

/** @brief Reload contour fill in the given index range from the data source immediately.
 *  @param indexRange The index range to load.
 **/
-(void)reloadContourFillsInIsoCurveIndexRange:(NSRange)indexRange {
    id<CPTContourPlotDataSource> theDataSource = (id<CPTContourPlotDataSource>)self.dataSource;
    
    if ([theDataSource isKindOfClass:[CPTFieldFunctionDataSource class]]) {
        theDataSource = (id<CPTContourPlotDataSource>)self.appearanceDataSource;
    }

    if ( [theDataSource respondsToSelector:@selector(fillsForContourPlot:isoCurveIndices:isoCurveIndicesSize:)] ) {

        id nilObject                    = [CPTPlot nilData];
        NSUInteger maxIndex             = NSMaxRange(indexRange);
        NSUInteger *indices = (NSUInteger*)calloc(maxIndex - indexRange.location, sizeof(NSUInteger));
        for ( NSUInteger idx = indexRange.location; idx < maxIndex; idx++ ) {
            indices[idx] = [[self.isoCurvesIndices objectAtIndex:idx] unsignedIntegerValue];
        }
        CPTFillArray *dataSourceFills = [theDataSource fillsForContourPlot:self isoCurveIndices:indices isoCurveIndicesSize:maxIndex - indexRange.location];
        for ( NSUInteger idx = 0; idx < maxIndex - indexRange.location; idx++ ) {
            CPTFill *dataSourceFill = [dataSourceFills objectAtIndex:idx];
            if ( idx > self.isoCurvesFills.count - 1 ) {
                [self.isoCurvesFills addObject:nilObject];
            }
            if ( dataSourceFill ) {
                [self.isoCurvesFills replaceObjectAtIndex:indices[idx] withObject:dataSourceFill];
            }
            else {
                [self.isoCurvesFills replaceObjectAtIndex:indices[idx] withObject:nilObject];
            }
        }
        free(indices);
    }
    else if ( [theDataSource respondsToSelector:@selector(fillForContourPlot:isoCurveIndex:)] ) {

        id nilObject                    = [CPTPlot nilData];
        NSUInteger maxIndex             = NSMaxRange(indexRange);
        for ( NSUInteger idx = indexRange.location; idx < maxIndex; idx++ ) {
            CPTFill *dataSourceFill = [theDataSource fillForContourPlot:self isoCurveIndex:idx];
            if ( idx > self.isoCurvesFills.count - 1 ) {
                [self.isoCurvesFills addObject:nilObject];
            }
            if ( dataSourceFill ) {
                [self.isoCurvesFills replaceObjectAtIndex:idx withObject:dataSourceFill];
            }
            else {
                [self.isoCurvesFills replaceObjectAtIndex:idx withObject:nilObject];
            }
        }
    }

    [self setNeedsDisplay];
}

- (CPTColor*) averageFillColourBetweenIndex:(NSUInteger)index0 OtherIndex:(NSUInteger)index1 {
    id nilObject                    = [CPTPlot nilData];
    CPTColor *avg = nil;
    if( self.isoCurvesLineStyles[index0] != nilObject && self.isoCurvesLineStyles[index1] != nilObject ) {
        CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
        CGColorRef color1 = CGColorCreateCopy([[self.isoCurvesLineStyles[index0] lineColor] cgColor]);
        CGColorRef color2 = CGColorCreateCopy([[self.isoCurvesLineStyles[index1] lineColor] cgColor]);
        
        const CGFloat *components1, *components2;
        if (CGColorGetNumberOfComponents(color1) < 4) {
            components1 = CGColorGetComponents(color1);
            CGColorRelease(color1);
            color1 = CGColorCreate(colorspace, components1);
        }
        else {
            components1 = CGColorGetComponents(color1);
        }
        if (CGColorGetNumberOfComponents(color2) < 4) {
            components2 = CGColorGetComponents(color2);
            CGColorRelease(color2);
            color2 = CGColorCreate(colorspace, components2);
        }
        else {
            components2 = CGColorGetComponents(color2);
        }
        if (CGColorSpaceGetModel(CGColorGetColorSpace(color1)) != kCGColorSpaceModelRGB || CGColorSpaceGetModel(CGColorGetColorSpace(color2)) != kCGColorSpaceModelRGB) {
            NSLog(@"no rgb colorspace");
            avg = [CPTColor colorWithCGColor:color1];
        }
        else {
            avg = [CPTColor colorWithComponentRed:(components1[0] + components2[0]) / 2.0 green:(components1[1] + components2[1]) / 2.0 blue:(components1[2] + components2[2]) / 2.0 alpha:(components1[3] + components2[3]) / 2.0];
        }
        CGColorRelease(color1);
        CGColorRelease(color2);
        CGColorSpaceRelease(colorspace);
    }
    
    return avg;
}

#pragma mark -
#pragma mark Contour Labels
/**
 *  @brief Reload all data labels from the data source immediately.
 **/
-(void)reloadContourLabels {
    [self reloadContourLabelsInIsoCurveIndexRange:NSMakeRange(0, self.isoCurvesValues.count)];
}

/**
 *  @brief Reload all IsoCurve labels in the given index range from the data source immediately.
 *  @param indexRange The index range to load.
 **/
-(void)reloadContourLabelsInIsoCurveIndexRange:(NSRange)indexRange {
    if ( self.isoCurvesIndices == nil ) {
        return;
    }
    id<CPTContourPlotDataSource> theDataSource = (id<CPTContourPlotDataSource>)self.dataSource;
    
    if ([theDataSource isKindOfClass:[CPTFieldFunctionDataSource class]]) {
        theDataSource = (id<CPTContourPlotDataSource>)self.appearanceDataSource;
    }

    if ( [theDataSource respondsToSelector:@selector(isoCurveLabelsForPlot:isoCurveValuesIndices:isoCurveValuesIndicesSize:)] ) {
        
        id nilObject                    = [CPTPlot nilData];
        NSUInteger maxIndex             = NSMaxRange(indexRange);
        NSUInteger *indices = (NSUInteger*)calloc(maxIndex - indexRange.location, sizeof(NSUInteger));
        for ( NSUInteger idx = indexRange.location; idx < maxIndex; idx++ ) {
            indices[idx] = [[self.isoCurvesIndices objectAtIndex:idx] unsignedIntegerValue];
        }
        
        CPTLayerArray *dataSourceLabels = [theDataSource isoCurveLabelsForPlot:self isoCurveValuesIndices:indices isoCurveValuesIndicesSize:maxIndex - indexRange.location];
        for ( NSUInteger idx = 0; idx < maxIndex - indexRange.location; idx++ ) {
            CPTLayer *labelLayer = [dataSourceLabels objectAtIndex:idx];
            if ( labelLayer ) {
                [self.isoCurvesLabels replaceObjectAtIndex:idx withObject:labelLayer];
            }
            else {
                [self.isoCurvesLabels replaceObjectAtIndex:idx withObject:nilObject];
            }
        }
        free(indices);
    }
    else if ( [theDataSource respondsToSelector:@selector(isoCurveLabelForPlot:isoCurveValueIndex:)] ) {
        id nilObject                = [CPTPlot nilData];
        NSUInteger maxIndex             = NSMaxRange(indexRange);
        for ( NSUInteger idx = indexRange.location; idx < maxIndex; idx++ ) {
            CPTLayer *labelLayer = [theDataSource isoCurveLabelForPlot:self isoCurveValueIndex:idx];
            if ( labelLayer ) {
                [self.isoCurvesLabels replaceObjectAtIndex:idx withObject:labelLayer];
            }
            else {
                [self.isoCurvesLabels replaceObjectAtIndex:idx withObject:nilObject];
            }
        }
    }

    [self relabelIsoCurvesIndexRange:indexRange];
}

#pragma mark -
#pragma mark View Points

/// @cond

-(NSUInteger)dataIndexFromInteractionPoint:(CGPoint)point
{
    return [self indexOfVisiblePointClosestToPlotAreaPoint:point];
}

/// @endcond

/** @brief Returns the index of the closest visible point to the point passed in.
 *  @param viewPoint The reference point.
 *  @return The index of the closest point, or @ref NSNotFound if there is no visible point.
 **/
-(NSUInteger)indexOfVisiblePointClosestToPlotAreaPoint:(CGPoint)viewPoint
{
    NSUInteger dataCount = self.cachedDataCount;
    CGPoint *viewPoints = (CGPoint*)calloc(dataCount, sizeof(CGPoint));
    BOOL *drawPointFlags     = (BOOL*)calloc(dataCount, sizeof(BOOL));

    [self calculatePointsToDraw:drawPointFlags forPlotSpace:(CPTXYPlotSpace *)self.plotSpace includeVisiblePointsOnly:YES numberOfPoints:dataCount];
    [self calculateViewPoints:viewPoints withDrawPointFlags:drawPointFlags numberOfPoints:dataCount];

    NSInteger result = [self extremeDrawnPointIndexForFlags:drawPointFlags numberOfPoints:dataCount extremeNumIsLowerBound:YES];

    if ( result != NSNotFound ) {
        CGFloat minimumDistanceSquared = (CGFloat)NAN;
        for ( NSUInteger i = (NSUInteger)result; i < dataCount; ++i ) {
            if ( drawPointFlags[i] ) {
                CGFloat distanceSquared = squareOfDistanceBetweenPoints(viewPoint, viewPoints[i]);
                if ( isnan(minimumDistanceSquared) || (distanceSquared < minimumDistanceSquared)) {
                    minimumDistanceSquared = distanceSquared;
                    result                 = (NSInteger)i;
                }
            }
        }
    }

    free(viewPoints);
    free(drawPointFlags);

    return (NSUInteger)result;
}

/** @brief Returns the plot area view point of a visible point.
 *  @param idx The index of the point.
 *  @return The view point of the visible point at the index passed.
 **/
-(CGPoint)plotAreaPointOfVisiblePointAtIndex:(NSUInteger)idx
{
//    NSParameterAssert(idx < self.cachedDataCount);

    CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
    CGPoint viewPoint;

    if ( self.doublePrecisionCache ) {
        double plotPoint[2];
        plotPoint[CPTContourPlotFieldX] = [self cachedDoubleForField:CPTContourPlotFieldX recordIndex:idx];
        plotPoint[CPTContourPlotFieldY] = [self cachedDoubleForField:CPTContourPlotFieldY recordIndex:idx];

        viewPoint = [thePlotSpace plotAreaViewPointForDoublePrecisionPlotPoint:plotPoint numberOfCoordinates:2];
    }
    else {
        NSDecimal plotPoint[2];
        plotPoint[CPTContourPlotFieldX] = [self cachedDecimalForField:CPTContourPlotFieldX recordIndex:idx];
        plotPoint[CPTContourPlotFieldY] = [self cachedDecimalForField:CPTContourPlotFieldY recordIndex:idx];

        viewPoint = [thePlotSpace plotAreaViewPointForPlotPoint:plotPoint numberOfCoordinates:2];
    }

    return viewPoint;
}


#pragma mark -
#pragma mark Drawing

/// @cond

-(void)renderAsVectorInContext:(nonnull CGContextRef)context {
    if ( self.hidden ) {
        return;
    }
        
    CGContextClearRect(context, CGContextGetClipBoundingBox(context));
    
    CPTMutableNumericData *xValueData = [self cachedNumbersForField:CPTContourPlotFieldX];
    CPTMutableNumericData *yValueData = [self cachedNumbersForField:CPTContourPlotFieldY];
    CPTMutableNumericData *zValueData = [self cachedNumbersForField:CPTContourPlotFieldFunctionValue];
    
    if ( (xValueData == nil) || (yValueData == nil) || (zValueData == nil) ) {
        return;
    }
    NSUInteger dataCount = self.cachedDataCount;
    if ( dataCount == 0 ) {
        return;
    }
    
    if ( xValueData.numberOfSamples != yValueData.numberOfSamples ) {
        [NSException raise:CPTException format:@"Number of x and y values do not match"];
    }
    
    [super renderAsVectorInContext:context];
    
    // Calculate view points, and align to user space
    CGPoint *viewPoints = (CGPoint*)calloc(dataCount, sizeof(CGPoint));
    BOOL *drawPointFlags = (BOOL*)calloc(dataCount, sizeof(BOOL));
    
    CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
    [self calculatePointsToDraw:drawPointFlags forPlotSpace:thePlotSpace includeVisiblePointsOnly:NO numberOfPoints:dataCount];
    [self calculateViewPoints:viewPoints withDrawPointFlags:drawPointFlags numberOfPoints:dataCount];
    
    // Get extreme points
    NSInteger lastDrawnPointIndex  = [self extremeDrawnPointIndexForFlags:drawPointFlags numberOfPoints:dataCount extremeNumIsLowerBound:NO];
    NSInteger firstDrawnPointIndex = [self extremeDrawnPointIndexForFlags:drawPointFlags numberOfPoints:dataCount extremeNumIsLowerBound:YES];
    
    if ( firstDrawnPointIndex != NSNotFound && lastDrawnPointIndex != NSNotFound ) {
        
        BOOL pixelAlign = self.alignsPointsToPixels;
        
        if ( self.dataSourceBlock == nil ) {
            CPTFieldFunctionDataSource *contourFunctionDataSource = (CPTFieldFunctionDataSource*)self.dataSource;
            self.dataSourceBlock = contourFunctionDataSource.dataSourceBlock;
        }
        
        double limit0, limit1, limit2, limit3;
        if ( !self.extrapolateToLimits && !self.functionPlot ) {
            limit0 = [self.limits[0] doubleValue];
            limit1 = [self.limits[1] doubleValue];
            limit2 = [self.limits[2] doubleValue];
            limit3 = [self.limits[3] doubleValue];
        }
        else {
            if (thePlotSpace.xRange.lengthDouble > thePlotSpace.yRange.lengthDouble) {
                if ([self.limits[0] doubleValue] == -DBL_MAX && [self.limits[1] doubleValue] == DBL_MAX) {
                    limit0 = thePlotSpace.xRange.locationDouble;
                    limit1 = thePlotSpace.xRange.endDouble;
                    limit2 = thePlotSpace.yRange.midPointDouble - thePlotSpace.xRange.lengthDouble / 2.0;
                    limit3 = thePlotSpace.yRange.midPointDouble + thePlotSpace.xRange.lengthDouble / 2.0;
                }
                else {
                    limit0 = thePlotSpace.xRange.minLimitDouble > [self.limits[0] doubleValue] ? thePlotSpace.xRange.minLimitDouble : [self.limits[0] doubleValue];
                    limit1 = thePlotSpace.xRange.maxLimitDouble < [self.limits[1] doubleValue] ? thePlotSpace.xRange.maxLimitDouble : [self.limits[1] doubleValue];
                    limit2 = thePlotSpace.yRange.minLimitDouble > [self.limits[2] doubleValue] ? thePlotSpace.yRange.minLimitDouble : [self.limits[2] doubleValue];
                    limit3 = thePlotSpace.yRange.minLimitDouble + thePlotSpace.yRange.lengthDouble < [self.limits[3] doubleValue] ? thePlotSpace.yRange.minLimitDouble + thePlotSpace.yRange.lengthDouble : [self.limits[3] doubleValue];
                }
            }
            else {
                if ([self.limits[2] doubleValue] == -DBL_MAX && [self.limits[3] doubleValue] == DBL_MAX) {
                    limit2 = thePlotSpace.yRange.locationDouble;
                    limit3 = thePlotSpace.yRange.endDouble;
                    limit0 = thePlotSpace.xRange.midPointDouble - thePlotSpace.yRange.lengthDouble / 2.0;
                    limit1 = thePlotSpace.xRange.midPointDouble + thePlotSpace.yRange.lengthDouble / 2.0;
                }
                else {
                    limit2 = thePlotSpace.yRange.minLimitDouble > [self.limits[2] doubleValue] ? thePlotSpace.yRange.minLimitDouble : [self.limits[2] doubleValue];
                    limit3 = thePlotSpace.yRange.maxLimitDouble < [self.limits[3] doubleValue] ? thePlotSpace.yRange.maxLimitDouble : [self.limits[3] doubleValue];
                    limit0 = thePlotSpace.xRange.minLimitDouble > [self.limits[0] doubleValue] ? thePlotSpace.xRange.minLimitDouble : [self.limits[0] doubleValue];
                    limit1 = thePlotSpace.xRange.minLimitDouble + thePlotSpace.xRange.lengthDouble < [self.limits[1] doubleValue] ? thePlotSpace.xRange.minLimitDouble + thePlotSpace.xRange.lengthDouble : [self.limits[1] doubleValue];
                }
            }
        }
        self.maxWidthPixels = CPTDecimalDoubleValue(self.plotArea.widthDecimal);
        self.maxHeightPixels = CPTDecimalDoubleValue(self.plotArea.heightDecimal);
        self.scaleX = self.maxWidthPixels / thePlotSpace.xRange.lengthDouble;
        self.scaleY = self.maxHeightPixels / thePlotSpace.yRange.lengthDouble;
        
        LineStripList *pStripList = NULL;
        LineStrip *pStrip = NULL;
        NSUInteger index, pos, pos2, plane;
        double x, y;
        CGPoint point;
        NSString *filePath = [NSString stringWithFormat:@"%@contours.bin", NSTemporaryDirectory()];
        NSString *imageFilePath = [NSString stringWithFormat:@"%@layer.png", NSTemporaryDirectory()];

        double _limits[4] = { limit0, limit1, limit2, limit3 };
        CGRect previousGreatestContourBox = CGRectMake((_limits[0] - thePlotSpace.xRange.locationDouble) * self.scaleX, (_limits[2] - thePlotSpace.yRange.locationDouble) * self.scaleY, (_limits[1] - _limits[0]) * self.scaleX, (_limits[3] - _limits[2]) * self.scaleY);
        CGPoint limitPoints[2] = { CGPointMake(previousGreatestContourBox.origin.x, previousGreatestContourBox.origin.y),
            CGPointMake(previousGreatestContourBox.origin.x + previousGreatestContourBox.size.width, previousGreatestContourBox.origin.y  + previousGreatestContourBox.size.height) };
        if( pixelAlign ) {
            [self alignViewPointsToUserSpace:limitPoints withContext:context numberOfPoints:2];
            previousGreatestContourBox = CGRectMake(limitPoints[0].x, limitPoints[0].y, limitPoints[1].x - limitPoints[0].x, limitPoints[1].y - limitPoints[0].y);
        }
        
        NSUInteger workingNoColumnsFirst = self.noColumnsFirst;
        NSUInteger workingNoRowsFirst = self.noRowsFirst;
        NSUInteger workingNoColumnsSecondary = self.noColumnsSecondary;
        NSUInteger workingNoRowsSecondary = self.noRowsSecondary;
        CGContextRef currentContext = NULL;
        CGFloat currentMaxWidthPixels, currentMaxHeightPixels;
        self.originOfContext = CGPointZero;
        self.scaleOfContext = 1.0;
        
        if ( fabs(thePlotSpace.xRange.lengthDouble - self.initialXRange.lengthDouble) > 0.001 || fabs(thePlotSpace.yRange.lengthDouble - self.initialYRange.lengthDouble) > 0.001 || self.previousFillIsoCurves != self.fillIsoCurves || self.firstRendition ) {
            self.needsIsoCurvesUpdate = YES;
        }
//        else if ( (self.functionPlot && ([self.limits[1] doubleValue] - [self.limits[0] doubleValue] > thePlotSpace.xRange.lengthDouble || [self.limits[3] doubleValue] - [self.limits[2] doubleValue] > thePlotSpace.yRange.lengthDouble) && (fabs(thePlotSpace.xRange.locationDouble - self.initialXRange.locationDouble) > 0.001 || fabs(thePlotSpace.yRange.locationDouble - self.initialYRange.locationDouble) > 0.001)) ) {
//            self.needsIsoCurvesUpdate = YES;
//        }
//        if ( (limit0 < [self.previousLimits[0] doubleValue] || limit1 > [self.previousLimits[1] doubleValue]) && limit0 != [self.limits[0] doubleValue] && limit1 != [self.limits[1] doubleValue] ) {
//            double constant = ([self.limits[1] doubleValue] - [self.limits[0] doubleValue]) / (limit1 - limit0);
//            workingNoColumnsFirst = (NSUInteger)(constant * (double)self.noColumnsFirst);
//            workingNoColumnsSecondary = (NSUInteger)(constant * (double)self.noColumnsSecondary);
//            self.needsIsoCurvesUpdate = YES;
//        }
//        if ( (limit2 < [self.previousLimits[2] doubleValue] || limit3 > [self.previousLimits[3] doubleValue]) && limit2 != [self.limits[2] doubleValue] && limit3 != [self.limits[3] doubleValue] ) {
//            double constant = ([self.limits[3] doubleValue] - [self.limits[2] doubleValue]) / (limit3 - limit2);
//            workingNoRowsFirst = (NSUInteger)(constant * (double)self.noRowsFirst);
//            workingNoRowsSecondary = (NSUInteger)(constant * (double)self.noRowsSecondary);
//            self.needsIsoCurvesUpdate = YES;
//        }
        if ( !self.extrapolateToLimits && !self.functionPlot ) {
            double constantColumns = ceil((limit1 - limit0) / thePlotSpace.xRange.lengthDouble);
            workingNoColumnsFirst = (NSUInteger)constantColumns * self.noColumnsFirst;
            workingNoColumnsSecondary = (NSUInteger)constantColumns * self.noColumnsSecondary;
            double constantRows = ceil((limit3 - limit2) / thePlotSpace.yRange.lengthDouble);
            workingNoRowsFirst = (NSUInteger)constantRows * self.noRowsFirst;
            workingNoRowsSecondary = (NSUInteger)constantRows * self.noRowsSecondary;
        }
        else {
            if ( thePlotSpace.xRange.locationDouble > [self.limits[0] doubleValue] || thePlotSpace.xRange.endDouble < [self.limits[1] doubleValue] ) {
                double constant = ([self.limits[1] doubleValue] - [self.limits[0] doubleValue]) / (limit1 - limit0);
                workingNoColumnsFirst = (NSUInteger)constant * self.noColumnsFirst;
                workingNoColumnsSecondary = (NSUInteger)constant * self.noColumnsSecondary;
            }
            if ( thePlotSpace.yRange.locationDouble > [self.limits[2] doubleValue] || thePlotSpace.yRange.endDouble < [self.limits[3] doubleValue] ) {
                double constant = ([self.limits[3] doubleValue] - [self.limits[2] doubleValue]) / (limit3 - limit2);
                workingNoRowsFirst = (NSUInteger)constant * self.noRowsFirst;
                workingNoRowsSecondary = (NSUInteger)constant * self.noRowsSecondary;
            }
        }
            
        // get extra drawing size if symbols/lines on border
        CGFloat extraWidth = MAX(self.plotSymbol.size.width, self.isoCurveLineStyle.lineWidth);
        CGFloat extraHeight = MAX(self.plotSymbol.size.height, self.isoCurveLineStyle.lineWidth);
        
        if ( self.needsIsoCurvesUpdate ) {
            // here we are going to generate contour planes based on max/min FunctionValue
            // then go through each plane and plot the points, lets try to make steps easy on the eye
            double _adjustedMinFunctionValue = 0, _adjustedMaxFunctionValue = 0, adjustedStep = 0;
            if ( self.easyOnTheEye && !CPTEasyOnTheEyeScaling(self.minFunctionValue, self.maxFunctionValue, (int)self.noIsoCurves, &_adjustedMinFunctionValue, &_adjustedMaxFunctionValue, &adjustedStep) ) {
            }
            else {
                _adjustedMinFunctionValue = lrint(floor(self.minFunctionValue));
                _adjustedMaxFunctionValue = lrint(ceil(self.maxFunctionValue));
                double step = (self.maxFunctionValue - self.minFunctionValue) / (double)(self.noIsoCurves - 1);
                adjustedStep = step;
            }
            self.noActualIsoCurves = self.noIsoCurves;
            double *planesValues = (double*)calloc(self.noActualIsoCurves, sizeof(double));
            for (NSUInteger iPlane = 0; iPlane < self.noActualIsoCurves; iPlane++) {
                planesValues[iPlane] = _adjustedMinFunctionValue + (double)iPlane * adjustedStep;
            }
            if (planesValues[self.noActualIsoCurves - 1] < _adjustedMaxFunctionValue ) {
                planesValues[self.noActualIsoCurves - 1] = _adjustedMaxFunctionValue;
            }
            _limits[0] = [self.limits[0] doubleValue];
            _limits[1] = [self.limits[1] doubleValue];
            _limits[2] = [self.limits[2] doubleValue];
            _limits[3] = [self.limits[3] doubleValue];
            CPTContours *contours = [[CPTContours alloc] initWithNoIsoCurve:self.noActualIsoCurves IsoCurveValues:planesValues Limits:_limits];
            if ( self.dataSourceBlock != NULL) {
                CPTContourDataSourceBlock __dataSourceBlock = self.dataSourceBlock;
                [contours setFieldBlock:__dataSourceBlock];
            }
            NSUInteger repeatContoursCalculation = 3;
            while ( repeatContoursCalculation > 0 ) {
                [contours setFirstGridDimensionColumns:workingNoColumnsFirst Rows:workingNoRowsFirst];
                [contours setSecondaryGridDimensionColumns:workingNoColumnsSecondary Rows:workingNoRowsSecondary];
                [contours initialiseMemory];
                if ( !self.firstRendition && self.fillIsoCurves != self.previousFillIsoCurves && [contours readPlanesFromDisk:filePath]) {
                    self.greatestContourBox = CGRectZero;
                }
                else {
                    self.firstRendition = NO;
                    [contours generateAndCompactStrips];
                    [contours writePlanesToDisk:filePath];
                }
                
                if ( self.isoCurvesIndices != nil ) {
                    [self.isoCurvesIndices removeAllObjects];
                    self.isoCurvesIndices = nil;
                }
                self.isoCurvesIndices = [[CPTMutableNumberArray alloc] init];
                for( NSUInteger i = 0; i < [contours getIsoCurvesLists]->used/*self.noActualIsoCurves*/; i++ ) {
                    [contours dumpPlane:i];
                    if ( [contours getStripListForIsoCurve:i]->used > 0 ) {
                        NSNumber *indexNumber = [NSNumber numberWithUnsignedInteger:i];
                        [self.isoCurvesIndices addObject:indexNumber];
                    }
                }
                BOOL stripEndsOnBoundary = NO;
                if ( !self.extrapolateToLimits && !self.functionPlot ) {
                    CGMutablePathRef dataLineClosedPath = NULL;
                    CGPoint _startPoint, _endPoint;
                    plane = [[self.isoCurvesIndices objectAtIndex:0] unsignedIntegerValue];
                    pStripList = [contours getStripListForIsoCurve:plane];
                    pStrip = &pStripList->array[0];
                    [self createDataLinePath:&dataLineClosedPath fromStrip:pStrip context:context contours:contours startPoint:&_startPoint endPoint:&_endPoint reverseOrder:NO closed:YES extraStripList:NO];
                    if( !CGPointEqualToPoint(_startPoint, _endPoint)) {
                        CGPathAddLineToPoint(dataLineClosedPath, NULL, _startPoint.x, _startPoint.y);
                    }
                    self.greatestContourBox = CGPathGetBoundingBox(dataLineClosedPath);
                    for ( NSUInteger iPlane = 0; iPlane < self.isoCurvesIndices.count; iPlane++ ) {
                        plane = [[self.isoCurvesIndices objectAtIndex:iPlane] unsignedIntegerValue];
                        pStripList = [contours getStripListForIsoCurve:plane];
                        for (pos = 0; pos < pStripList->used; pos++) {
                            pStrip = &pStripList->array[pos];
                            if ( pStrip->used > 0 ) {
                                stripEndsOnBoundary |= ([contours isNodeOnBoundary:pStrip->array[0]] || [contours isNodeOnBoundary:pStrip->array[pStrip->used-1]]);
                                [self createDataLinePath:&dataLineClosedPath fromStrip:pStrip context:context contours:contours startPoint:&_startPoint endPoint:&_endPoint reverseOrder:NO closed:YES extraStripList:NO];
                                if( !CGPointEqualToPoint(_startPoint, _endPoint)) {
                                    CGPathAddLineToPoint(dataLineClosedPath, NULL, _startPoint.x, _startPoint.y);
                                }
                                self.greatestContourBox = CGRectUnion(self.greatestContourBox, CGPathGetBoundingBox(dataLineClosedPath));
#if DEBUG
#if TARGET_OS_OSX
                                NSBezierPath * __unused bezierPath1 = [NSBezierPath bezierPathWithCGPath:dataLineClosedPath];
#else
                                UIBezierPath * __unused bezierPath1 = [UIBezierPath bezierPathWithCGPath:dataLineClosedPath];
#endif
#endif
                                if ( dataLineClosedPath != NULL ) {
                                    CGPathRelease(dataLineClosedPath);
                                }
                            }
                        }
                    }
                }
                NSLog(@"greatestContourBox: %f %f %f %f", self.greatestContourBox.origin.x, self.greatestContourBox.origin.y, self.greatestContourBox.size.width, self.greatestContourBox.size.height);
                NSLog(@"previousGreatestContourBox: %f %f %f %f", previousGreatestContourBox.origin.x, previousGreatestContourBox.origin.y, previousGreatestContourBox.size.width, previousGreatestContourBox.size.height);

                if ( !self.extrapolateToLimits && !self.functionPlot && !CGRectEqualToRect(self.greatestContourBox, CGRectZero) && (CGRectEqualToRect(self.greatestContourBox, previousGreatestContourBox) || stripEndsOnBoundary) ) {
                    previousGreatestContourBox = self.greatestContourBox;
                    repeatContoursCalculation--;
                    if ( repeatContoursCalculation == 0 ) {
                        break;
                    }
                    _limits[0] = (self.greatestContourBox.origin.x - self.greatestContourBox.size.width) / self.scaleX + thePlotSpace.xRange.locationDouble;
                    _limits[1] = (self.greatestContourBox.origin.x + self.greatestContourBox.size.width * 2.0) / self.scaleX + thePlotSpace.xRange.locationDouble;
                    _limits[2] = (self.greatestContourBox.origin.y - self.greatestContourBox.size.height) / self.scaleY + thePlotSpace.yRange.locationDouble;
                    _limits[3] = (self.greatestContourBox.origin.y + self.greatestContourBox.size.height * 2.0) / self.scaleY + thePlotSpace.yRange.locationDouble;
                    if ( ceil((_limits[1] - _limits[0]) / (limit1 - limit0)) >= 2 || ceil((_limits[3] - _limits[2]) / (limit3 - limit2)) >= 2 ) {
                        limit0 = _limits[0];
                        limit1 = _limits[1];
                        limit2 = _limits[2];
                        limit3 = _limits[3];
//                        self.noColumnsFirst *= 2;
//                        self.noRowsFirst *= 2;
                        self.noColumnsSecondary *= 2;
                        self.noRowsSecondary *= 2;
                    }
                    [contours setXYLimits:_limits];
                }
                else {
                    repeatContoursCalculation = 0;
                }
            }
            CGContextSaveGState(context);
            if ( !self.extrapolateToLimits && !self.functionPlot ) {
                currentMaxWidthPixels = self.greatestContourBox.size.width + extraWidth * 2;
                currentMaxHeightPixels = self.greatestContourBox.size.height + extraHeight * 2;
#if TARGET_OS_OSX
                NSSize size = NSMakeSize(currentMaxWidthPixels, currentMaxHeightPixels);
                self.macOSImage = [[NSImage alloc] initWithSize:size];
                NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size.width pixelsHigh:(NSInteger)size.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(NSInteger)size.width * 4 bitsPerPixel:32];
                [self.macOSImage addRepresentation:rep];
                [self.macOSImage lockFocus];
                currentContext = [[NSGraphicsContext currentContext] CGContext];
                self.scaleOfContext = 1.0;
//                NSGraphicsContext *bitmapContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
//                currentContext = (CGContextRef)bitmapContext.CGContext;
#else
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(currentMaxWidthPixels, currentMaxHeightPixels), NO, 0);
                currentContext = UIGraphicsGetCurrentContext();
#endif
                viewPoints[0] = CGPointMake(self.greatestContourBox.origin.x - extraWidth, self.greatestContourBox.origin.y - extraHeight);
                viewPoints[1] = CGPointMake(self.greatestContourBox.origin.x + self.greatestContourBox.size.width + extraWidth, self.greatestContourBox.origin.y + self.greatestContourBox.size.height + extraHeight);
                if ( pixelAlign ) {
                    [self alignViewPointsToUserSpace:viewPoints withContext:currentContext numberOfPoints:2];
                }
                self.originOfContext = viewPoints[0];
                double plotPoint[2];
                [thePlotSpace doublePrecisionPlotPoint:plotPoint numberOfCoordinates:2 forPlotAreaViewPoint:viewPoints[0]];
                limit0 = plotPoint[0];
                limit2 = plotPoint[1];
                [thePlotSpace doublePrecisionPlotPoint:plotPoint numberOfCoordinates:2 forPlotAreaViewPoint:viewPoints[1]];
                limit1 = plotPoint[0];
                limit3 = plotPoint[1];
            }
            else {
                double plotPoint0[2], plotPoint1[2];
                plotPoint0[CPTCoordinateX] = [self.limits[0] doubleValue];//limit0;
                plotPoint0[CPTCoordinateY] = [self.limits[2] doubleValue];//limit2;
                plotPoint1[CPTCoordinateX] = [self.limits[1] doubleValue];//limit1;
                plotPoint1[CPTCoordinateY] = [self.limits[3] doubleValue];//limit3;
                viewPoints[0] = [thePlotSpace plotAreaViewPointForDoublePrecisionPlotPoint:plotPoint0 numberOfCoordinates:2];
                viewPoints[1] = [thePlotSpace plotAreaViewPointForDoublePrecisionPlotPoint:plotPoint1 numberOfCoordinates:2];
                if ( pixelAlign ) {
                    [self alignViewPointsToUserSpace:viewPoints withContext:context numberOfPoints:2];
                }
                currentMaxWidthPixels = viewPoints[1].x - viewPoints[0].x + extraWidth * 2;
                currentMaxHeightPixels = viewPoints[1].y - viewPoints[0].y + extraHeight * 2;
                self.originOfContext = CGPointMake(viewPoints[0].x - extraWidth, viewPoints[0].y - extraHeight);
#if TARGET_OS_OSX
                NSSize size = NSMakeSize(currentMaxWidthPixels, currentMaxHeightPixels);
                self.macOSImage = [[NSImage alloc] initWithSize:size];
                NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size.width pixelsHigh:(NSInteger)size.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(NSInteger)size.width * 4 bitsPerPixel:32];
                [self.macOSImage addRepresentation:rep];
                [self.macOSImage lockFocus];
                currentContext = [[NSGraphicsContext currentContext] CGContext];
                self.scaleOfContext = 1.0;
#else
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(currentMaxWidthPixels, currentMaxHeightPixels), NO, 0);
                currentContext = UIGraphicsGetCurrentContext();
#endif
            }
            //        double __unused v = [contours getFieldValueForX:1.0 Y:0.1];
#if DEBUG        // debug
            IsoCurvesList *list = [contours getIsoCurvesLists];
            NSLog(@"No of IsoCurves: %ld", list->used);
#endif
            [self.isoCurvesValues removeAllObjects];
            for ( NSUInteger i = 0; i < [contours getContourPlanes]->used; i++ ) {
                NSNumber *value = [NSNumber numberWithDouble:[contours getContourPlanes]->array[i]];
                [self.isoCurvesValues addObject:value];
            }
            self.noActualIsoCurves = [contours getContourPlanes]->used;
            
            if ( self.needsIsoCurvesUpdate ) {
                [self clearOut];
                self.isoCurvesLineStyles = [[CPTMutableLineStyleArray alloc] init];
                self.isoCurvesFills = [[CPTMutableFillArray alloc] init];
                self.isoCurvesFillings = [[NSMutableArray alloc] init];
                self.isoCurvesLabels = [[CPTMutableLayerArray alloc] init];
                id nilObject                    = [CPTPlot nilData];
                for( NSUInteger i = 0; i < self.noActualIsoCurves; i++ ) {
                    [self.isoCurvesLabels addObject: nilObject];
                    CPTMutableLineStyle *lineStyle = [CPTMutableLineStyle lineStyleWithStyle: self.isoCurveLineStyle];
                    [self.isoCurvesLineStyles addObject: lineStyle];
                    [self.isoCurvesFills addObject: nilObject];
                }
                [self.isoCurvesFills addObject: nilObject];
                self.isoCurvesValues = [CPTMutableNumberArray arrayWithCapacity:self.noActualIsoCurves];
                self.isoCurvesNoStrips = [CPTMutableNumberArray arrayWithCapacity:self.noActualIsoCurves];
                self.isoCurvesLabelsPositions = (NSMutableArray<CPTMutableValueArray*>*)[NSMutableArray arrayWithCapacity:self.noActualIsoCurves];
                self.isoCurvesLabelsRotations = (NSMutableArray<NSMutableArray*>*)[NSMutableArray arrayWithCapacity:self.noActualIsoCurves];
                
                for ( plane = 0; plane < self.noActualIsoCurves; plane++ ) {
                    NSNumber *isoCurveValue = [NSNumber numberWithDouble: [contours getIsoCurveAt:plane]];
                    [self.isoCurvesValues addObject:isoCurveValue];
                    pStripList = [contours getStripListForIsoCurve:plane];
                    NSNumber *isoCurveNoStrips = [NSNumber numberWithUnsignedInteger:pStripList->used];
                    [self.isoCurvesNoStrips addObject:isoCurveNoStrips];
                }
                CGFloat rotation;
                for ( NSUInteger iPlane = 0; iPlane < self.isoCurvesValues.count; iPlane++ ) {
                    pStripList = [contours getStripListForIsoCurve:iPlane];
                    if (pStripList->used > 0) {
                        // position one set of contour labels
                        CPTMutableValueArray *positionsPerStrip = [CPTMutableValueArray arrayWithCapacity:pStripList->used];
                        CPTMutableNumberArray *rotationsPerStrip = [CPTMutableNumberArray arrayWithCapacity:pStripList->used];
                        for (pos = 0; pos < pStripList->used; pos++) {
                            pStrip = &pStripList->array[pos];
                            if ( pStrip->used > 5 ) {
                                pos2 = (pStrip->used - 1) / 8; // * pos / pStripList->used;
                                if ( pos2 >= pStrip->used ) {
                                    pos2 = pStrip->used - 1;
                                }
                                index = pStrip->array[pos2]; // retreiving index
                                x = [contours getXAt:index];
                                y = [contours getYAt:index];
                                point = CGPointMake(x, y);
                                // try to rotate label to parallel contour
                                if ( pos2 + 2 > pStrip->used - 1 ) {
                                    index = pStrip->array[pStrip->used - 1];
                                }
                                else {
                                    index = pStrip->array[pos2 + 2];
                                }
                                rotation = atan2(y - [contours getYAt:index], x - [contours getXAt:index]);
                                if ( rotation > M_PI / 2.0 ) {
                                    rotation -= M_PI;
                                }
                                else if ( rotation < -M_PI / 2.0 ) {
                                    rotation += M_PI;
                                }
#if TARGET_OS_OSX
                                NSValue *positionValue = [NSValue valueWithPoint:point];
#else
                                NSValue *positionValue = [NSValue valueWithCGPoint:point];
#endif
                                [positionsPerStrip addObject:positionValue];
                                [rotationsPerStrip addObject:[NSNumber numberWithDouble:(double)rotation]];
                            }
                            else {
                                id nullObject         = [NSNull null];
                                [positionsPerStrip addObject:nullObject];
                                [rotationsPerStrip addObject:nullObject];
                            }
                        }
                        if (positionsPerStrip.count > 0) {
                            [self.isoCurvesLabelsPositions addObject:positionsPerStrip];
                            [self.isoCurvesLabelsRotations addObject:rotationsPerStrip];
                        }
                        else {
                            id nullObject         = [NSNull null];
                            [self.isoCurvesLabelsPositions addObject:nullObject];
                            [self.isoCurvesLabelsRotations addObject:nullObject];
                        }
                    }
                    else {
                        id nullObject         = [NSNull null];
                        [self.isoCurvesLabelsPositions addObject:nullObject];
                        [self.isoCurvesLabelsRotations addObject:nullObject];
                    }
                }
                self.needsIsoCurvesUpdate = NO;
            }
            
            [self reloadContourLineStyles];
            [self reloadContourFills];
            
            CGPoint cornerPoints[2];
            cornerPoints[0] = CGPointMake((_limits[0] - thePlotSpace.xRange.locationDouble) * self.scaleX, (_limits[2] - thePlotSpace.yRange.locationDouble) * self.scaleY);
            cornerPoints[1] = CGPointMake((_limits[1] - thePlotSpace.xRange.locationDouble) * self.scaleX, (_limits[3] - thePlotSpace.yRange.locationDouble) * self.scaleY);
            if ( pixelAlign ) {
                [self alignViewPointsToUserSpace:cornerPoints withContext:currentContext numberOfPoints:2];
            }
            // easier naming edges
            CGFloat leftEdge = cornerPoints[0].x;
            CGFloat bottomEdge = cornerPoints[0].y;
            CGFloat rightEdge = cornerPoints[1].x;
            CGFloat topEdge = cornerPoints[1].y;
            
            CGMutablePathRef *boundaryLimitsDataLinePaths = NULL;
            NSUInteger noBoundaryLimitsDataLinePaths = 0;
            Strips discontinuityBorderStrips;
            initStrips(&discontinuityBorderStrips, 2);
            if ( self.functionPlot ) {
                // Attend to any discontinuities in the 3D function, by creating out of bounds
                // CGPaths, use the already accummulated discontinuity points from 'contours'
                noBoundaryLimitsDataLinePaths = [self pathsDiscontinuityRegions:&boundaryLimitsDataLinePaths context:currentContext contours:contours discontinuityStrips:&discontinuityBorderStrips leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
            }
            
            if ( self.fillIsoCurves && ((self.isoCurvesFills.count > 0 && [self.isoCurvesFills objectAtIndex:0] != [CPTPlot nilData]) || (self.isoCurvesLineStyles.count > 0 && [[self.isoCurvesLineStyles objectAtIndex:0] isKindOfClass:[CPTLineStyle class]])) ) {
                
                Strips combinedBorderStrips;
                Strips allEdgeBorderStrips[4];
                for( NSUInteger i = 0 ; i < 4; i++ ) {
                    initStrips(&allEdgeBorderStrips[i], 16);
                }
                
                BOOL *usedExtraLineStripLists = (BOOL*)malloc((size_t)[contours getIsoCurvesLists]->used * sizeof(BOOL));
                [self collectStripsForBorders:allEdgeBorderStrips usedExtraLineStripLists:usedExtraLineStripLists context:currentContext  contours:contours leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                
                // if there are discontinuity boundaries include the edges if any
                if ( noBoundaryLimitsDataLinePaths > 0 ) {
                    [self collectBorderDiscontinuityStrips:&discontinuityBorderStrips BorderStrips:allEdgeBorderStrips leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                }
                
                sortStripsByBorderDirection(&allEdgeBorderStrips[0], CPTContourBorderDimensionDirectionXForward);
                sortStripsByBorderDirection(&allEdgeBorderStrips[1], CPTContourBorderDimensionDirectionYForward);
                sortStripsByBorderDirection(&allEdgeBorderStrips[2], CPTContourBorderDimensionDirectionXBackward);
                sortStripsByBorderDirection(&allEdgeBorderStrips[3], CPTContourBorderDimensionDirectionYBackward);
                initStrips(&combinedBorderStrips, allEdgeBorderStrips[0].used + allEdgeBorderStrips[1].used + allEdgeBorderStrips[2].used + allEdgeBorderStrips[3].used);
                concatenateStrips(&combinedBorderStrips, allEdgeBorderStrips, 4);
                for( NSUInteger i = 0 ; i < 4; i++ ) {
                    freeStrips(&allEdgeBorderStrips[i]);
                }
                
                // check Strips with based on extraLineStripList to see that only 2 points touch the border,
                // rid LineStrip of points on same boundary except the one joining to another boundary
                if ( combinedBorderStrips.used > 0 ) {
                    removeDuplicatesStrips(&combinedBorderStrips);
                    for ( NSUInteger i = 0; i < combinedBorderStrips.used; i++ ) {
                        // if combinedBorderStrips.array[i].plane == NSNotFound, then a discontinuity strip
                        if ( combinedBorderStrips.array[i].plane != NSNotFound && usedExtraLineStripLists[combinedBorderStrips.array[i].plane] && (pStripList = combinedBorderStrips.array[i].pStripList) == [contours getExtraIsoCurvesListsAtIsoCurve:combinedBorderStrips.array[i].plane] ) {
                            pos = combinedBorderStrips.array[i].index;
                            if ( pos < pStripList->used ) {
                                pStrip = &pStripList->array[pos];
                                if( [contours removeExcessBoundaryNodeFromExtraLineStrip:pStrip] ) {
                                    NSUInteger indexStart = pStrip->array[0];
                                    NSUInteger indexEnd = pStrip->array[pStrip->used - 1];
                                    double startX = ([contours getXAt:indexStart] - thePlotSpace.xRange.locationDouble) * self.scaleX;
                                    double startY = ([contours getYAt:indexStart] - thePlotSpace.yRange.locationDouble) * self.scaleY;
                                    double endX = ([contours getXAt:indexEnd] - thePlotSpace.xRange.locationDouble) * self.scaleX;
                                    double endY = ([contours getYAt:indexEnd] - thePlotSpace.yRange.locationDouble) * self.scaleY;
                                    CGPoint startPoint = CGPointMake(startX, startY);
                                    CGPoint endPoint = CGPointMake(endX, endY);
                                    CGPoint convertPoints[2];
                                    convertPoints[0] = startPoint;
                                    convertPoints[1] = endPoint;
                                    [self convertPointsIfPixelAligned:currentContext points:convertPoints noPoints:2];
                                    startPoint = convertPoints[0];
                                    endPoint = convertPoints[1];
                                    if ( combinedBorderStrips.array[i].reverse ) {
                                        startPoint = endPoint;
                                        endPoint = convertPoints[0];
                                    }
                                    if ( !CGPointEqualToPoint(combinedBorderStrips.array[i].startPoint, startPoint) ) {
                                        combinedBorderStrips.array[i].startPoint = startPoint;
                                        combinedBorderStrips.array[i].startBorderdirection = [self findPointBorderDirection:startPoint leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                                    }
                                    if ( !CGPointEqualToPoint(combinedBorderStrips.array[i].endPoint, endPoint) ) {
                                        combinedBorderStrips.array[i].endPoint = endPoint;
                                        combinedBorderStrips.array[i].endBorderdirection = [self findPointBorderDirection:endPoint leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                                    }
                                }
                            }
                        }
                    }
                }
                
    #pragma mark Fill contours
                if ( combinedBorderStrips.used > 0 ) {
                    BorderIndices startEndPointIndices;
                    initBorderIndices(&startEndPointIndices, 2 * combinedBorderStrips.used);
                    sortStripsIntoStartEndPointPositions(&combinedBorderStrips, &startEndPointIndices);
                    if ( !self.extrapolateToLimits && !self.functionPlot ) {
                        [self joinBorderStripsToCreateClosedStrips:&combinedBorderStrips borderIndices:&startEndPointIndices usedExtraLineStripLists:usedExtraLineStripLists context:currentContext contours:(CPTContours *)contours leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                    }
                    else {
                        [self drawFillBetweenBorderIsoCurves:currentContext contours:contours borderStrips:&combinedBorderStrips borderIndices:&startEndPointIndices usedExtraLineStripLists:usedExtraLineStripLists leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge outerBoundaryLimitsCGPaths:boundaryLimitsDataLinePaths noOuterBoundaryLimitsCGPaths:noBoundaryLimitsDataLinePaths];
                    }
                    freeBorderIndices(&startEndPointIndices);
                }
                freeStrips(&combinedBorderStrips);
                
                [self drawFillBetweenClosedIsoCurves:currentContext contours:contours usedExtraLineStripLists:usedExtraLineStripLists leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                free(usedExtraLineStripLists);
            }
            freeStrips(&discontinuityBorderStrips);
            
            // draw the contours with a CPTLinestyle if available
            if ( self.isoCurvesLineStyles.count > 0 && [[self.isoCurvesLineStyles objectAtIndex:0] isKindOfClass:[CPTLineStyle class]] ) {
                ContourPoints stripContours;
                initContourPoints(&stripContours, 64);
                CGMutablePathRef dataLinePath;
#if DEBUG
    #if TARGET_OS_OSX
                NSBezierPath *bezierPath = [NSBezierPath bezierPath];
    #else
                UIBezierPath *bezierPath = [[UIBezierPath alloc] init];
    #endif
#endif
                NSUInteger maxIndicesSize = ([contours getNoRowsSecondaryGrid] + 1) * ([contours getNoColumnsSecondaryGrid] + 1);
                for ( NSUInteger iPlane = 0; iPlane < self.isoCurvesIndices.count; iPlane++ ) {
//                    if ( !(iPlane == 1 /*|| iPlane == 2*/) ) continue;
                    plane = [[self.isoCurvesIndices objectAtIndex:iPlane] unsignedIntegerValue];
//    #if DEBUG
//                    [contours dumpPlane:plane];
//    #endif
                    CPTMutableLineStyle *theContourLineStyle = [CPTMutableLineStyle lineStyleWithStyle: [self isoCurveLineStyleForIndex:plane]];
                    if( theContourLineStyle == nil ) {
                        theContourLineStyle = [self.isoCurveLineStyle mutableCopy];
                        theContourLineStyle.lineColor = [CPTColor colorWithComponentRed:(CGFloat)((float)plane / (float)[contours getNoIsoCurves]) green:(CGFloat)(1.0f - (float)plane / (float)[contours getNoIsoCurves]) blue:0.0 alpha:1.0];
                    }
                    theContourLineStyle.lineWidth = self.isoCurveLineStyle.lineWidth;
                    pStripList = [contours getStripListForIsoCurve:plane];
                    for ( pos = 0; pos < (NSUInteger)pStripList->used; pos++) {
                        pStrip = &pStripList->array[pos];
                        if (pStrip->used > 0 ) {
                            for ( pos2 = 0; pos2 < pStrip->used; pos2++ ) {
                                index = pStrip->array[pos2]; // retrieving index
                                if ( index < maxIndicesSize ) {
                                    // drawing
                                    x = [contours getXAt:index];
                                    y = [contours getYAt:index];
                                    point = CGPointMake(((x - thePlotSpace.xRange.locationDouble) * self.scaleX - self.originOfContext.x) * self.scaleOfContext, ((y - thePlotSpace.yRange.locationDouble) * self.scaleY - self.originOfContext.y) * self.scaleOfContext);
                                    appendContourPoints(&stripContours, point);
                                }
                            }

                            if ( stripContours.used > 0 ) {
                                if ( pixelAlign ) {
                                    [self alignViewPointsToUserSpace:stripContours.array withContext:currentContext numberOfPoints:stripContours.used];
                                }
                                // if a border contour, recheck that start & end are on border, else make contour closed
                                if ( !CGPointEqualToPoint(stripContours.array[0], stripContours.array[stripContours.used - 1]) ) {
                                    if ( (fabs(stripContours.array[0].x - (leftEdge - self.originOfContext.x)) < 0.5 || fabs(stripContours.array[0].x - (rightEdge - self.originOfContext.x)) < 0.5 ||  fabs(stripContours.array[0].y - (bottomEdge - self.originOfContext.y)) < 0.5 || fabs(stripContours.array[0].y - (topEdge - self.originOfContext.y)) < 0.5) && (fabs(stripContours.array[stripContours.used - 1].x - (leftEdge - self.originOfContext.x)) < 0.5 || fabs(stripContours.array[stripContours.used - 1].x - (rightEdge - self.originOfContext.x)) < 0.5 || fabs(stripContours.array[stripContours.used - 1].y - (bottomEdge - self.originOfContext.y)) < 0.5 || fabs(stripContours.array[stripContours.used - 1].y - (topEdge - self.originOfContext.y)) < 0.5) ) {
                                        ;
                                    }
                                    else {
                                        appendContourPoints(&stripContours, stripContours.array[0]);
                                    }
                                }
                                dataLinePath = [self newDataLinePathForViewPoints:stripContours.array indexRange: NSMakeRange(0, stripContours.used) extraStripList:NO];
                                if (!self.extrapolateToLimits && !self.functionPlot && !CGPointEqualToPoint(CGPathGetCurrentPoint(dataLinePath), CGPointMake(stripContours.array[0].x, stripContours.array[0].y)) /*&& self.joinContourLineStartToEnd*/) {
                                    CGPathAddLineToPoint(dataLinePath, NULL, stripContours.array[0].x, stripContours.array[0].y);
                                }
                                // Draw line
                                if ( theContourLineStyle && !CGPathIsEmpty(dataLinePath) ) {
                                    CGContextSaveGState(currentContext);
                                    CGContextBeginPath(currentContext);
                                    CGContextAddPath(currentContext, dataLinePath);
                                    [theContourLineStyle setLineStyleInContext:currentContext];
                                    [theContourLineStyle strokePathInContext:currentContext];
                                    CGContextRestoreGState(currentContext);
    #if DEBUG
    #if TARGET_OS_OSX
                                    NSBezierPath * bezierPath1 = [NSBezierPath bezierPathWithCGPath:dataLinePath];
                                    [bezierPath appendBezierPath:bezierPath1];
    #else
                                    UIBezierPath * bezierPath1 = [UIBezierPath bezierPathWithCGPath:dataLinePath];
                                    [bezierPath appendPath:bezierPath1];
    #endif
    #endif
                                }
                                CGPathRelease(dataLinePath);
                            }
                            clearContourPoints(&stripContours);
    #if DEBUG
                            CGImageRef imgRef = CGBitmapContextCreateImage(currentContext);
    #if TARGET_OS_OSX
                            NSImage* img = [[NSImage alloc] initWithCGImage:imgRef size: NSZeroSize];

                            NSImage* __unused flippedImage = [NSImage imageWithSize:img.size flipped:YES drawingHandler:^BOOL(NSRect dstRect) {
                                [img drawInRect:dstRect];
                                return YES;
                            }];
    #else
                            UIImage* img = [UIImage imageWithCGImage:imgRef];
                            CGSize size = img.size;
                            UIGraphicsBeginImageContext(CGSizeMake(size.width, size.height));
                            [[UIImage imageWithCGImage:imgRef scale:1.0 orientation:UIImageOrientationDownMirrored] drawInRect:CGRectMake(0, 0, size.width, size.height)];
                            UIImage* __unused flippedImage = UIGraphicsGetImageFromCurrentImageContext();
                            UIGraphicsEndImageContext();
    #endif
                            CGImageRelease(imgRef);
    #endif
                        }
                    }
                }
                freeContourPoints(&stripContours);
            }
            
            free(planesValues);
            contours = nil;
            
            // show & clean up discontinuity boundary memory
            if ( boundaryLimitsDataLinePaths != NULL ) {
                for( NSUInteger i = 0; i < noBoundaryLimitsDataLinePaths; i++ ) {
                    CPTMutableLineStyle *theContourLineStyle = [self.isoCurveLineStyle mutableCopy];
                    theContourLineStyle.lineColor = [CPTColor blackColor];
                    theContourLineStyle.lineWidth = self.isoCurveLineStyle.lineWidth / 2.0;
                    if ( !CGPathIsEmpty(boundaryLimitsDataLinePaths[i]) ) {
                        CGContextSaveGState(currentContext);
                        CGContextBeginPath(currentContext);
                        CGContextAddPath(currentContext, boundaryLimitsDataLinePaths[i]);
                        [theContourLineStyle setLineStyleInContext:currentContext];
                        [theContourLineStyle strokePathInContext:currentContext];
                        CGContextRestoreGState(currentContext);
    #if DEBUG
    #if TARGET_OS_OSX
                        NSBezierPath * __unused bezierPath1 = [NSBezierPath bezierPathWithCGPath:boundaryLimitsDataLinePaths[i]];
    #else
                        UIBezierPath * __unused bezierPath1 = [UIBezierPath bezierPathWithCGPath:boundaryLimitsDataLinePaths[i]];
    #endif
                        NSLog(@"stop");
    #endif
                    }
                    if( !CGPathIsEmpty(boundaryLimitsDataLinePaths[i]) ) {
                        CGPathRelease(boundaryLimitsDataLinePaths[i]);
                    }
                }
                free(boundaryLimitsDataLinePaths);
            }
            
            if ( self.fillIsoCurves && self.isoCurvesFillings.count > 1 ) {
                [self.isoCurvesFillings sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                    CPTContourFill *filling1 = (CPTContourFill*)obj1;
                    CPTContourFill *filling2 = (CPTContourFill*)obj2;
                    size_t numComponents1 = CGColorGetNumberOfComponents(filling1.fill.cgColor);
                    const CGFloat *colour1 = CGColorGetComponents(filling1.fill.cgColor);
                    size_t numComponents2 = CGColorGetNumberOfComponents(filling2.fill.cgColor);
                    const CGFloat *colour2 = CGColorGetComponents(filling2.fill.cgColor);
                    CGFloat red1, red2, hue1, hue2;
                    CGFloat green1, green2, saturation1, saturation2;
                    CGFloat blue1, blue2, lightness1, lightness2;
                    CGFloat alpha1, alpha2;
                    if (numComponents1 == 2) {
                        red1 = colour1[0];
                        green1 = colour1[0];
                        blue1 = colour1[0];
                        alpha1 = colour1[1];
                    }
                    else {
                        red1 = colour1[0];
                        green1 = colour1[1];
                        blue1 = colour1[2];
                        alpha1 = colour1[3];
                    }
                    if (numComponents2 == 2) {
                        red2 = colour2[0];
                        green2 = colour2[0];
                        blue2 = colour2[0];
                        alpha2 = colour2[1];
                    }
                    else {
                        red2 = colour2[0];
                        green2 = colour2[1];
                        blue2 = colour2[2];
                        alpha2 = colour2[3];
                    }
                    
                    ColorRGBtoHSL(red1, green1, blue1, &hue1, &saturation1, &lightness1);
                    ColorRGBtoHSL(red2, green2, blue2, &hue2, &saturation2, &lightness2);
                    
                    if ( hue1 == hue2 ) {
                        return alpha1 < alpha2 ? (NSComparisonResult)NSOrderedAscending : (NSComparisonResult)NSOrderedDescending;
                    }
                    else {
                        return hue1 > hue2 ? (NSComparisonResult)NSOrderedAscending : (NSComparisonResult)NSOrderedDescending;
                    }
                    //                if ( red1 == red2 ) {
                    //                    if ( green1 == green2 ) {
                    //                        if ( blue1 == blue2 )  {
                    //                            return alpha1 < alpha2 ? (NSComparisonResult)NSOrderedAscending : (NSComparisonResult)NSOrderedDescending;
                    //                        }
                    //                        else {
                    //                            return blue1 < blue2 ? (NSComparisonResult)NSOrderedAscending : (NSComparisonResult)NSOrderedDescending;
                    //                        }
                    //                    }
                    //                    else {
                    //                        return green1 < green2 ? (NSComparisonResult)NSOrderedAscending : (NSComparisonResult)NSOrderedDescending;
                    //                    }
                    //                }
                    //                else {
                    //                    return red1 < red2 ? (NSComparisonResult)NSOrderedAscending : (NSComparisonResult)NSOrderedDescending;
                    //                }
                }];
                for ( CPTContourFill *filling in self.isoCurvesFillings ) {
                    const CGFloat *colour = CGColorGetComponents(filling.fill.cgColor);
                    if ( filling.firstValue == nil ) {
                        printf("<%f\t\t%f %f %f %f\n", [filling.secondValue doubleValue], colour[0], colour[1], colour[2], colour[3]);
                    }
                    else if ( filling.secondValue == nil ) {
                        printf(">%f\t\t%f %f %f %f\n", [filling.firstValue doubleValue], colour[0], colour[1], colour[2], colour[3]);
                    }
                    else {
                        if ( [filling.secondValue doubleValue] < [filling.firstValue doubleValue] ) {
                            printf("%f\t%f\t%f %f %f %f\n", [filling.secondValue doubleValue], [filling.firstValue doubleValue], colour[0], colour[1], colour[2], colour[3]);
                        }
                        else {
                            printf("%f\t%f\t%f %f %f %f\n", [filling.firstValue doubleValue], [filling.secondValue doubleValue], colour[0], colour[1], colour[2], colour[3]);
                        }
                    }
                }
            }
            
            // Draw plot symbols
            if ( self.plotSymbol || self.plotSymbols.count ) {
                Class symbolClass = [CPTPlotSymbol class];
                
                // clear the plot shadow if any--symbols draw their own shadows
                CGContextSetShadowWithColor(currentContext, CGSizeZero, (CGFloat)0.0, NULL);
                
                if ( self.useFastRendering ) {
#if TARGET_OS_OSX
                    CGFloat scale = self.scaleOfContext;
#else
                    CGFloat scale = self.contentsScale;
#endif
                    for ( NSUInteger i = (NSUInteger)firstDrawnPointIndex; i <= (NSUInteger)lastDrawnPointIndex; i++ ) {
                        if ( drawPointFlags[i] ) {
                            CPTPlotSymbol *currentSymbol = [self plotSymbolForRecordIndex:i];
                            if ( [currentSymbol isKindOfClass:symbolClass] ) {
                                point = CGPointMake((viewPoints[i].x - self.originOfContext.x) * self.scaleOfContext, (viewPoints[i].y - self.originOfContext.y) * self.scaleOfContext);
                                [currentSymbol renderInContext:currentContext atPoint:point scale:scale alignToPixels:pixelAlign];
                            }
                        }
                    }
                }
                else {
                    for ( NSUInteger i = (NSUInteger)firstDrawnPointIndex; i <= (NSUInteger)lastDrawnPointIndex; i++ ) {
                        if ( drawPointFlags[i] ) {
                            CPTPlotSymbol *currentSymbol = [self plotSymbolForRecordIndex:i];
                            if ( [currentSymbol isKindOfClass:symbolClass] ) {
                                point = CGPointMake((viewPoints[i].x - self.originOfContext.x) * self.scaleOfContext, (viewPoints[i].y - self.originOfContext.y) * self.scaleOfContext);
                                [currentSymbol renderAsVectorInContext:currentContext atPoint:point scale:(CGFloat)1.0];
                            }
                        }
                    }
                }
            }
            
            // make image of contours
            CGImageRef imageRef = CGBitmapContextCreateImage(currentContext);
            NSData* imageData;
#if TARGET_OS_OSX
            [self.macOSImage unlockFocus];
            NSImage* image = [[NSImage alloc] initWithCGImage:imageRef size: NSZeroSize];
//            NSImage* flippedImage = [NSImage imageWithSize:self.macOSImage.size flipped:YES drawingHandler:^BOOL(NSRect dstRect) {
//                    [self.macOSImage drawInRect:dstRect];
//                    return YES;
//                }];
            NSData *tiffData = [image TIFFRepresentation];
            NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:tiffData];
            imageData = [imageRep representationUsingType:NSBitmapImageFileTypePNG properties:[NSDictionary dictionaryWithObjectsAndKeys:NSImageCompressionFactor, [NSNumber numberWithInt:1], nil]];
//            [[image TIFFRepresentation] writeToFile:imageFilePath atomically:NO];
            image = nil;
//            flippedImage = nil;
#else
            // Convert back to UIImage and flip to correct way up
            UIImage* image = [UIImage imageWithCGImage:imageRef];
            CGSize size = image.size;
            UIGraphicsBeginImageContext(CGSizeMake(size.width, size.height));
            [[UIImage imageWithCGImage:imageRef scale:1.0 orientation:UIImageOrientationDownMirrored] drawInRect:CGRectMake(0, 0, size.width, size.height)];
            UIImage* flippedImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
                         
            imageData = UIImagePNGRepresentation(flippedImage);
            image = nil;
            flippedImage = nil;
            
            // clear up working CGContext(currentContext) if no extrapolate to corners and a data based contour plot
            // size will be bigger than Device screen size
            UIGraphicsEndImageContext();
#endif
            [imageData writeToFile:imageFilePath atomically:YES];
            CGContextRestoreGState(context);
            // Clean up reference pointers
            CGImageRelease(imageRef);
            
            self.initialXRange = [thePlotSpace.xRange mutableCopy];
            self.initialYRange = [thePlotSpace.yRange mutableCopy];
            self.previousLimits = [NSMutableArray arrayWithObjects:[NSNumber numberWithDouble:limit0], [NSNumber numberWithDouble:limit1], [NSNumber numberWithDouble:limit2], [NSNumber numberWithDouble:limit3], nil];
            self.needsIsoCurvesRelabel = YES;
        }
        
        if ( !self.needsIsoCurvesUpdate ) {
            CGContextSaveGState(context);
            CGFloat imageScaleX = 1.0, imageScaleY = 1.0;
#if TARGET_OS_OSX
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:imageFilePath];
            CGImageRef imageRef = [image CGImageForProposedRect:nil context:[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO] hints:nil];
            imageScaleX = 1 / self.plotArea.contentsScale;
            imageScaleY = 1 / self.plotArea.contentsScale;
#else
            UIImage* image = [UIImage imageWithContentsOfFile:imageFilePath];
            
            NSInteger display = 0; // standard display
            if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)] && [[UIScreen mainScreen] scale] == 2.0) {
                display = 1; // is retina display
            }
            else if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)] && [[UIScreen mainScreen] scale] == 3.0) {
                display = 4; // is retina display
            }
            if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
                display += 2;
            }
            
            if (display == 1 || display == 3) {
                imageScaleX = 0.5;
                imageScaleY = 0.5;
            }
            else if (display == 4) {
                imageScaleX = 1.0 / 3.0;
                imageScaleY = 1.0 / 3.0;
            }
            CGImageRef imageRef = [image CGImage];
#endif

            double plotPoint[2][2];
//            plotPoint[0][CPTCoordinateX] = self.previousLimits[0].doubleValue;
//            plotPoint[0][CPTCoordinateY] = self.previousLimits[2].doubleValue;
//            plotPoint[1][CPTCoordinateX] = self.previousLimits[1].doubleValue;
//            plotPoint[1][CPTCoordinateY] = self.previousLimits[3].doubleValue;
            plotPoint[0][CPTCoordinateX] = self.limits[0].doubleValue;
            plotPoint[0][CPTCoordinateY] = self.limits[2].doubleValue;
            plotPoint[1][CPTCoordinateX] = self.limits[1].doubleValue;
            plotPoint[1][CPTCoordinateY] = self.limits[3].doubleValue;
                
            CGPoint posLimits[2] = { [thePlotSpace plotAreaViewPointForDoublePrecisionPlotPoint:plotPoint[0] numberOfCoordinates:2], [thePlotSpace plotAreaViewPointForDoublePrecisionPlotPoint:plotPoint[1] numberOfCoordinates:2] };
            if( pixelAlign ) {
                [self alignViewPointsToUserSpace:posLimits withContext:context numberOfPoints:2];
            }
            
            CGFloat xOffset = 0, yOffset = 0;
            CGFloat xWidth = CGImageGetWidth(imageRef), yHeight = CGImageGetHeight(imageRef);
            CGFloat xWidthOriginal = xWidth, yHeightOriginal = yHeight;
            if ( plotPoint[0][CPTCoordinateX] < thePlotSpace.xRange.minLimitDouble ) {
                xOffset = (-posLimits[0].x - extraWidth) / imageScaleX;
                xWidth =  posLimits[1].x / imageScaleX;
            }
            else if ( plotPoint[1][CPTCoordinateX] > thePlotSpace.xRange.maxLimitDouble ) {
                xWidth -= (posLimits[1].x - self.maxWidthPixels - extraWidth) / imageScaleX;
            }
            if ( plotPoint[0][CPTCoordinateY] < thePlotSpace.yRange.minLimitDouble ) {
                yHeight = (posLimits[1].y + extraHeight) / imageScaleY;
            }
            else if ( plotPoint[1][CPTCoordinateY] > thePlotSpace.yRange.maxLimitDouble ) {
                yOffset = (posLimits[1].y - self.maxHeightPixels - extraHeight) / imageScaleY;
                yHeight -= yOffset;
            }
            CGRect rect = CGRectMake(posLimits[0].x - extraWidth < 0 ? 0 : posLimits[0].x - extraWidth, posLimits[0].y - extraHeight < 0 ? 0 : posLimits[0].y - extraHeight, xWidth, yHeight);
            CGContextScaleCTM(context, imageScaleX, imageScaleY);
            CGContextTranslateCTM(context, posLimits[0].x - extraWidth < 0 ? 0 : posLimits[0].x - extraWidth, posLimits[0].y - extraHeight < 0 ? 0 : posLimits[0].y - extraHeight);
            if ( xOffset != 0.0 || yOffset != 0.0 || xWidth != xWidthOriginal || yHeight != yHeightOriginal ) {
                CGRect imageArea = CGRectMake (xOffset, yOffset, xWidth, yHeight);
                CGImageRef subImageRef = CGImageCreateWithImageInRect (imageRef, imageArea);
                CGContextDrawImage(context, rect, subImageRef);
                CGImageRelease(subImageRef);
            }
            else {
                CGContextDrawImage(context, rect, imageRef);
            }
            CGContextRestoreGState(context);
            
            CPTGraph *theGraph = self.graph;
            if ( theGraph.allowTracking ) {
                [self updateTrackingAreas];
                [self updateIsoCurveTrackingAreas];
            }
        }
        self.previousFillIsoCurves = self.fillIsoCurves;
    }
    
    free(viewPoints);
    free(drawPointFlags);
}
                   
-(void)convertPointsIfPixelAligned:(nonnull CGContextRef)context points:(CGPoint*)points noPoints:(NSUInteger)noPoints {
        if ( self.alignsPointsToPixels ) {
            [self alignViewPointsToUserSpace:points withContext:context numberOfPoints:noPoints];
        }
    }
                   
-(CPTContourBorderDimensionDirection) startBorderDirectionFromEdge:(NSUInteger)index startSideDimension:(CGFloat*)startSideDimension endSideDimension:(CGFloat*)endSideDimension adjacentSideDimension:(CGFloat*)adjacentSideDimension leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge perimeters:(CGPoint*)perimeterPoints {
        CPTContourBorderDimensionDirection startBorderdirection;
        if ( index % 2 == 0 ) {
            *startSideDimension = perimeterPoints[index].x;
            *endSideDimension = perimeterPoints[index+1].x;
            if (index > 0) {
                startBorderdirection = CPTContourBorderDimensionDirectionXBackward;
                *adjacentSideDimension = topEdge;
            }
            else {
                startBorderdirection = CPTContourBorderDimensionDirectionXForward;
                *adjacentSideDimension = bottomEdge;
            }
        }
        else {
            *startSideDimension = perimeterPoints[index].y;
            *endSideDimension = perimeterPoints[index+1].y;
            if (index > 1) {
                startBorderdirection = CPTContourBorderDimensionDirectionYBackward;
                *adjacentSideDimension = leftEdge;
            }
            else {
                startBorderdirection = CPTContourBorderDimensionDirectionYForward;
                *adjacentSideDimension = rightEdge;
            }
        }
        return startBorderdirection;
    }
                   
-(void) addCornersToDataLinePath:(CGMutablePathRef*)dataLineBorderPath startBorderdirection:(CPTContourBorderDimensionDirection)startBorderdirection endBorderdirection:(CPTContourBorderDimensionDirection)endBorderdirection leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge mirror:(BOOL)mirror {
        CGPoint cornerRectPoints[4] = { CGPointMake(leftEdge, bottomEdge), CGPointMake(rightEdge, bottomEdge), CGPointMake(rightEdge, topEdge), CGPointMake(leftEdge, topEdge) };
        CGAffineTransform transform = CGAffineTransformIdentity;
        switch(startBorderdirection) {
            case CPTContourBorderDimensionDirectionXForward:
                if ( endBorderdirection == CPTContourBorderDimensionDirectionYForward ) {
                    CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[1].x, cornerRectPoints[1].y);
                }
                else if ( endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                    CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[0].x, cornerRectPoints[0].y);
                }
                else if ( endBorderdirection == CPTContourBorderDimensionDirectionXBackward ) {
                    if ( mirror ) {
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[1].x, cornerRectPoints[1].y);
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[2].x, cornerRectPoints[2].y);
                    }
                    else {
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[0].x, cornerRectPoints[0].y);
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[1].x, cornerRectPoints[1].y);
                    }
                }
                break;
            case CPTContourBorderDimensionDirectionYForward:
                if ( endBorderdirection == CPTContourBorderDimensionDirectionXBackward ) {
                    CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[2].x, cornerRectPoints[2].y);
                }
                else if ( endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                    CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[1].x, cornerRectPoints[1].y);
                }
                else if ( endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                    if ( mirror ) {
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[2].x, cornerRectPoints[2].y);
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[3].x, cornerRectPoints[3].y);
                    }
                    else {
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[1].x, cornerRectPoints[1].y);
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[2].x, cornerRectPoints[2].y);
                    }
                }
                break;
            case CPTContourBorderDimensionDirectionXBackward:
                if ( endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                    CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[3].x, cornerRectPoints[3].y);
                }
                else if ( endBorderdirection == CPTContourBorderDimensionDirectionYForward ) {
                    CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[2].x, cornerRectPoints[2].y);
                }
                else if ( endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                    if ( mirror ) {
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[0].x, cornerRectPoints[0].y);
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[1].x, cornerRectPoints[1].y);
                    }
                    else {
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[3].x, cornerRectPoints[3].y);
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[0].x, cornerRectPoints[0].y);
                    }
                }
                break;
            case CPTContourBorderDimensionDirectionYBackward:
            default:
                if ( endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                    CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[0].x, cornerRectPoints[0].y);
                }
                else if ( endBorderdirection == CPTContourBorderDimensionDirectionXBackward ) {
                    CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[3].x, cornerRectPoints[3].y);
                }
                else if ( endBorderdirection == CPTContourBorderDimensionDirectionYForward ) {
                    if ( mirror ) {
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[1].x, cornerRectPoints[1].y);
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[2].x, cornerRectPoints[2].y);
                    }
                    else {
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[0].x, cornerRectPoints[0].y);
                        CGPathAddLineToPoint(*dataLineBorderPath, &transform, cornerRectPoints[1].x, cornerRectPoints[1].y);
                    }
                }
                break;
        }
    }
                   
-(void) drawFillBetweenClosedIsoCurves:(nonnull CGContextRef)context contours:(CPTContours *)contours usedExtraLineStripLists:(BOOL*)usedExtraLineStripLists leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
        
    CGAffineTransform transform = CGAffineTransformIdentity;
    CPTFill *theFill;
    Strips closedStrips;   // closed isocurves
    initStrips(&closedStrips, 8);
    // look for all closed strips ie not touching boundary
    NSUInteger *collectedPlanes = (NSUInteger*)calloc(1, sizeof(NSUInteger));
    NSUInteger countCollectedPlanes = 1, actualPlane, plane;
    CGPoint startPoint;
    
    // go through all the planes
    for ( NSInteger i = 0; i < (NSInteger)self.isoCurvesIndices.count; i++ ) {
        actualPlane = [[self.isoCurvesIndices objectAtIndex:(NSUInteger)i] unsignedIntegerValue];
//                    if ( !(actualPlane == 1 || actualPlane == 2 || actualPlane == 3) ) continue;
        collectedPlanes[0] = actualPlane;
        // search for all the closed isocurves for this plane and store in closedStrips
        [self searchPlaneClosedIsoCurves:context contours:contours Plane:actualPlane ClosedStrips:&closedStrips useExtraLineStripList:usedExtraLineStripLists[actualPlane]];
        // go through the isocurves in each plane
        for( NSUInteger j = 0; j < (NSUInteger)closedStrips.used; j++ ) {
            countCollectedPlanes = 1;
            collectedPlanes[0] = actualPlane;
            CGMutablePathRef refDataLinePath = CGPathCreateMutable();
            [self createClosedDataLinePath:&refDataLinePath context:context contours:contours strip:closedStrips index:j startPoint:&startPoint];
            if ( !CGPathIsEmpty(refDataLinePath) ) {
                if( !self.extrapolateToLimits && !self.functionPlot && !CGPointEqualToPoint(CGPathGetCurrentPoint(refDataLinePath), startPoint)) {
                    CGPathAddLineToPoint(refDataLinePath, &transform, startPoint.x, startPoint.y);
                }
                CGMutablePathRef *foundDataLinePaths = (CGMutablePathRef*)calloc(1, sizeof(CGMutablePathRef));
                NSUInteger *foundPlanes = (NSUInteger*)calloc(1, sizeof(NSUInteger));
                // now find any paths that are within this contour
                NSUInteger noFoundDataLinePaths = 0;
                // check if any of other closedStrips for this plane are inside refDataLinePath
                for(NSUInteger k = 0; k < (NSUInteger)closedStrips.used; k++) {
                    if( k == j) {
                        continue;
                    }
                    
                    if ( CGPathContainsPoint(refDataLinePath, &transform, closedStrips.array[k].startPoint, YES) ) {
                        CGMutablePathRef innerRefDataLinePath = CGPathCreateMutable();
                        [self createClosedDataLinePath:&innerRefDataLinePath context:context contours:contours strip:closedStrips index:k startPoint:&startPoint];
                        foundDataLinePaths[noFoundDataLinePaths] = CGPathCreateMutableCopy(innerRefDataLinePath);
                        foundPlanes[noFoundDataLinePaths] = closedStrips.array[k].plane;
#if TARGET_OS_OSX
                        NSBezierPath *bezierPath4 = [NSBezierPath  bezierPathWithCGPath:refDataLinePath];
                        [bezierPath4 appendBezierPath:[NSBezierPath bezierPathWithCGPath:innerRefDataLinePath]];
#else
                        UIBezierPath *bezierPath4 = [UIBezierPath  bezierPathWithCGPath:refDataLinePath];
                        [bezierPath4 appendPath:[UIBezierPath bezierPathWithCGPath:innerRefDataLinePath]];
#endif
                        CGPathRelease(innerRefDataLinePath);
                        noFoundDataLinePaths++;
                        foundDataLinePaths = (CGMutablePathRef*)realloc(foundDataLinePaths, sizeof(CGMutablePathRef) * (size_t)(noFoundDataLinePaths + 1));
                        foundPlanes = (NSUInteger*)realloc(foundPlanes, sizeof(NSUInteger) * (size_t)(noFoundDataLinePaths + 1));
                    }
                }
                CGContextSaveGState(context);
                
                plane = (NSUInteger)i;
                noFoundDataLinePaths = [self findClosedDataLinePaths:&foundDataLinePaths noFoundClosedDataLinePaths:noFoundDataLinePaths foundClosedPlanes:&foundPlanes OuterCGPath:&refDataLinePath context:context contours:contours plane:plane leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge ascendingOrder:YES useExtraLineStripList:(BOOL)closedStrips.array[j].extra fromCurrentPlane:NO checkPointOnPath:NO];

//                if ( noFoundDataLinePaths == 0 ) {
                    noFoundDataLinePaths = [self findClosedDataLinePaths:&foundDataLinePaths noFoundClosedDataLinePaths:noFoundDataLinePaths foundClosedPlanes:&foundPlanes OuterCGPath:&refDataLinePath context:context contours:contours plane:plane leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge ascendingOrder:NO useExtraLineStripList:(BOOL)closedStrips.array[j].extra fromCurrentPlane:NO checkPointOnPath:NO];
//                }
                // just check if we've missed a path inside another, if so get rid of smaller path
                for(NSInteger k = 0; k < (NSInteger)noFoundDataLinePaths; k++) {
#if DEBUG
    #if TARGET_OS_OSX
                    NSBezierPath * __unused bezierPath9 = [NSBezierPath bezierPathWithCGPath:foundDataLinePaths[k]];
    #else
                    UIBezierPath * __unused bezierPath9 = [UIBezierPath bezierPathWithCGPath:foundDataLinePaths[k]];
    #endif
#endif
                    for( NSInteger l = 0; l < (NSInteger)noFoundDataLinePaths; l++ ) {
                        if( l == k ) {
                            continue;
                        }
                        CGPoint centreOfPath = GetCenterPointOfCGPath(foundDataLinePaths[l]);
                        if ( CGPathContainsPoint(foundDataLinePaths[k], &transform, centreOfPath, YES) ) {
                            for ( NSInteger m = l; m < (NSInteger)noFoundDataLinePaths; m++ ) {
                                foundDataLinePaths[m] = foundDataLinePaths[m + 1];
                                foundPlanes[m] = foundPlanes[m + 1];
                            }
                            noFoundDataLinePaths--;
                            if (k > 0) {
                                k--;
                            }
                        }
                    }
                }
                for ( NSUInteger l = 0; l < noFoundDataLinePaths; l++ ) {
                    collectedPlanes = (NSUInteger*)realloc(collectedPlanes, sizeof(NSUInteger) * (size_t)(countCollectedPlanes + 1));
                    collectedPlanes[countCollectedPlanes] = foundPlanes[l];// [[self.isoCurvesIndices objectAtIndex:plane > self.isoCurvesIndices.count - 1 ? self.isoCurvesIndices.count - 1 : plane] unsignedIntegerValue];
                    countCollectedPlanes++;
                }
                
                if ( !CGPathIsEmpty(refDataLinePath) ) {
                    CGContextAddPath(context, refDataLinePath);
#if DEBUG
    #if TARGET_OS_OSX
                    NSBezierPath *bezierPath = [NSBezierPath  bezierPathWithCGPath:refDataLinePath];
    #else
                    UIBezierPath *bezierPath = [UIBezierPath  bezierPathWithCGPath:refDataLinePath];
    #endif
#endif
                    
                    for( NSUInteger k = 0; k < noFoundDataLinePaths; k++ ) {
                        if( !self.extrapolateToLimits && !self.functionPlot ) {
                            CGPathCloseSubpath(foundDataLinePaths[k]);
                        }
#if DEBUG
    #if TARGET_OS_OSX
                        NSBezierPath *bezierPath1 = [NSBezierPath bezierPathWithCGPath:foundDataLinePaths[k]];
                        [bezierPath appendBezierPath:bezierPath1];
    #else
                        UIBezierPath *bezierPath1 = [UIBezierPath bezierPathWithCGPath:foundDataLinePaths[k]];
                        [bezierPath appendPath:bezierPath1];
    #endif
                        CGContextAddPath(context, foundDataLinePaths[k]);
#endif
                    }
                }
                
                for( NSUInteger k = 0; k < noFoundDataLinePaths; k++ ) {
                    CGPathRelease(foundDataLinePaths[k]);
                }
                free(foundDataLinePaths);
                free(foundPlanes);
                
                if ( countCollectedPlanes == 1 ) {
#if DEBUG
#if TARGET_OS_OSX
                    NSBezierPath * __unused bezierPath = [NSBezierPath  bezierPathWithCGPath:refDataLinePath];
#else
                    UIBezierPath * __unused bezierPath = [UIBezierPath  bezierPathWithCGPath:refDataLinePath];
#endif
#endif
                    //                    theFill = [self findFillFromBoundingPlanes:collectedPlanes noCollectedPlanes:countCollectedPlanes];
                    theFill = [self calculateFill:refDataLinePath combinedPath:NULL collectedPlanes:collectedPlanes noCollectedPlanes:countCollectedPlanes];
                }
                else {
                    // rid duplicates collectedPlanes
                    for ( NSUInteger l = 0; l < countCollectedPlanes; l++ ) {
                        for ( NSUInteger m = l + 1; m < countCollectedPlanes; m++ ) {
                            if ( collectedPlanes[l] == collectedPlanes[m] ) {
                                countCollectedPlanes--;
                                for ( NSUInteger n = m; n < countCollectedPlanes; n++) {
                                    collectedPlanes[n] = collectedPlanes[n + 1];
                                }
                                m--;
                            }
                        }
                    }

                    theFill = [self findFillFromBoundingPlanes:collectedPlanes noCollectedPlanes:countCollectedPlanes];
                        //                        theFill = [self calculateFill:outerCheckValueCGPath combinedPath:innerCheckValueCGPath collectedPlanes:collectedPlanes];
                    
                }
                
                if ( theFill && [theFill isKindOfClass:[CPTFill class]] ) {
                    CGContextSetFillColorWithColor(context, theFill.cgColor);
                }
                
                CGContextSetFillColorWithColor(context, theFill.cgColor);
                CGContextEOFillPath(context);
                
#if DEBUG
                CGImageRef imgRef = CGBitmapContextCreateImage(context);
#if TARGET_OS_OSX
                NSImage* img = [[NSImage alloc] initWithCGImage:imgRef size: NSZeroSize];
                
                NSImage* __unused flippedImage = [NSImage imageWithSize:img.size flipped:YES drawingHandler:^BOOL(NSRect dstRect) {
                    [img drawInRect:dstRect];
                    return YES;
                }];
#else
                UIImage* img = [UIImage imageWithCGImage:imgRef];
                CGSize size = img.size;
                UIGraphicsBeginImageContext(CGSizeMake(size.height, size.width));
                [[UIImage imageWithCGImage:imgRef scale:1.0 orientation:UIImageOrientationDownMirrored] drawInRect:CGRectMake(0, 0, size.width, size.height)];
                UIImage* __unused flippedImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
#endif
                CGImageRelease(imgRef);
#endif
                CGContextRestoreGState(context);
            }
            else {
                NSLog(@"%f %f", CGPathGetCurrentPoint(refDataLinePath).x, CGPathGetCurrentPoint(refDataLinePath).y);
            }
            CGPathRelease(refDataLinePath);
        }
        clearStrips(&closedStrips);
    }
    freeStrips(&closedStrips);
    free(collectedPlanes);
}
                   
-(void) drawFillBetweenBorderIsoCurves:(nonnull CGContextRef)context contours:(CPTContours *)contours borderStrips:(Strips*)borderStrips borderIndices:(BorderIndices*)borderIndices usedExtraLineStripLists:(BOOL*)usedExtraLineStripLists leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge outerBoundaryLimitsCGPaths:(CGMutablePathRef*)outerBoundaryLimitsCGPaths noOuterBoundaryLimitsCGPaths:(NSUInteger)noOuterBoundaryLimitsCGPaths {
        
        CGPoint cornerPoints[4], centre;
        CGFloat cornerAngles[4], offset = 0;
        
        // now include corners if needed to borderIndices array start from bottom left corner
        cornerPoints[0] = CGPointMake(leftEdge, bottomEdge);
        cornerPoints[1] = CGPointMake(rightEdge, bottomEdge);
        cornerPoints[2] = CGPointMake(rightEdge, topEdge);
        cornerPoints[3] = CGPointMake(leftEdge, topEdge);
        
        centre = CGPointMake((leftEdge + rightEdge) / 2.0, (bottomEdge + topEdge) / 2.0);
        cornerAngles[0] = atan2(leftEdge - centre.x, bottomEdge - centre.y);
        cornerAngles[1] = atan2(rightEdge - centre.x, bottomEdge - centre.y);
        cornerAngles[2] = atan2(rightEdge - centre.x, topEdge - centre.y);
        cornerAngles[3] = atan2(leftEdge - centre.x, topEdge - centre.y);
        offset = -cornerAngles[0];
        cornerAngles[0] = 2.0 * M_PI;
        cornerAngles[1] += offset;
        cornerAngles[2] += offset;
        cornerAngles[3] += offset;
        
        NSUInteger corner = 0, start = 0;
        if ( !CGPointEqualToPoint(borderIndices->array[0].point, cornerPoints[0]) ) {
            BorderIndex element = initBorderIndex();
            element.point = cornerPoints[corner];
            insertBorderIndicesAtIndex(borderIndices, element, 0);
            corner++;
            start = 1;
        }
        
        NSUInteger i = start, j = start + 1;
        CGFloat thetaI, thetaJ;
        while ( i < borderIndices->used - 1 ) {
            if ( j == borderIndices->used ) {
                j = 0;
            }
            if ( corner == 4 ) {
                break;
            }
            thetaI = atan2(borderIndices->array[i].point.x - centre.x, borderIndices->array[i].point.y - centre.y) + offset;
            if( thetaI < 0 ) {
                thetaI = cornerAngles[0] + thetaI;
            }
            thetaJ = atan2(borderIndices->array[j].point.x - centre.x, borderIndices->array[j].point.y - centre.y) + offset;
            if( thetaJ < 0 ) {
                thetaJ = cornerAngles[0] + thetaJ;
            }
            if( thetaI > cornerAngles[corner] && thetaJ < cornerAngles[corner] ) {
                BorderIndex element = initBorderIndex();
                element.point = cornerPoints[corner];
                insertBorderIndicesAtIndex(borderIndices, element, j);
                corner++;
                continue;
            }
            else if ( CGPointEqualToPoint(borderIndices->array[i].point, cornerPoints[corner]) ) {
                corner++;
                continue;
            }
            else if ( thetaI < cornerAngles[corner] && thetaJ < cornerAngles[corner] ) {
                BorderIndex element = initBorderIndex();
                element.point = cornerPoints[corner];
                insertBorderIndicesAtIndex(borderIndices, element, i);
                corner++;
                continue;
            }
            i++;
            j++;
        }
        
        // if extra contours involved for a functionPlot, sort the borderIndices array correctly
        BOOL usedExtraLineStripList = NO;
        for( i = 0; i < [contours getIsoCurvesLists]->used; i++ ) {
            usedExtraLineStripList |= usedExtraLineStripLists[i];
        }
        if( usedExtraLineStripList ) {
            sortBorderIndicesWithExtraContours(borderIndices);
            authenticateNextToDuplicatesBorderIndices(borderIndices);
        }
        
        // since border intersection point go around the boundary line anti-clockwise staring in bottom left we need to shift the
        // borderIndices to the right to make sure we see all the complex regions
        // shift borderIndices such that if first and last are the same contour, move first to last
        // till array is split across a complex region
        CPTFill *theFill;
        //    id nilObject                    = [CPTPlot nilData];
        CGAffineTransform transform = CGAffineTransformIdentity;
        CGMutablePathRef dataLinePath;
        
        Centroids centroids;
        initCentroids(&centroids, 8);
        NSUInteger *positionsForBorderStripIndex = (NSUInteger*)calloc(1, sizeof(NSUInteger));
        
        NSUInteger *collectedPlanes, countCollectedPlanes;
        CGPoint startPoint, endPoint;
        LineStrip *pStrip;
        BOOL reverse, containsACorner, consecutiveEdge;
        NSUInteger borderIndex = 0, initialBorderIndex = 0, nextBorderIndex = NSNotFound, index;
        while ( borderIndex < borderIndices->used ) {
            containsACorner = NO;
            consecutiveEdge = NO;
            countCollectedPlanes = 0;
            collectedPlanes = (NSUInteger*)calloc(2, sizeof(NSUInteger));
            dataLinePath = CGPathCreateMutable();
            while ( borderIndices->array[borderIndex].borderdirection == CPTContourBorderDimensionDirectionNone ) {
                borderIndex++;
                if ( borderIndex >= borderIndices->used ) {
                    break; // safety break
                }
            }
            initialBorderIndex = borderIndex;
            if ( borderIndex - 1 != NSNotFound && borderIndices->array[borderIndex - 1].borderdirection == CPTContourBorderDimensionDirectionNone && !borderIndices->array[borderIndex - 1].used ) {
                    CGPathMoveToPoint(dataLinePath, &transform, (borderIndices->array[borderIndex - 1].point.x - self.originOfContext.x) * self.scaleOfContext, (borderIndices->array[borderIndex - 1].point.y - self.originOfContext.y) * self.scaleOfContext);
                initialBorderIndex = borderIndex - 1;
                borderIndices->array[borderIndex - 1].used = YES;
                containsACorner = YES;
            }
            else {
                CGPathMoveToPoint(dataLinePath, &transform, (borderIndices->array[borderIndex].point.x - self.originOfContext.x) * self.scaleOfContext, (borderIndices->array[borderIndex].point.y - self.originOfContext.y) * self.scaleOfContext);
            }
#if DEBUG
#if TARGET_OS_OSX
            NSBezierPath *bezierPath = [NSBezierPath bezierPathWithCGPath:dataLinePath];
#else
            UIBezierPath *bezierPath = [UIBezierPath bezierPathWithCGPath:dataLinePath];
#endif
#endif
            while ( YES ) {
                index = borderIndices->array[borderIndex].index;
                borderIndices->array[borderIndex].used = YES;
                collectedPlanes[countCollectedPlanes] = borderStrips->array[index].plane;
                countCollectedPlanes++;
                collectedPlanes = (NSUInteger*)realloc(collectedPlanes, (size_t)(countCollectedPlanes + 2) * sizeof(NSUInteger));
                
                searchBorderIndicesForBorderStripIndex(borderIndices, borderIndices->array[borderIndex].index, &positionsForBorderStripIndex);
                
                CGMutablePathRef workingPath;
                if ( borderStrips->array[index].plane == NSNotFound ) { // is a discontinuity border already have CGPath
                    if ( (BOOL)borderStrips->array[index].reverse ) {
#if TARGET_OS_OSX
                        NSBezierPath *discontinuityBezierPath = [NSBezierPath bezierPathWithCGPath:outerBoundaryLimitsCGPaths[borderStrips->array[index].index]];
                        discontinuityBezierPath = [discontinuityBezierPath bezierPathByReversingPath];
                        workingPath = CGPathCreateMutableCopy([discontinuityBezierPath CGPath]);
#else
                        UIBezierPath *discontinuityBezierPath = [UIBezierPath bezierPathWithCGPath:outerBoundaryLimitsCGPaths[borderStrips->array[index].index]];
                        discontinuityBezierPath = [discontinuityBezierPath bezierPathByReversingPath];
                        workingPath = CGPathCreateMutableCopy([discontinuityBezierPath CGPath]);
#endif
                        //                        [self reverseCGPath:&(outerBoundaryLimitsCGPaths[borderStrips->array[index].index])];
                    }
                    else {
                        workingPath = CGPathCreateMutableCopy(outerBoundaryLimitsCGPaths[borderStrips->array[index].index]);
                    }
                    startPoint = CGPointMake((borderStrips->array[index].startPoint.x - self.originOfContext.x) * self.scaleOfContext, (borderStrips->array[index].startPoint.y - self.originOfContext.y) * self.scaleOfContext);
                    endPoint = CGPointMake((borderStrips->array[index].endPoint.x - self.originOfContext.x) * self.scaleOfContext, (borderStrips->array[index].endPoint.y - self.originOfContext.y) * self.scaleOfContext);
                    
                }
                else {
                    pStrip = &borderStrips->array[index].pStripList->array[borderStrips->array[index].index];
                    reverse = NO;
                    if ( borderIndices->array[borderIndex].end ) {
                        reverse = YES;
                    }
                    workingPath = CGPathCreateMutable();
                    [self createDataLinePath:&workingPath fromStrip:pStrip context:context contours:contours startPoint:&startPoint endPoint:&endPoint reverseOrder:((reverse ^ (BOOL)borderStrips->array[index].reverse) ? YES : NO) closed:NO extraStripList:borderStrips->array[index].pStripList == [contours getExtraIsoCurvesListsAtIsoCurve:borderStrips->array[index].plane]];
                }
                CGPathAddLineToPoint(dataLinePath, &transform, startPoint.x, startPoint.y);
                CGPathAddPath(dataLinePath, &transform, workingPath);
#if DEBUG
    #if TARGET_OS_OSX
                [bezierPath lineToPoint:startPoint];
                NSBezierPath *bezierPath1 = [NSBezierPath bezierPathWithCGPath:workingPath];
                [bezierPath appendBezierPath:bezierPath1];
    #else
                [bezierPath addLineToPoint:startPoint];
                UIBezierPath *bezierPath1 = [UIBezierPath bezierPathWithCGPath:workingPath];
                [bezierPath appendPath:bezierPath1];
    #endif
#endif
                CGPathRelease(workingPath);
                
                borderIndex = borderIndex == positionsForBorderStripIndex[0] ? positionsForBorderStripIndex[1] : positionsForBorderStripIndex[0];
                borderIndices->array[borderIndex].used = YES;
                CGPoint pointOnBorder = CGPointMake((borderIndices->array[initialBorderIndex].point.x - self.originOfContext.x) * self.scaleOfContext, (borderIndices->array[initialBorderIndex].point.y - self.originOfContext.y) * self.scaleOfContext);
                if ( CGPointEqualToPoint(endPoint, pointOnBorder) ) {
                    CGPathAddLineToPoint(dataLinePath, &transform, pointOnBorder.x, pointOnBorder.y);
                    if ( borderIndices->array[initialBorderIndex].index == borderIndices->array[borderIndex].index ) {
                        consecutiveEdge = YES;
                    }
                    break;
                }
                
                borderIndex++;
                if ( borderIndex == (NSUInteger)borderIndices->used ) {
                    borderIndex = 0;
                }
                pointOnBorder = CGPointMake((borderIndices->array[borderIndex].point.x - self.originOfContext.x) * self.scaleOfContext, (borderIndices->array[borderIndex].point.y - self.originOfContext.y));
                if ( borderIndex == initialBorderIndex || CGPointEqualToPoint(endPoint, pointOnBorder)) {
                    CGPathAddLineToPoint(dataLinePath, &transform, (borderIndices->array[borderIndex].point.x - self.originOfContext.x) * self.scaleOfContext, (borderIndices->array[borderIndex].point.y - self.originOfContext.y) * self.scaleOfContext);
                    if ( borderIndices->array[initialBorderIndex].index == borderIndices->array[borderIndex].index ) {
                        consecutiveEdge = YES;
                    }
                    break;
                }
                
                if ( CGPointEqualToPoint(endPoint, pointOnBorder) ) {
                    if ( nextBorderIndex != NSNotFound ) {
                        borderIndex = nextBorderIndex;
                    }
                    else {
                        borderIndex++;
                        if ( borderIndex == (NSUInteger)borderIndices->used ) {
                            borderIndex = 0;
                        }
                        if ( CGPointEqualToPoint(endPoint, pointOnBorder) ) {
                            borderIndex = initialBorderIndex;
                        }
                    }
                }
                
                if ( borderIndex == initialBorderIndex && borderIndices->array[borderIndex].borderdirection == CPTContourBorderDimensionDirectionNone ) {
                    CGPathAddLineToPoint(dataLinePath, &transform, (borderIndices->array[borderIndex].point.x - self.originOfContext.x) * self.scaleOfContext, (borderIndices->array[borderIndex].point.y - self.originOfContext.y));
                    break;
                }
                
                while( borderIndices->array[borderIndex].borderdirection == CPTContourBorderDimensionDirectionNone ) {
                    CGPathAddLineToPoint(dataLinePath, &transform, (borderIndices->array[borderIndex].point.x - self.originOfContext.x) * self.scaleOfContext, (borderIndices->array[borderIndex].point.y - self.originOfContext.y) * self.scaleOfContext);
                    borderIndex++;
                    if ( borderIndex == (NSUInteger)borderIndices->used ) {
                        borderIndex = 0;
                    }
                    if ( borderIndex == initialBorderIndex ) {
                        break; // safety break
                    }
                }
                if ( borderIndex == initialBorderIndex ) {
                    CGPathAddLineToPoint(dataLinePath, &transform, (borderIndices->array[borderIndex].point.x - self.originOfContext.x) * self.scaleOfContext, (borderIndices->array[borderIndex].point.y - self.originOfContext.y) * self.scaleOfContext);
                    break;
                }
            }
            if ( countCollectedPlanes == 0 || (countCollectedPlanes == 1 && !(containsACorner || consecutiveEdge)) ) {
                CGPathRelease(dataLinePath);
                free(collectedPlanes);
                borderIndex = initialBorderIndex + 1;
                continue;
            }
            
            [self stripCGPathOfExtraMoveTos:&dataLinePath];
#if DEBUG
#if TARGET_OS_OSX
            NSBezierPath * bezierPath2 = [NSBezierPath bezierPathWithCGPath:dataLinePath];
#else
            UIBezierPath * bezierPath2 = [UIBezierPath bezierPathWithCGPath:dataLinePath];
#endif
#endif
            Centroid centroid;
            qsort(centroids.array, centroids.used, sizeof(Centroid), compareCentroidsByXCoordinate);
            centroid.centre =  GetCenterPointOfCGPath(dataLinePath);//CGPointMake(averageX, averageY);
            centroid.noVertices = GetNoVerticesCGPath(dataLinePath);// (NSUInteger)(floor(dataArray[2]));
            centroid.boundingBox = CGPathGetBoundingBox(dataLinePath);
            Centroid *original;
            if( (original = (Centroid*)bsearch(&centroid, centroids.array, centroids.used, sizeof(Centroid), compareCentroids)) != NULL && toleranceCGRectEqualToRect(original->boundingBox, centroid.boundingBox)) {
                free(collectedPlanes);
                CGPathRelease(dataLinePath);
            }
            else {
                appendCentroids(&centroids, centroid);
                
                CGContextSaveGState(context);
                CGContextAddPath(context, dataLinePath);
                
                CGMutablePathRef *closedDataLinePaths = (CGMutablePathRef *)calloc(1, sizeof(CGMutablePathRef));
                NSUInteger *closedPlanes = (NSUInteger*)calloc(1, sizeof(NSUInteger));
                NSUInteger noFoundClosedDataLinePaths = [self findClosedDataLinePaths:&closedDataLinePaths foundClosedPlanes:&closedPlanes OuterCGPath:&dataLinePath context:context contours:contours leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge useExtraLineStripList:YES checkPointOnPath:NO];
                
                CGFloat areaOfDataLinePath = 0;
                if ( noFoundClosedDataLinePaths > 0 ) {
                    areaOfDataLinePath = fabs(cgpathArea(dataLinePath));
                    for( NSUInteger l = 0; l < noFoundClosedDataLinePaths; l++ ) {
                        if ( CGPathContainsPoint(dataLinePath, NULL, CGPathGetCurrentPoint(closedDataLinePaths[l]), YES) ) {
                            CGContextAddPath(context, closedDataLinePaths[l]);
    #if DEBUG
    #if TARGET_OS_OSX
                            NSBezierPath * bezierPath6 = [NSBezierPath bezierPathWithCGPath:closedDataLinePaths[l]];
                            [bezierPath2 appendBezierPath:bezierPath6];
    #else
                            UIBezierPath * bezierPath6 = [UIBezierPath bezierPathWithCGPath:closedDataLinePaths[l]];
                            [bezierPath2 appendPath:bezierPath6];
    #endif
    #endif
                            // if area of closed contour is tiny compare to main contour don't use it for fill colour
                            if ( fabs(cgpathArea(closedDataLinePaths[l])) > 0.1 * areaOfDataLinePath ) {
                                collectedPlanes[countCollectedPlanes] = closedPlanes[l];
                                countCollectedPlanes++;
                                collectedPlanes = (NSUInteger*)realloc(collectedPlanes, (size_t)(countCollectedPlanes + 2) * sizeof(NSUInteger));
                            }
                        }
                        CGPathRelease(closedDataLinePaths[l]);
                    }
                }
                free(closedPlanes);
                free(closedDataLinePaths);
                
                // rid duplicates collectedPlanes
                for ( NSUInteger l = 0; l < countCollectedPlanes; l++ ) {
                    for ( NSUInteger m = l + 1; m < countCollectedPlanes; m++ ) {
                        if ( collectedPlanes[l] == collectedPlanes[m] ) {
                            countCollectedPlanes--;
                            for ( NSUInteger n = m; n < countCollectedPlanes; n++) {
                                collectedPlanes[n] = collectedPlanes[n + 1];
                            }
                            m--;
                        }
                    }
                }
                
                // Fill colours will be made from combining or not the elevation levels of contours surrunding a fill region
                // the elevation levels colours are stored in the isoCurvesLineStyles array.
                // actualPlane is the real plane index in the isoCurvesIndices array
                if ( countCollectedPlanes == 1 ) {
                    theFill = [self calculateFill:dataLinePath combinedPath:NULL collectedPlanes:collectedPlanes noCollectedPlanes:countCollectedPlanes];
                }
                else {
                    //                theFill = [self calculateFill:dataLinePath combinedPath:bezierPath.CGPath collectedPlanes:collectedPlanes];
                    theFill = [self findFillFromBoundingPlanes:collectedPlanes noCollectedPlanes:countCollectedPlanes];
                }
                
                if ( theFill && [theFill isKindOfClass:[CPTFill class]] ) {
                    CGContextSetFillColorWithColor(context, theFill.cgColor);
                }
                free(collectedPlanes);
                
                //            if ( outerBoundaryLimitsCGPaths != NULL ) {
                //#if DEBUG
                //    #if TARGET_OS_OSX
                //                NSBezierPath * bezierPath3 = [NSBezierPath bezierPathWithCGPath:dataLinePath];
                //    #else
                //                UIBezierPath * bezierPath3 = [UIBezierPath bezierPathWithCGPath:dataLinePath];
                //    #endif
                //#endif
                //                for( NSUInteger k = 0; k < noOuterBoundaryLimitsCGPaths; k++ ) {
                //                    if ( !CGPathIsEmpty(outerBoundaryLimitsCGPaths[k]) ) {
                //#if DEBUG
                //    #if TARGET_OS_OSX
                //                            [bezierPath3 appendBezierPath:[NSBezierPath bezierPathWithCGPath:outerBoundaryLimitsCGPaths[k]]];
                //    #else
                //                             [bezierPath3 appendPath:[UIBezierPath bezierPathWithCGPath:outerBoundaryLimitsCGPaths[k]]];
                //    #endif
                //#endif
                //                        CGPoint last = CGPathGetCurrentPoint(outerBoundaryLimitsCGPaths[k]);
                //                        if ( CGPathContainsPoint(dataLinePath, &transform, last, YES) || CGPathIntersectsPathWithOther(outerBoundaryLimitsCGPaths[k], dataLinePath) ) {
                //                            CGContextAddPath(context, outerBoundaryLimitsCGPaths[k]);
                //                            theFill = nil;
                //                        }
                //                    }
                //                }
                //            }
                CGPathRelease(dataLinePath);
                
                CGContextSetFillColorWithColor(context, theFill.cgColor);
                CGContextEOFillPath(context);
                
#if DEBUG
                CGImageRef imgRef = CGBitmapContextCreateImage(context);
#if TARGET_OS_OSX
                NSImage* img = [[NSImage alloc] initWithCGImage:imgRef size: NSZeroSize];
                
                NSImage* __unused flippedImage = [NSImage imageWithSize:img.size flipped:YES drawingHandler:^BOOL(NSRect dstRect) {
                    [img drawInRect:dstRect];
                    return YES;
                }];
#else
                UIImage* img = [UIImage imageWithCGImage:imgRef];
                CGSize size = img.size;
                UIGraphicsBeginImageContext(CGSizeMake(size.height, size.width));
                [[UIImage imageWithCGImage:imgRef scale:1.0 orientation:UIImageOrientationDownMirrored] drawInRect:CGRectMake(0, 0, size.height, size.width)];
                UIImage* __unused flippedImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
#endif
                CGImageRelease(imgRef);
#endif
                CGContextRestoreGState(context);
            }
            borderIndex = initialBorderIndex;
            while ( borderIndices->array[borderIndex].borderdirection == CPTContourBorderDimensionDirectionNone ) {
                borderIndex++;
                if ( borderIndex >= borderIndices->used ) {
                    break; // safety break
                }
            }
            
            if ( CGPointEqualToPoint(borderIndices->array[borderIndex].point, borderIndices->array[borderIndex + 1 == borderIndices->used ? 0 : borderIndex + 1].point) ) {
                searchBorderIndicesForBorderStripIndex(borderIndices, borderIndices->array[borderIndex + 1].index, &positionsForBorderStripIndex);
                nextBorderIndex = (borderIndex + 1) == positionsForBorderStripIndex[0] ? positionsForBorderStripIndex[1] : positionsForBorderStripIndex[0];
                if ( nextBorderIndex == (NSUInteger)borderIndices->used ) {
                    nextBorderIndex = 0;
                }
                borderIndex+= 2;
            }
            else {
                if ( nextBorderIndex == NSNotFound ) {
                    borderIndex++;
                }
                nextBorderIndex = NSNotFound;
            }
        }
        free(positionsForBorderStripIndex);
        freeCentroids(&centroids);
}

#pragma mark -
#pragma mark Searches and Tests

-(NSUInteger) findLargestOverlappedPath:(nonnull CGContextRef)context contours:(CPTContours *)contours overlappedPaths:(CGMutablePathRef*)overlappedPaths noOverlappedPaths:(NSUInteger)noOverlappedPaths collectedPlanes:(NSUInteger*)collectedPlanes combinedOverlapDataLinePaths:(CGMutablePathRef**)combinedOverlapDataLinePaths  leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge ascendingOrder:(BOOL)ascendingOrder useExtraLineStripList:(BOOL)useExtraLineStripList {
    CGFloat maxArea = fabs(cgpathArea(overlappedPaths[0])), checkArea;
    NSUInteger maxIndexRef = 0;
#if DEBUG
    #if TARGET_OS_OSX
    NSBezierPath *bezierPath = [NSBezierPath  bezierPathWithCGPath:overlappedPaths[0]];
    #else
    UIBezierPath *bezierPath = [UIBezierPath  bezierPathWithCGPath:overlappedPaths[0]];
    #endif
#endif
    *combinedOverlapDataLinePaths = (CGMutablePathRef*)calloc((size_t)noOverlappedPaths, sizeof(CGMutablePathRef));
    for ( NSUInteger i = 0; i < noOverlappedPaths; i++ ) {
        if ( i > 0 ) {
            if ( maxArea < (checkArea = fabs(cgpathArea(overlappedPaths[i]))) ) {
                maxArea = checkArea;
                maxIndexRef = i;
            }
#if DEBUG
#if TARGET_OS_OSX
            [bezierPath appendBezierPath:[NSBezierPath bezierPathWithCGPath:overlappedPaths[i]]];
#else
            [bezierPath appendPath:[UIBezierPath bezierPathWithCGPath:overlappedPaths[i]]];
#endif
#endif
        }
//        CGMutablePathRef combinedDataLinePath = CGPathCreateMutableCopy(overlappedPaths[i]);
//        CGMutablePathRef *combinedDataLinePaths = (CGMutablePathRef*)calloc(1, sizeof(CGMutablePathRef));
//        // now find any paths that are within this context
//        NSUInteger noCombinedDataLinePaths = 0;
//        NSUInteger plane = [self findIsoCurveIndicesIndex:collectedPlanes[0]];
//        if ( (noCombinedDataLinePaths = [self findClosedDataLinePaths:&combinedDataLinePaths noFoundClosedDataLinePaths:noCombinedDataLinePaths OuterCGPath:&combinedDataLinePath context:context contours:contours plane:&plane leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge ascendingOrder:ascendingOrder useExtraLineStripList:useExtraLineStripList fromCurrentPlane:YES checkPointOnPath:YES]) > 0 ) {
////            collectedPlanes = (NSUInteger*)realloc(collectedPlanes, sizeof(NSUInteger) * (size_t)(countCollectedPlanes + 1));
////            collectedPlanes[countCollectedPlanes] = plane;
////            countCollectedPlanes++;
//        }
//        plane = [self findIsoCurveIndicesIndex:collectedPlanes[0]];
//        NSUInteger origNoCombinedDataLinePaths = noCombinedDataLinePaths;
//        if ( (noCombinedDataLinePaths = [self findClosedDataLinePaths:&combinedDataLinePaths noFoundClosedDataLinePaths:noCombinedDataLinePaths OuterCGPath:&combinedDataLinePath context:context contours:contours plane:&plane leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge ascendingOrder:!ascendingOrder useExtraLineStripList:useExtraLineStripList fromCurrentPlane:YES checkPointOnPath:YES]) > origNoCombinedDataLinePaths ) {
////            collectedPlanes = (NSUInteger*)realloc(collectedPlanes, sizeof(NSUInteger) * (size_t)(countCollectedPlanes + 1));
////            collectedPlanes[countCollectedPlanes] = plane;
////            countCollectedPlanes++;
//        }
//
//        for( NSUInteger j = 0; j < noCombinedDataLinePaths; j++ ) {
//            if( !self.extrapolateToLimits && !self.functionPlot ) {
//                CGPathCloseSubpath(combinedDataLinePaths[j]);
//            }
//            if ( CGPathEqualToPath(combinedDataLinePaths[j], overlappedPaths[i]) ) {
//                continue;
//            }
//#if DEBUG
//#if TARGET_OS_OSX
//            [bezierPath appendBezierPath:[NSBezierPath bezierPathWithCGPath:combinedDataLinePaths[j]]];
//#else
//            [bezierPath appendPath:[UIBezierPath bezierPathWithCGPath:combinedDataLinePaths[j]]];
//#endif
//#endif
//            CGPathAddPath(*(*combinedOverlapDataLinePaths + i), NULL, combinedDataLinePaths[j]);
//            CGPathRelease(combinedDataLinePaths[j]);
//        }
//        free(combinedDataLinePaths);
    }
    return maxIndexRef;
}

-(CPTFill*)calculateFill:(CGPathRef)refDataLinePath combinedPath:(CGPathRef)combinedPath collectedPlanes:(NSUInteger*)collectedPlanes noCollectedPlanes:(NSUInteger)noCollectedPlanes {
    CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
    
#if DEBUG
    #if TARGET_OS_OSX
    NSBezierPath *bezierPath = [NSBezierPath  bezierPathWithCGPath:refDataLinePath];
    #else
    UIBezierPath *bezierPath = [UIBezierPath  bezierPathWithCGPath:refDataLinePath];
    #endif
#endif
    CGPoint ptInside;
    if ( combinedPath == NULL || CGPathIsEmpty(combinedPath) ) {
        ptInside = pointInCGPath(refDataLinePath, refDataLinePath);
    }
    else {
        ptInside = pointInCGPath(refDataLinePath, combinedPath);
#if DEBUG
    #if TARGET_OS_OSX
        [bezierPath appendBezierPath:[NSBezierPath bezierPathWithCGPath:combinedPath]];
    #else
        [bezierPath appendPath:[UIBezierPath bezierPathWithCGPath:combinedPath]];
    #endif
#endif
    }
    
    CGFloat averageX = (ptInside.x / self.scaleOfContext + self.originOfContext.x) / self.scaleX + thePlotSpace.xRange.locationDouble;
    CGFloat averageY = (ptInside.y / self.scaleOfContext + self.originOfContext.y) / self.scaleY + thePlotSpace.yRange.locationDouble;
    double fieldValue = self.dataSourceBlock((double)averageX, (double)averageY);
    //    int value = (int)(fieldValue * 100);
    //    fieldValue = (double)value / 100;
    if ( isnan(fieldValue) ) {
        CPTColor *color = [CPTColor clearColor];
        return [CPTFill fillWithColor:color];
    }
    
    id nilObject                    = [CPTPlot nilData];
    CPTFill *theFill = nil;
    CPTContourFill *filling = [[CPTContourFill alloc] init];
    CGFloat r1, g1, b1, a1;
    BOOL strongAlpha = NO;
    if ( noCollectedPlanes == 1 ) {
        strongAlpha = YES;
        NSUInteger fillIndex1, fillIndex2 = NSNotFound;
        if ( fieldValue < [[self.isoCurvesValues firstObject] doubleValue] ) {
            fillIndex1 = 0;
            filling.firstValue = [self.isoCurvesValues objectAtIndex:fillIndex1];
            filling.secondValue = nil;
        }
        else if ( fieldValue > [[self.isoCurvesValues lastObject] doubleValue] ) {
            fillIndex1 = self.isoCurvesValues.count - 1;
            filling.firstValue = nil;
            filling.secondValue = [self.isoCurvesValues objectAtIndex:self.isoCurvesIndices.count - 1];
        }
        else {
            fillIndex1 = 0;
            for ( NSUInteger i = 1; i < self.isoCurvesValues.count; i++ ) {
                if ( fieldValue > [[self.isoCurvesValues objectAtIndex:i - 1] doubleValue] && fieldValue <= [[self.isoCurvesValues objectAtIndex:i]  doubleValue] ) {
                    fillIndex1 = i;
                    break;
                }
            }
            filling.firstValue = [self.isoCurvesValues objectAtIndex:fillIndex1];
            filling.secondValue = nil;
        }
        if ( [self.isoCurvesFills firstObject] == nilObject ) {
            CPTColor *colour;
            if ( fillIndex2 == NSNotFound ) {
                CPTLineStyle *lineStyle = [self.isoCurvesLineStyles objectAtIndex: fillIndex1];
                colour = [lineStyle lineColor];
#if TARGET_OS_OSX
                [[colour nsColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#else
                [[colour uiColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#endif
                if ( strongAlpha ) {
                    colour = [colour colorWithAlphaComponent:a1 * 0.75];
                }
                else {
                    colour = [colour colorWithAlphaComponent:a1 * 0.5];
                }
            }
//            else {
//                CPTLineStyle *lineStyle1 = [self.isoCurvesLineStyles objectAtIndex: fillIndex1];
//                CPTLineStyle *lineStyle2 = [self.isoCurvesLineStyles objectAtIndex: fillIndex2];
//                UIColor *colour1 = [[lineStyle1 lineColor] uiColor];
//                UIColor *colour2 = [[lineStyle2 lineColor] uiColor];
//                CGFloat r2, g2, b2, a2;
//                [colour1 getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
//                [colour2 getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
//                CGFloat red     = (r2 + r1) / 2;
//                CGFloat green   = (g2 + g1) / 2;
//                CGFloat blue    = (b2 + b1) / 2;
//                CGFloat alpha   = (a2 + a1) / 4;
//                colour = [CPTColor colorWithComponentRed:red green:green blue:blue alpha:alpha];
//            }
            theFill = [CPTFill fillWithColor:colour];
        }
        else {
            theFill = [self.isoCurvesFills objectAtIndex:fillIndex1];
        }
        filling.fill = theFill;
    }
    else if ( fieldValue < [[self.isoCurvesValues firstObject] doubleValue] ) {
        if ( [self.isoCurvesFills firstObject] == nilObject ) {
            CPTLineStyle *lineStyle = [self.isoCurvesLineStyles firstObject];
            CPTColor *colour = [lineStyle lineColor];
#if TARGET_OS_OSX
            [[colour nsColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#else
            [[colour uiColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#endif
            colour = [colour colorWithAlphaComponent:a1 * 0.75];
            theFill = [CPTFill fillWithColor:colour];
        }
        else {
            theFill = [self.isoCurvesFills objectAtIndex:0];
        }
        filling.fill = theFill;
        filling.firstValue = [self.isoCurvesValues firstObject];
        filling.secondValue = nil;
    }
    else if ( fieldValue > [[self.isoCurvesValues lastObject] doubleValue] ) {
        if ( [self.isoCurvesFills firstObject] == nilObject ) {
            CPTLineStyle *lineStyle = [self.isoCurvesLineStyles lastObject];
            CPTColor *colour = [lineStyle lineColor];
#if TARGET_OS_OSX
            [[colour nsColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#else
            [[colour uiColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#endif
            colour = [colour colorWithAlphaComponent:a1 * 0.75];
            theFill = [CPTFill fillWithColor:colour];
        }
        else {
            theFill = [self.isoCurvesFills objectAtIndex:self.isoCurvesFills.count - 1];
        }
        filling.fill = theFill;
        filling.firstValue = nil;
        filling.secondValue = [self.isoCurvesValues lastObject];
    }
    else {
        NSUInteger fillIndex = 0;
        for ( NSUInteger i = 1; i < self.isoCurvesValues.count; i++ ) {
            if ( fieldValue > [[self.isoCurvesValues objectAtIndex:i - 1] doubleValue] && fieldValue <= [[self.isoCurvesValues objectAtIndex:i] doubleValue] ) {
                fillIndex = i;
                break;
            }
        }
        if ( [self.isoCurvesFills firstObject] == nilObject ) {
            CPTLineStyle *lineStyle1 = [self.isoCurvesLineStyles objectAtIndex: fillIndex - 1];
            CPTLineStyle *lineStyle2 = [self.isoCurvesLineStyles objectAtIndex: fillIndex];
#if TARGET_OS_OSX
            NSColor *colour1 = [[lineStyle1 lineColor] nsColor];
            NSColor *colour2 = [[lineStyle2 lineColor] nsColor];
#else
            UIColor *colour1 = [[lineStyle1 lineColor] uiColor];
            UIColor *colour2 = [[lineStyle2 lineColor] uiColor];
#endif
            
            CGFloat r2, g2, b2, a2;
            [colour1 getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
            [colour2 getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
//            CGFloat alpha2 = MIN( 1.0, MAX( 0.0, a2 ) );
//            CGFloat beta = 1.0 - alpha2;
//            CGFloat red     = r1 * beta + r2 * alpha2;
//            CGFloat green   = g1 * beta + g2 * alpha2;
//            CGFloat blue    = b1 * beta + b2 * alpha2;
//            CGFloat alpha   = a1 * beta + a2 * alpha2;
//            CGFloat alpha1 = MIN( 1.0, MAX( 0.0, a1 ) );
//            CGFloat beta = 1.0 - alpha1;
//            CGFloat red     = r2 * beta + r1 * alpha1;
//            CGFloat green   = g2 * beta + g1 * alpha1;
//            CGFloat blue    = b2 * beta + b1 * alpha1;
//            CGFloat alpha   = a2 * beta + a1 * alpha1;
            
            CGFloat red     = (r2 + r1) / 2;
            CGFloat green   = (g2 + g1) / 2;
            CGFloat blue    = (b2 + b1) / 2;
            CGFloat alpha   = (a2 + a1) / 4;
            CPTColor *colour = [CPTColor colorWithComponentRed:red green:green blue:blue alpha:alpha];
            theFill = [CPTFill fillWithColor:colour];
        }
        else {
            theFill = [self.isoCurvesFills objectAtIndex:fillIndex];
        }
        filling.fill = theFill;
        filling.firstValue = [self.isoCurvesValues objectAtIndex:fillIndex - 1];
        filling.secondValue = [self.isoCurvesValues objectAtIndex:fillIndex];
    }
    const CGFloat *components = CGColorGetComponents(filling.fill.cgColor);
    NSUInteger noComponents = CGColorGetNumberOfComponents(filling.fill.cgColor);
    if ( [self.isoCurvesFillings indexOfObjectPassingTest:^BOOL(CPTContourFill * _Nonnull obj, NSUInteger __unused idx, BOOL * _Nonnull __unused stop) {
        const CGFloat *componentsObj = CGColorGetComponents(obj.fill.cgColor);
        NSUInteger noComponentsObj = CGColorGetNumberOfComponents(obj.fill.cgColor);
        if ( noComponents == 2 && noComponentsObj == 2 ) {
            return componentsObj[0] == components[0] && componentsObj[1] == components[1] && (([obj.firstValue doubleValue] ==  [filling.firstValue doubleValue] && [obj.secondValue doubleValue] == [filling.secondValue doubleValue]) || ([obj.firstValue doubleValue] == [filling.secondValue doubleValue] && [obj.secondValue doubleValue] == [filling.firstValue doubleValue]));
        }
        else if ( noComponents == 2 && noComponentsObj == 4 ) {
            return componentsObj[0] == components[0] && componentsObj[1] == components[0] && componentsObj[2] == components[0] && componentsObj[3] == components[1] && (([obj.firstValue doubleValue] == [filling.firstValue doubleValue] && [obj.secondValue doubleValue] == [filling.secondValue doubleValue]) || ([obj.firstValue doubleValue] == [filling.secondValue doubleValue] && [obj.secondValue doubleValue] ==  [filling.firstValue doubleValue]));
        }
        else if ( noComponents == 4 && noComponentsObj == 2 ) {
            return componentsObj[0] == components[0] && componentsObj[0] == components[1] && componentsObj[0] == components[2] && componentsObj[1] == components[3] && (([obj.firstValue doubleValue] == [filling.firstValue doubleValue] && [obj.secondValue doubleValue] == [filling.secondValue doubleValue]) || ([obj.firstValue doubleValue] == [filling.secondValue doubleValue] && [obj.secondValue doubleValue] == [filling.firstValue doubleValue]));
        }
        else {
            return componentsObj[0] == components[0] && componentsObj[1] == components[1] && componentsObj[2] == components[2] && componentsObj[3] == components[3] && (([obj.firstValue doubleValue] == [filling.firstValue doubleValue] && [obj.secondValue doubleValue] == [filling.secondValue doubleValue]) || ([obj.firstValue doubleValue] == [filling.secondValue doubleValue] && [obj.secondValue doubleValue] == [filling.firstValue doubleValue]));
        }
    } ] == NSNotFound ) {
        [self.isoCurvesFillings addObject:filling];
    }
           
    return theFill;
}

-(CPTFill*)findFillFromBoundingPlanes:(NSUInteger*)collectedPlanes noCollectedPlanes:(NSUInteger)noCollectedPlanes {
    id nilObject                    = [CPTPlot nilData];
    CPTFill *theFill = nil;
    CPTContourFill *filling = [[CPTContourFill alloc] init];
    NSUInteger fillIndex1 = collectedPlanes[0], fillIndex2 = NSNotFound;
    if ( fillIndex1 == 0 && [[self.isoCurvesValues objectAtIndex:0] doubleValue] == 10.0 * [[self.isoCurvesValues objectAtIndex:1] doubleValue] ) {
        CPTColor *color = [CPTColor clearColor];
        return [CPTFill fillWithColor:color];
    }
    CGFloat r1, g1, b1, a1;
    
    if ( fillIndex1 == NSNotFound && noCollectedPlanes > 1 ) {
        fillIndex1 = collectedPlanes[1];
        noCollectedPlanes = 1;
    }
    else if ( collectedPlanes[1] == NSNotFound && noCollectedPlanes > 1 ) {
        fillIndex1 = collectedPlanes[0];
        noCollectedPlanes = 1;
    }
    
    if ( noCollectedPlanes == 1 ) {
        if ( [self.isoCurvesFills firstObject] == nilObject ) {
            CPTLineStyle *lineStyle1 = [self.isoCurvesLineStyles objectAtIndex: fillIndex1];
            CPTColor *colour1 = lineStyle1.lineColor;
#if TARGET_OS_OSX
            [[colour1 nsColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#else
            [[colour1 uiColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#endif
            [colour1 colorWithAlphaComponent:a1 / 2];
            theFill = [CPTFill fillWithColor:colour1];
        }
        else {
            theFill = [self.isoCurvesFills objectAtIndex:fillIndex1];
        }
        filling.fill = theFill;
        filling.firstValue = [self.isoCurvesValues firstObject];
        filling.secondValue = nil;
    }
    else {
        fillIndex2 = collectedPlanes[1];
        if ( [self.isoCurvesFills firstObject] == nilObject ) {
            CPTLineStyle *lineStyle1 = [self.isoCurvesLineStyles objectAtIndex: fillIndex1];
            CPTLineStyle *lineStyle2 = [self.isoCurvesLineStyles objectAtIndex: fillIndex2];
#if TARGET_OS_OSX
            NSColor *colour1 = [[lineStyle1 lineColor] nsColor];
            NSColor *colour2 = [[lineStyle2 lineColor] nsColor];
#else
            UIColor *colour1 = [[lineStyle1 lineColor] uiColor];
            UIColor *colour2 = [[lineStyle2 lineColor] uiColor];
#endif
            
            CGFloat r2, g2, b2, a2;
            [colour1 getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
            [colour2 getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
            CGFloat red     = (r2 + r1) / 2;
            CGFloat green   = (g2 + g1) / 2;
            CGFloat blue    = (b2 + b1) / 2;
            CGFloat alpha   = (a2 + a1) / 4;
            CPTColor *colour = [CPTColor colorWithComponentRed:red green:green blue:blue alpha:alpha];
            theFill = [CPTFill fillWithColor:colour];
        }
        else {
            theFill = [self.isoCurvesFills objectAtIndex:fillIndex1];
        }
        filling.fill = theFill;
        filling.firstValue = [self.isoCurvesValues objectAtIndex:fillIndex1];
        filling.secondValue = [self.isoCurvesValues objectAtIndex:fillIndex2];
    }
    const CGFloat *components = CGColorGetComponents(filling.fill.cgColor);
    NSUInteger noComponents = CGColorGetNumberOfComponents(filling.fill.cgColor);
    if ( [self.isoCurvesFillings indexOfObjectPassingTest:^BOOL(CPTContourFill * _Nonnull obj, NSUInteger __unused idx, BOOL * _Nonnull __unused stop) {
        const CGFloat *componentsObj = CGColorGetComponents(obj.fill.cgColor);
        NSUInteger noComponentsObj = CGColorGetNumberOfComponents(obj.fill.cgColor);
        if ( noComponents == 2 && noComponentsObj == 2 ) {
            return componentsObj[0] == components[0] && componentsObj[1] == components[1] && (([obj.firstValue doubleValue] ==  [filling.firstValue doubleValue] && [obj.secondValue doubleValue] == [filling.secondValue doubleValue]) || ([obj.firstValue doubleValue] == [filling.secondValue doubleValue] && [obj.secondValue doubleValue] == [filling.firstValue doubleValue]));
        }
        else if ( noComponents == 2 && noComponentsObj == 4 ) {
            return componentsObj[0] == components[0] && componentsObj[1] == components[0] && componentsObj[2] == components[0] && componentsObj[3] == components[1] && (([obj.firstValue doubleValue] == [filling.firstValue doubleValue] && [obj.secondValue doubleValue] == [filling.secondValue doubleValue]) || ([obj.firstValue doubleValue] == [filling.secondValue doubleValue] && [obj.secondValue doubleValue] ==  [filling.firstValue doubleValue]));
        }
        else if ( noComponents == 4 && noComponentsObj == 2 ) {
            return componentsObj[0] == components[0] && componentsObj[0] == components[1] && componentsObj[0] == components[2] && componentsObj[1] == components[3] && (([obj.firstValue doubleValue] == [filling.firstValue doubleValue] && [obj.secondValue doubleValue] == [filling.secondValue doubleValue]) || ([obj.firstValue doubleValue] == [filling.secondValue doubleValue] && [obj.secondValue doubleValue] == [filling.firstValue doubleValue]));
        }
        else {
            return componentsObj[0] == components[0] && componentsObj[1] == components[1] && componentsObj[2] == components[2] && componentsObj[3] == components[3] && (([obj.firstValue doubleValue] == [filling.firstValue doubleValue] && [obj.secondValue doubleValue] == [filling.secondValue doubleValue]) || ([obj.firstValue doubleValue] == [filling.secondValue doubleValue] && [obj.secondValue doubleValue] == [filling.firstValue doubleValue]));
        }
    } ] == NSNotFound ) {
        [self.isoCurvesFillings addObject:filling];
    }
    
    return theFill;
}

- (NSUInteger)findFillIndex:(NSUInteger)actualPlane {
    return [self.isoCurvesIndices indexOfObjectPassingTest:^BOOL(NSNumber * _Nonnull obj, NSUInteger __unused  idx, BOOL * _Nonnull __unused stop) {
        return [obj unsignedIntegerValue] == actualPlane;
    }];
}

- (NSUInteger)findIsoCurveIndicesIndex:(NSUInteger)actualPlane {
        return [self.isoCurvesIndices indexOfObjectPassingTest:^BOOL(NSNumber * _Nonnull obj, NSUInteger __unused  idx, BOOL * _Nonnull __unused  stop) {
        return [obj unsignedIntegerValue] == actualPlane;
    }];
}

-(NSUInteger)findNextBorderStripFromBorderStrips:(Strips*)borderStrips direction:(CPTContourBorderDimensionDirection)direction point:(CGPoint)point startIndex:(NSUInteger)startIndex leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    CGPoint prevPoint, nextPoint;
    NSUInteger i = startIndex;
    for (NSUInteger j = 0; j < borderStrips->used; j++ ) {
        if( borderStrips->array[i].endBorderdirection == direction || borderStrips->array[i].startBorderdirection == direction ) {
            prevPoint = borderStrips->array[i].endPoint;
            nextPoint = borderStrips->array[i + 1 > borderStrips->used - 1 ? 0 : i + 1].startPoint;
            if ( direction == CPTContourBorderDimensionDirectionXForward && point.y == bottomEdge && point.x >= prevPoint.x && point.x <= nextPoint.x && nextPoint.y == bottomEdge ) {
                break;
            }
            else if( direction == CPTContourBorderDimensionDirectionYForward && point.x == rightEdge && point.y >= prevPoint.y && point.y <= nextPoint.y && nextPoint.x == rightEdge ) {
                break;
            }
            else if ( direction == CPTContourBorderDimensionDirectionXBackward && point.y == topEdge && point.x <= prevPoint.x && point.x >= nextPoint.x && nextPoint.y == topEdge ) {
                break;
            }
            else if ( direction == CPTContourBorderDimensionDirectionYBackward && point.x == leftEdge && point.y <= prevPoint.y && point.y >= nextPoint.y && nextPoint.x == leftEdge ) {
                break;
            }
        }
        i++;
        if ( i > borderStrips->used ) {
            i = 0;
        }
    }
    if ( i >= borderStrips->used) {
        return NSNotFound;
    }
    return i;
}

-(void) collectStripsForBorders:(Strips*)edgeBorderStrips usedExtraLineStripLists:(BOOL*)usedExtraLineStripLists context:(nonnull CGContextRef)context contours:(CPTContours *)contours leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    /* since contours are grouped by their isocurve value within a defined rectangle, one needs to search for the inner
     contour for the current contour in order to enable filling.
     Start in bottom left hand corner and move around perimeter of rectangle till getting back to bottm left */
    Strips edgeStrips[4];
    for ( NSUInteger i = 0; i < 4; i++ ) {
        initStrips(&edgeStrips[i], 4);
    }
    
    // will have to iterate through descending / ascending iso curves to see if any curves inside outer curve, as inner curve may not have an iso curve inside outer
    // move along bottom edge, then up right edge, back along top edge and finally back down left edge to start
    // looking of boundary intersection point in each isoCurve plane group of points and storing the index for later
    //CGPoint previousEndPoint = CGPointMake(-0.0, -0.0);
    NSUInteger actualPlane;
    for ( NSUInteger iPlane = 0; iPlane < self.isoCurvesIndices.count; iPlane++ ) {
        // actualPlane is the real plane index in the isoCurvesIndices array
        actualPlane = [[self.isoCurvesIndices objectAtIndex:iPlane] unsignedIntegerValue];
        usedExtraLineStripLists[actualPlane] = NO;
        if( self.functionPlot ) {
            Strips planeBorderStrips;
            initStrips(&planeBorderStrips, 16);
            if ( [self checkForIntersectingContoursAndCreateNewBorderContours:context contours:contours plane:actualPlane /*borderStrip:&planeBorderStrips*/] > 0 /*|| [self checkForMirroredContoursAndCreateNewBorderContours:context contours:contours plane:actualPlane] > 0*/ ) {
                [self searchPlaneBorderIsoCurves:context contours:contours Plane:actualPlane BorderStrips:edgeStrips useExtraLineStripList:YES leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                for ( NSUInteger i = 0; i < 4; i++ ) {
                    for( NSUInteger j = 0; j < edgeStrips[i].used; j++ ) {
                        appendStrips(&edgeBorderStrips[i], edgeStrips[i].array[j]);
                    }
                    clearStrips(&edgeStrips[i]);
                }
                usedExtraLineStripLists[actualPlane] = YES;
            }
            else { // if no extra LineStripList detected
                [self searchPlaneBorderIsoCurves:context contours:contours Plane:actualPlane BorderStrips:edgeStrips useExtraLineStripList:NO leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                for ( NSUInteger i = 0; i < 4; i++ ) {  // moving along border anticlockwise from btm left corner
                    for( NSUInteger j = 0; j < edgeStrips[i].used; j++ ) {
                        appendStrips(&edgeBorderStrips[i], edgeStrips[i].array[j]);
                    }
                    clearStrips(&edgeStrips[i]);
                }
            }
            freeStrips(&planeBorderStrips);
        }
        else {
            [self searchPlaneBorderIsoCurves:context contours:contours Plane:actualPlane BorderStrips:edgeStrips useExtraLineStripList:NO leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
            for ( NSUInteger i = 0; i < 4; i++ ) {  // moving along border anticlockwise from btm left corner
                for( NSUInteger j = 0; j < edgeStrips[i].used; j++ ) {
                    appendStrips(&edgeBorderStrips[i], edgeStrips[i].array[j]);
                }
                clearStrips(&edgeStrips[i]);
            }
        }
    }
    for ( NSUInteger i = 0; i < 4; i++ ) {
        freeStrips(&edgeStrips[i]);
    }
}


-(void) joinBorderStripsToCreateClosedStrips:(Strips*)borderStrips borderIndices:(BorderIndices*)borderIndices usedExtraLineStripLists:(BOOL*)usedExtraLineStripLists context:(CGContextRef)context contours:(CPTContours *)contours leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    BOOL reverse;
    LineStrip *pStrip;
    NSUInteger borderIndex = 0, actualPlane, index;
    for( NSUInteger plane = 0; plane < self.isoCurvesIndices.count; plane++ ) {
        actualPlane = [[self.isoCurvesIndices objectAtIndex:plane] unsignedIntegerValue];
        NSUInteger* indices = (NSUInteger*)calloc(1, sizeof(NSUInteger));
        NSUInteger noIndices = searchForStripIndicesForPlane(borderStrips, actualPlane, &indices);
        if ( noIndices > 0 ) {
            Strips planeStrips;
            initStrips(&planeStrips, noIndices);
            BorderIndices planeBorderIndices;
            initBorderIndices(&planeBorderIndices, (size_t)noIndices * 2);
            CGPoint *vertices = (CGPoint*)calloc((size_t)noIndices * 2, sizeof(CGPoint));
            for ( NSUInteger i = 0; i < noIndices; i++ ) {
                borderStrips->array[indices[i]].usedInExtra = 1;
                appendStrips(&planeStrips, borderStrips->array[indices[i]]);
                BorderIndex element1 = initBorderIndex();
                element1.point = borderStrips->array[indices[i]].startPoint;
                element1.index = indices[i];
                appendBorderIndices(&planeBorderIndices, element1);
                BorderIndex element2 = initBorderIndex();
                element2.point =  borderStrips->array[indices[i]].endPoint;
                element2.index = indices[i];
                appendBorderIndices(&planeBorderIndices, element2);
                vertices[i * 2] = borderStrips->array[indices[i]].startPoint;
                vertices[i * 2 + 1] = borderStrips->array[indices[i]].endPoint;
            }
            CGPoint centre = [self findCentroidOfShape:vertices noPoints:noIndices * 2];
            for( NSUInteger i = 0; i < noIndices * 2; i++ ) {
                planeBorderIndices.array[i].angle = atan2(vertices[i].x - centre.x, vertices[i].y - centre.y);
            }
            free(vertices);
            free(indices);
            sortBorderIndicesByAngle(&planeBorderIndices);
            if ( planeBorderIndices.array[0].index != planeBorderIndices.array[1].index ) { // start on BorderIndex with the same BorderStrip
                appendBorderIndices(&planeBorderIndices, planeBorderIndices.array[0]);
                removeBorderIndicesAtIndex(&planeBorderIndices, 0);
            }

            LineStrip combinedLineStrip;
            initLineStrip(&combinedLineStrip, 128);
            
            borderIndex = 0;
            while ( borderIndex < planeBorderIndices.used ) {
                index = planeBorderIndices.array[borderIndex].index;
                pStrip = &borderStrips->array[index].pStripList->array[borderStrips->array[index].index];
                reverse = NO;
                if( !CGPointEqualToPoint(borderStrips->array[index].startPoint, planeBorderIndices.array[borderIndex].point) ) {
                    reverse = YES;
                }
                if ( ((BOOL)borderStrips->array[index].reverse && !reverse) || (!(BOOL)borderStrips->array[index].reverse && reverse)  ) {
                    for ( NSInteger k = (NSInteger)pStrip->used - 1; k > -1; k-- ) {
                        appendLineStrip(&combinedLineStrip, pStrip->array[k]);
                    }
                }
                else {
                    for ( NSUInteger k = 0; k < pStrip->used; k++ ) {
                        appendLineStrip(&combinedLineStrip, pStrip->array[k]);
                    }
                }
                borderIndex+= 2;
            }
            appendLineStrip(&combinedLineStrip, combinedLineStrip.array[0]);
        
            if ( combinedLineStrip.used > 0 ) {
                usedExtraLineStripLists[actualPlane] = YES;
                LineStripList *pReOrganisedLineStripList = [contours getExtraIsoCurvesListsAtIsoCurve:actualPlane];
                [contours addLineStripToLineStripList:pReOrganisedLineStripList lineStrip:&combinedLineStrip isoCurve:actualPlane];
            }
            freeBorderIndices(&planeBorderIndices);
            freeStrips(&planeStrips);
        }
    }
}

// finds next valid inner closed contour in an outer closed contour and passes back the plane and no of contours found
- (NSUInteger) findClosedDataLinePaths:(CGMutablePathRef **)foundClosedDataLinePaths noFoundClosedDataLinePaths:(NSUInteger)noFound OuterCGPath:(CGMutablePathRef*)outerCGPath InnerCGPaths:(CGMutablePathRef**)innerCGPaths noInnerCGPaths:(NSUInteger)noInnerCGPaths context:(nonnull CGContextRef)context contours:(CPTContours *)contours plane:(NSUInteger*)plane leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge ascendingOrder:(BOOL)ascendingOrder {
    NSUInteger counter = noFound;
    NSUInteger currentPlane, foundPlane = *plane;
    // now check for closed contours within  the ref contour and added border contours
    if ( (ascendingOrder && *plane + 1 < [self.isoCurvesIndices count]) || (!ascendingOrder && (NSInteger)*plane - 1 > -1) ) {
        Strips workingStrips;
        initStrips(&workingStrips, 8);
//        if ( !CGPathIsEmpty(*outerCGPath) && ![self isCGPathClockwise:*outerCGPath] ) {
//            [self reverseCGPath:outerCGPath];
//        }
//        if ( innerCGPaths != NULL ) {
//            for( NSUInteger i = 0; i < noInnerCGPaths; i++ ) {
//                if ( !CGPathIsEmpty(*(*innerCGPaths + i)) && ![self isCGPathClockwise:*(*innerCGPaths + i)] ) {
//                    [self reverseCGPath:(*innerCGPaths + i)];
//                }
//            }
//        }
//        CGMutablePathRef joinedCGPath;
        CGMutablePathRef *joinedCGPaths = (CGMutablePathRef*)calloc(1, sizeof(CGMutablePathRef));
        NSUInteger noJoinedCGPaths = 0;
        if ( innerCGPaths != NULL ) {
            NSUInteger *usedIndices, noUsedIndices = 0;
//            joinedCGPath = CGPathCreateMutable();
            usedIndices = (NSUInteger*)calloc(1, sizeof(NSUInteger));
//            if ( [self createCGPathOfJoinedCGPathsPlanesWithACommonEdge:*outerCGPath innerPaths:*innerCGPaths noInnerPaths:noInnerCGPaths leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge joinedCGPaths:&joinedCGPaths usedIndices:&usedIndices noUsedIndices:&noUsedIndices] ) {
////                CGMutablePathRef *splitCGPaths = (CGMutablePathRef*)calloc(1, sizeof(CGMutablePathRef));
////                NSUInteger noSplits = [self splitSelfIntersectingCGPath:joinedCGPath SeparateCGPaths:&splitCGPaths leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
////                NSLog(@"%ld", noSplits);
////                free(splitCGPaths);
//            }
            noJoinedCGPaths = [self createCGPathOfJoinedCGPathsPlanesWithACommonEdge:outerCGPath innerPaths:innerCGPaths noInnerPaths:noInnerCGPaths leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge joinedCGPaths:&joinedCGPaths usedIndices:&usedIndices noUsedIndices:&noUsedIndices];
            free(usedIndices);
        }
        else {
            joinedCGPaths[0] = CGPathCreateMutableCopy(*outerCGPath);
            noJoinedCGPaths = 1;
        }
        CGPoint startPoint;
        CGAffineTransform transform = CGAffineTransformIdentity;
//        currentPlane = ascendingOrder ? *plane + 1 : *plane - 1;
        currentPlane = *plane;
//        while ( TRUE ) {
            if( [self checkForClosedIsoCurvesInsideOuterIsoCurve:context contours:contours Plane:currentPlane Strips:&workingStrips ascendingOrder:ascendingOrder useExtraLineStripList:NO] ) {
                BOOL include = YES, foundCGPath = NO;
                for( NSUInteger i = 0; i < (NSUInteger)workingStrips.used; i++ ) {
                    CGMutablePathRef foundDataLinePath = CGPathCreateMutable();
                    [self createClosedDataLinePath:&foundDataLinePath context:context contours:contours strip:workingStrips index:i startPoint:&startPoint];
                    if ( ![self isCGPathClockwise:foundDataLinePath] ) {
                        [self reverseCGPath:&foundDataLinePath];
                    }
                    include = YES;
                    foundCGPath = NO;
                    if ( innerCGPaths != NULL ) {
                        for( NSUInteger j = 0; j < noJoinedCGPaths; j++) {
                            if( CGPathContainsPoint(joinedCGPaths[j], &transform, startPoint, YES) ) {
                                foundCGPath = YES;
                                break;
                            }
                        }
                    }
                    else {
                        if( CGPathContainsPoint(joinedCGPaths[0], &transform, startPoint, YES) ) {
                            foundCGPath = YES;
                        }
                    }
//                    if ( **innerCGPaths != NULL && !CGPathIsEmpty(joinedCGPath) ) {
//                        if ( CGPathContainsPoint(joinedCGPath, &transform, startPoint, YES) ) {
//                            foundCGPath = YES;
//                        }
////                        for ( NSUInteger j = 0; j < noInnerCGPaths; j++ ) {
////                            lastPoint = CGPathGetCurrentPoint(*(*innerCGPaths + j));
////                            NSLog(@"%f %f", lastPoint.x, lastPoint.y);
////                            if( CGPathContainsPoint(*outerCGPath, &transform, startPoint, YES) && CGPathContainsPoint(*outerCGPath, &transform, lastPoint, YES) && !CGPathContainsPoint(*(*innerCGPaths + j), &transform, startPoint, YES) ) {
////                                foundCGPath = YES;
////                                break;
////                            }
////                        }
//                    }
//                    else {
//                        if( CGPathContainsPoint(*outerCGPath, &transform, startPoint, YES) ) {
//                            foundCGPath = YES;
//                        }
//                    }
                    
                    if ( foundCGPath ) {
                        for( NSUInteger j = 0; j < counter; j++) {
                            if ( !(include = !CGPathContainsPoint(*(*foundClosedDataLinePaths + j), &transform, startPoint, YES)) ) {
                                break;
                            }
                        }
                    }
                    if ( include && foundCGPath ) {
                        foundPlane = workingStrips.array[i].plane;
                        *(*foundClosedDataLinePaths + counter) = CGPathCreateMutableCopy(foundDataLinePath);
                        counter++;
                        *foundClosedDataLinePaths = (CGMutablePathRef*)realloc(*foundClosedDataLinePaths, sizeof(CGMutablePathRef) * (size_t)(counter + 1));
                    }
                    CGPathRelease(foundDataLinePath);
                }
                clearStrips(&workingStrips);
            }
//            if( (ascendingOrder && currentPlane + 1 > [self.isoCurvesIndices count] - 1) || (!ascendingOrder && (NSInteger)currentPlane - 1 < 0) ) {
//                break;
//            }
//            currentPlane = ascendingOrder ? currentPlane + 1 : currentPlane - 1;
//        }
//        if ( **innerCGPaths != NULL ) {
//            CGPathRelease(joinedCGPath);
//        }
        for ( NSUInteger i = 0; i < noJoinedCGPaths; i++ ) {
            CGPathRelease(joinedCGPaths[i]);
        }
        free(joinedCGPaths);
        freeStrips(&workingStrips);
        *plane = foundPlane;
    }
    return counter;
}

- (NSUInteger) findClosedDataLinePaths:(CGMutablePathRef**)foundClosedDataLinePaths noFoundClosedDataLinePaths:(NSUInteger)noFound foundClosedPlanes:(NSUInteger**)foundClosedPlanes OuterCGPath:(CGMutablePathRef*)outerCGPath context:(nonnull CGContextRef)context contours:(CPTContours *)contours plane:(NSUInteger)plane leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge ascendingOrder:(BOOL)ascendingOrder useExtraLineStripList:(BOOL)useExtraLineStripList fromCurrentPlane:(BOOL)fromCurrentPlane checkPointOnPath:(BOOL)checkPointOnPath {
    NSUInteger counter = noFound;
    NSUInteger currentPlane;
    // now check for closed contours within  the ref contour and added border contours
    if ( (ascendingOrder && plane + 1 < [self.isoCurvesIndices count]) || (!ascendingOrder && (NSInteger)plane - 1 > -1) ) {
        Strips workingStrips;
        initStrips(&workingStrips, 8);
        
        CGPoint startPoint;
        CGAffineTransform transform = CGAffineTransformIdentity;
        if ( fromCurrentPlane ) {
            currentPlane = plane;
        }
        else {
            currentPlane = ascendingOrder ? plane + 1 : plane - 1;
        }
        CGFloat areaOfOuterCGPath = fabs(cgpathArea(*outerCGPath));
        //        while ( TRUE ) {
        if( [self checkForClosedIsoCurvesInsideOuterIsoCurve:context contours:contours Plane:currentPlane Strips:&workingStrips ascendingOrder:ascendingOrder useExtraLineStripList:useExtraLineStripList] ) {
            BOOL include = YES, foundCGPath = NO;
            CGPoint centreOfPath;
            CGFloat areaOfFoundDataLinePath;
            for( NSUInteger i = 0; i < (NSUInteger)workingStrips.used; i++ ) {
                CGMutablePathRef foundDataLinePath = CGPathCreateMutable();
                include = YES;
                foundCGPath = NO;
                [self createClosedDataLinePath:&foundDataLinePath context:context contours:contours strip:workingStrips index:i startPoint:&startPoint];
                centreOfPath = GetCenterPointOfCGPath(foundDataLinePath);
                areaOfFoundDataLinePath = fabs(cgpathArea(foundDataLinePath));
                if( CGPathContainsPoint(*outerCGPath, &transform, centreOfPath, YES) && areaOfFoundDataLinePath < areaOfOuterCGPath ) {
                    foundCGPath = YES;
#if TARGET_OS_OSX
                    NSBezierPath * bezierPath = [NSBezierPath bezierPathWithCGPath:*outerCGPath];
                    [bezierPath appendBezierPath:[NSBezierPath bezierPathWithCGPath:foundDataLinePath]];
#else
                    UIBezierPath * bezierPath = [UIBezierPath bezierPathWithCGPath:*outerCGPath];
                    [bezierPath appendPath:[UIBezierPath bezierPathWithCGPath:foundDataLinePath]];
#endif
//                    if( CGPathEqualToPath(*outerCGPath, foundDataLinePath) || (checkPointOnPath && [self checkCGPathHasCGPoint:*outerCGPath point: workingStrips.array[i].startPoint]) ) {
//                        foundCGPath = NO;
//                    }
//                    else {
                        for( NSUInteger j = 0; j < counter; j++) {
                            if ( !(include = !CGPathContainsPoint(*(*foundClosedDataLinePaths + j), &transform, startPoint, YES)) ) {
                                break;
                            }
                        }
//                    }
                }
                if ( include && foundCGPath ) {
#if TARGET_OS_OSX
                    NSBezierPath * __unused bezierPath = [NSBezierPath bezierPathWithCGPath:foundDataLinePath];
#else
                    UIBezierPath * __unused bezierPath = [UIBezierPath bezierPathWithCGPath:foundDataLinePath];
#endif
                    *(*foundClosedDataLinePaths + counter) = CGPathCreateMutableCopy(foundDataLinePath);
                    *(*foundClosedPlanes + counter) = workingStrips.array[i].plane;
                    counter++;
                    *foundClosedDataLinePaths = (CGMutablePathRef*)realloc(*foundClosedDataLinePaths, sizeof(CGMutablePathRef) * (size_t)(counter + 1));
                    *foundClosedPlanes = (NSUInteger*)realloc(*foundClosedPlanes, sizeof(NSUInteger) * (size_t)(counter + 1));
                }
                CGPathRelease(foundDataLinePath);
            }
            clearStrips(&workingStrips);
        }
        freeStrips(&workingStrips);
    }
    return counter;
}

- (NSUInteger) findClosedDataLinePaths:(CGMutablePathRef**)foundClosedDataLinePaths foundClosedPlanes:(NSUInteger**)foundClosedPlanes OuterCGPath:(CGMutablePathRef*)outerCGPath context:(nonnull CGContextRef)context contours:(CPTContours *)contours leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge useExtraLineStripList:(BOOL)useExtraLineStripList checkPointOnPath:(BOOL)checkPointOnPath {
    NSUInteger counter = 0;
    NSUInteger currentPlane;
    Strips workingStrips;
    initStrips(&workingStrips, 8);
    CGPoint startPoint;
    CGAffineTransform transform = CGAffineTransformIdentity;
    // now check for closed contours within  the ref contour and added border contours
    for ( NSUInteger i = 0; i < [self.isoCurvesIndices count]; i++ ) {
        currentPlane = [[self.isoCurvesIndices objectAtIndex:i] unsignedIntegerValue];
        [self searchPlaneClosedIsoCurves:context contours:contours Plane:currentPlane ClosedStrips:&workingStrips useExtraLineStripList:useExtraLineStripList];
        if ( workingStrips.used > 0 ) {
            BOOL include = YES, foundCGPath = NO;
            for( NSUInteger j = 0; j < (NSUInteger)workingStrips.used; j++ ) {
                CGMutablePathRef foundDataLinePath = CGPathCreateMutable();
                include = YES;
                foundCGPath = NO;
                if( CGPathContainsPoint(*outerCGPath, &transform, workingStrips.array[j].startPoint, YES) ) {
                    foundCGPath = YES;
                    [self createClosedDataLinePath:&foundDataLinePath context:context contours:contours strip:workingStrips index:j startPoint:&startPoint];
                    
    #if TARGET_OS_OSX
                    NSBezierPath * __unused bezierPath = [NSBezierPath bezierPathWithCGPath:foundDataLinePath];
    #else
                    UIBezierPath *  __unused bezierPath = [UIBezierPath bezierPathWithCGPath:foundDataLinePath];
    #endif
                    if( CGPathEqualToPath(*outerCGPath, foundDataLinePath) || (checkPointOnPath && [self checkCGPathHasCGPoint:*outerCGPath point: workingStrips.array[j].startPoint]) ) {
                        foundCGPath = NO;
                    }
                    else {
                        for( NSUInteger k = 0; k < counter; k++) {
                            if ( !(include = !CGPathContainsPoint(*(*foundClosedDataLinePaths + k), &transform, startPoint, YES)) ) {
                                break;
                            }
                        }
                    }
                }
                
                if ( include && foundCGPath ) {
    #if TARGET_OS_OSX
                    NSBezierPath * __unused bezierPath = [NSBezierPath bezierPathWithCGPath:foundDataLinePath];
    #else
                    UIBezierPath * __unused bezierPath = [UIBezierPath bezierPathWithCGPath:foundDataLinePath];
    #endif
                    *(*foundClosedDataLinePaths + counter) = CGPathCreateMutableCopy(foundDataLinePath);
                    *(*foundClosedPlanes + counter) = workingStrips.array[j].plane;
                    counter++;
                    *foundClosedDataLinePaths = (CGMutablePathRef*)realloc(*foundClosedDataLinePaths, sizeof(CGMutablePathRef) * (size_t)(counter + 1));
                    *foundClosedPlanes = (NSUInteger*)realloc(*foundClosedPlanes, sizeof(NSUInteger) * (size_t)(counter + 1));
                }
                CGPathRelease(foundDataLinePath);
            }
            clearStrips(&workingStrips);
        }
    }

    freeStrips(&workingStrips);
    
    return counter;
}

-(void)shiftUpInnerDataLinePaths:(CGMutablePathRef *)dataLinePaths noPaths:(NSUInteger*)noPaths index:(NSUInteger)index {
    // move all datalinePaths below index up and free the last datalinePath
    if ( index < *noPaths ) {
        for( NSUInteger i = index; i < *noPaths-1; i++ ) {
            CGPathRelease(dataLinePaths[i]);
            dataLinePaths[i] = CGPathCreateMutableCopy(dataLinePaths[i+1]);
        }
        CGPathRelease(dataLinePaths[*noPaths-1]);
        *noPaths = *noPaths - 1;
    }
}

- (void)searchPlaneClosedIsoCurves:(nonnull CGContextRef)context contours:(CPTContours *)contours Plane:(NSUInteger)actualPlane ClosedStrips:(Strips*)closedStrips useExtraLineStripList:(BOOL)useExtraLineStripList {
    LineStripList *pStripList = useExtraLineStripList && [contours getExtraIsoCurvesListsAtIsoCurve:actualPlane]->used > 0 ? [contours getExtraIsoCurvesListsAtIsoCurve:actualPlane] : [contours getStripListForIsoCurve:actualPlane];
    LineStrip *pStrip = NULL;
    NSUInteger indexStart, indexEnd;
    Strip closedStrip = initStrip();
    closedStrip.pStripList = pStripList;
    NSUInteger index = 0;
    for (NSUInteger pos = 0; pos < (NSUInteger)pStripList->used; pos++) {
        pStrip = &pStripList->array[pos];
        if (pStrip != NULL && pStrip->used > 0) {
            indexStart = pStrip->array[0];
            indexEnd = pStrip->array[pStrip->used-1];
            if ( !([contours isNodeOnBoundary:indexStart] && [contours isNodeOnBoundary:indexEnd]) || (!self.extrapolateToLimits && !self.functionPlot) ) {
                CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
                double startX = ([contours getXAt:indexStart] - thePlotSpace.xRange.locationDouble) * self.scaleX;
                double startY = ([contours getYAt:indexStart] - thePlotSpace.yRange.locationDouble) * self.scaleY;
                double endX = ([contours getXAt:indexEnd] - thePlotSpace.xRange.locationDouble) * self.scaleX;
                double endY = ([contours getYAt:indexEnd] - thePlotSpace.yRange.locationDouble) * self.scaleY;
                CGPoint startPoint = CGPointMake(startX, startY);
                CGPoint endPoint = CGPointMake(endX, endY);
                CGPoint convertPoints[2] = { startPoint, endPoint };
                [self convertPointsIfPixelAligned:context points:convertPoints noPoints:2];
                closedStrip.startPoint = convertPoints[0];
                closedStrip.endPoint = convertPoints[1];
                closedStrip.startBorderdirection = CPTContourBorderDimensionDirectionNone;
                closedStrip.endBorderdirection = CPTContourBorderDimensionDirectionNone;
                closedStrip.reverse = 0;
                if ( indexStart == indexEnd) {
                    closedStrip.index = index;
                    closedStrip.plane = actualPlane;
                    closedStrip.usedInExtra = 0;
                    closedStrip.extra = 0;
                    appendStrips(closedStrips, closedStrip);
                }
                else {
                    // also check if the contours is nearly closed based on DX,DY tolerance and assume contour is closed
                    if ( sqrt(pow(startX - endX, 2.0) + pow(startY - endY, 2.0)) < 10.0 * sqrt(pow([contours getDX] * self.scaleX, 2.0) + pow([contours getDY] * self.scaleY, 2.0)) || (!self.extrapolateToLimits && !self.functionPlot) ) {  // if contours are not extrapolated to a rectangle
                        closedStrip.endPoint = closedStrip.startPoint;
                        closedStrip.index = index;
                        closedStrip.plane = actualPlane;
                        closedStrip.usedInExtra = 0;
                        closedStrip.extra = 0;
                        appendStrips(closedStrips, closedStrip);
                    }
                }
            }
        }
        index++;
    }
}
    
- (void)searchPlaneBorderIsoCurves:(nonnull CGContextRef)context contours:(CPTContours *)contours Plane:(NSUInteger)actualPlane  BorderStrips:(Strips*)borderStrips useExtraLineStripList:(BOOL)useExtraLineStripList leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    CGPoint convertPoints[2];
    LineStripList *pStripList = useExtraLineStripList ? [contours getExtraIsoCurvesListsAtIsoCurve:actualPlane] : [contours getStripListForIsoCurve:actualPlane];
    LineStrip *pStrip = NULL;
    NSUInteger indexStart, indexEnd;
    Strip borderStrip = initStrip();
    borderStrip.pStripList = pStripList;
    borderStrip.usedInExtra = 0;
    borderStrip.extra = useExtraLineStripList;
    CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
    for ( NSUInteger pos = 0; pos < (NSUInteger)pStripList->used; pos++ ) {
        pStrip = &pStripList->array[pos];
        if ( pStrip != NULL && pStrip->used > 0 ) {
            indexStart = pStrip->array[0];
            indexEnd = pStrip->array[pStrip->used - 1];
            // check that end and start indexs are not the same, then if they are on the boundary
            if ( indexStart != indexEnd && [contours isNodeOnBoundary:indexStart] && [contours isNodeOnBoundary:indexEnd] ) {
                // from indexs get physical point in plot space
                double startX = ([contours getXAt:indexStart] - thePlotSpace.xRange.locationDouble) * self.scaleX;
                double startY = ([contours getYAt:indexStart] - thePlotSpace.yRange.locationDouble) * self.scaleY;
                double endX = ([contours getXAt:indexEnd] - thePlotSpace.xRange.locationDouble) * self.scaleX;
                double endY = ([contours getYAt:indexEnd] - thePlotSpace.yRange.locationDouble) * self.scaleY;
                CGPoint startPoint = CGPointMake(startX, startY);
                CGPoint endPoint = CGPointMake(endX, endY);
                convertPoints[0] = startPoint;
                convertPoints[1] = endPoint;
                [self convertPointsIfPixelAligned:context points:convertPoints noPoints:2];
                startPoint = convertPoints[0];
                endPoint = convertPoints[1];
            
                // depending on the start edge of contour update the borderStrip.startBorderdirection
                BOOL foundBorder = NO;
                for ( int border = 0; border < 4; border++) {
                    switch(border) {
                        case CPTContourBorderDimensionDirectionXForward:
                            if ( (startPoint.y == bottomEdge || (startPoint.y == topEdge && endPoint.y == bottomEdge)) && startPoint.x > leftEdge && startPoint.x <= rightEdge ) {
                                borderStrip.index = pos;
                                borderStrip.plane = actualPlane;
                                borderStrip.reverse = 0;
                                borderStrip.startBorderdirection = border;
                                borderStrip.endBorderdirection = [self findEndPointBorderDirection:endPoint.y == bottomEdge ? startPoint : endPoint leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                                borderStrip.startPoint = startPoint;
                                borderStrip.endPoint = endPoint;
                                if( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                                    if( endPoint.x < startPoint.x ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    appendStrips(&borderStrips[0], borderStrip);
                                }
                                else if ( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionYForward || borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionXBackward ) {
                                    if ( endPoint.y == bottomEdge ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    appendStrips(&borderStrips[0], borderStrip);
                                }
                                else {  // if startBorderdirection == CPTContourBorderDimensionDirectionYBackward make it YBackward edge border
                                    borderStrip.startPoint = endPoint;
                                    borderStrip.endPoint = startPoint;
                                    borderStrip.startBorderdirection = CPTContourBorderDimensionDirectionYBackward;
                                    borderStrip.endBorderdirection = CPTContourBorderDimensionDirectionXForward;
                                    borderStrip.reverse = 1;
                                    appendStrips(&borderStrips[3], borderStrip);
                                }
                                foundBorder = YES;
                            }
                            break;
                        case CPTContourBorderDimensionDirectionYForward:
                            if ( (startPoint.x == rightEdge || (startPoint.x == leftEdge && endPoint.x == rightEdge)) && startPoint.y > bottomEdge && startPoint.y <= topEdge ) {
                                borderStrip.index = pos;
                                borderStrip.plane = actualPlane;
                                borderStrip.reverse = 0;
                                borderStrip.startBorderdirection = border;
                                borderStrip.endBorderdirection = [self findEndPointBorderDirection:endPoint.x == rightEdge ? startPoint : endPoint leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                                borderStrip.startPoint = startPoint;
                                borderStrip.endPoint = endPoint;
                                if( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionYForward ) {
                                    if( endPoint.y < startPoint.y ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    appendStrips(&borderStrips[1], borderStrip);
                                }
                                else if( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionXBackward || borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                                    if ( endPoint.x == rightEdge ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    appendStrips(&borderStrips[1], borderStrip);
                                }
                                else {
                                    borderStrip.startPoint = endPoint;
                                    borderStrip.endPoint = startPoint;
                                    borderStrip.startBorderdirection = CPTContourBorderDimensionDirectionXForward;
                                    borderStrip.endBorderdirection = CPTContourBorderDimensionDirectionYForward;
                                    borderStrip.reverse = 1;
                                    appendStrips(&borderStrips[0], borderStrip);
                                }
                                foundBorder = YES;
                            }
                            break;
                        case CPTContourBorderDimensionDirectionXBackward:
                            if ( startPoint.y == topEdge && startPoint.x < rightEdge && startPoint.x >= leftEdge ) {
                                borderStrip.index = pos;
                                borderStrip.plane = actualPlane;
                                borderStrip.startPoint = startPoint;
                                borderStrip.endPoint = endPoint;
                                borderStrip.startBorderdirection = border;
                                borderStrip.endBorderdirection = [self findEndPointBorderDirection:startPoint.y == topEdge ? endPoint : startPoint leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                                borderStrip.reverse = 0;
                                if( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionXBackward ) {
                                    if( endPoint.x > startPoint.x ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    appendStrips(&borderStrips[2], borderStrip);
                                }
                                else if ( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                                    if ( endPoint.y == topEdge ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    appendStrips(&borderStrips[2], borderStrip);
                                }
                                else if ( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                                    if ( endPoint.y == bottomEdge ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    borderStrip.startBorderdirection = CPTContourBorderDimensionDirectionXForward;
                                    borderStrip.endBorderdirection = CPTContourBorderDimensionDirectionXBackward;
                                    appendStrips(&borderStrips[0], borderStrip);
                                }
                                else {//} if ( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionYForward ) {
                                    if ( endPoint.x == rightEdge ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    borderStrip.startBorderdirection = CPTContourBorderDimensionDirectionYForward;
                                    borderStrip.endBorderdirection = CPTContourBorderDimensionDirectionXBackward;
                                    appendStrips(&borderStrips[1], borderStrip);
                                }
                                foundBorder = YES;
                            }
                            break;
                        default:
                        case CPTContourBorderDimensionDirectionYBackward:
                            if ( startPoint.x == leftEdge && startPoint.y < topEdge && startPoint.y >= bottomEdge ) {
                                borderStrip.index = pos;
                                borderStrip.plane = actualPlane;
                                borderStrip.reverse = 0;
                                borderStrip.startBorderdirection = border;
                                borderStrip.endBorderdirection = [self findEndPointBorderDirection:startPoint.x == leftEdge ? endPoint : startPoint leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
                                borderStrip.startPoint = startPoint;
                                borderStrip.endPoint = endPoint;
                                if( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                                    if( endPoint.y > startPoint.y ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    appendStrips(&borderStrips[3], borderStrip);
                                }
                                else if ( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                                    if ( endPoint.x == leftEdge ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    appendStrips(&borderStrips[3], borderStrip);
                                }
                                else if ( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionYForward ) {
                                    if ( endPoint.x == rightEdge ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    borderStrip.startBorderdirection = CPTContourBorderDimensionDirectionYForward;
                                    borderStrip.endBorderdirection = CPTContourBorderDimensionDirectionXBackward;
                                    appendStrips(&borderStrips[1], borderStrip);
                                }
                                else { //if ( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionXBackward ) {
                                    if ( startPoint.x == leftEdge ) {
                                        borderStrip.startPoint = endPoint;
                                        borderStrip.endPoint = startPoint;
                                        borderStrip.reverse = 1;
                                    }
                                    borderStrip.startBorderdirection = CPTContourBorderDimensionDirectionXBackward;
                                    borderStrip.endBorderdirection = CPTContourBorderDimensionDirectionYBackward;
                                    appendStrips(&borderStrips[2], borderStrip);
                                }
                                foundBorder = YES;
                            }
                            break;
                    }
                    if( foundBorder ) {
                        break;
                    }
                }
            }
        }
    }
}

- (void)collectBorderDiscontinuityStrips:(Strips*)discontinuityStrips BorderStrips:(Strips*)borderStrips leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    
    for ( NSUInteger i = 0; i < (NSUInteger)discontinuityStrips->used; i++ ) {
        // check that end and start positions are not the same, then if they are on the boundary
        Strip *pStrip = &(discontinuityStrips->array[i]);
        if ( !CGPointEqualToPoint(pStrip->startPoint, pStrip->endPoint) ) {
            // from indexs get physical point in plot space
           
            // depending on the start edge of contour update the borderStrip.startBorderdirection
            BOOL foundBorder = NO;
            CGPoint tempPoint;
            for ( int border = 0; border < 4; border++) {
                switch(border) {
                    case CPTContourBorderDimensionDirectionXForward:
                        if ( (pStrip->startPoint.y == bottomEdge || (pStrip->startPoint.y == topEdge && pStrip->endPoint.y == bottomEdge)) && pStrip->startPoint.x > leftEdge && pStrip->startPoint.x <= rightEdge ) {
                            if( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                                if( pStrip->endPoint.x < pStrip->startPoint.x ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                appendStrips(&borderStrips[0], *pStrip);
                            }
                            else if ( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionYForward || pStrip->endBorderdirection == CPTContourBorderDimensionDirectionXBackward ) {
                                if ( pStrip->endPoint.y == bottomEdge ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                appendStrips(&borderStrips[0], *pStrip);
                            }
                            else {  // if startBorderdirection == CPTContourBorderDimensionDirectionYBackward make it YBackward edge border
                                tempPoint = pStrip->startPoint;
                                pStrip->startPoint = pStrip->endPoint;
                                pStrip->endPoint = tempPoint;
                                pStrip->startBorderdirection = CPTContourBorderDimensionDirectionYBackward;
                                pStrip->endBorderdirection = CPTContourBorderDimensionDirectionXForward;
                                pStrip->reverse = 1;
                                appendStrips(&borderStrips[3], *pStrip);
                            }
                            foundBorder = YES;
                        }
                        break;
                    case CPTContourBorderDimensionDirectionYForward:
                        if ( (pStrip->startPoint.x == rightEdge || (pStrip->startPoint.x == leftEdge && pStrip->endPoint.x == rightEdge)) && pStrip->startPoint.y > bottomEdge && pStrip->startPoint.y <= topEdge ) {
                            if( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionYForward ) {
                                if( pStrip->endPoint.y < pStrip->startPoint.y ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                appendStrips(&borderStrips[1], *pStrip);
                            }
                            else if( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionXBackward || pStrip->endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                                if ( pStrip->endPoint.x == rightEdge ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                appendStrips(&borderStrips[1], *pStrip);
                            }
                            else {
                                tempPoint = pStrip->startPoint;
                                pStrip->startPoint = pStrip->endPoint;
                                pStrip->endPoint = tempPoint;
                                pStrip->startBorderdirection = CPTContourBorderDimensionDirectionXForward;
                                pStrip->endBorderdirection = CPTContourBorderDimensionDirectionYForward;
                                pStrip->reverse = 1;
                                appendStrips(&borderStrips[0], *pStrip);
                            }
                            foundBorder = YES;
                        }
                        break;
                    case CPTContourBorderDimensionDirectionXBackward:
                        if ( pStrip->startPoint.y == topEdge && pStrip->startPoint.x < rightEdge && pStrip->startPoint.x >= leftEdge ) {
                            if( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionXBackward ) {
                                if( pStrip->endPoint.x > pStrip->startPoint.x ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                appendStrips(&borderStrips[2], *pStrip);
                            }
                            else if ( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                                if ( pStrip->endPoint.y == topEdge ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                appendStrips(&borderStrips[2], *pStrip);
                            }
                            else if ( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                                if ( pStrip->endPoint.y == bottomEdge ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                pStrip->startBorderdirection = CPTContourBorderDimensionDirectionXForward;
                                pStrip->endBorderdirection = CPTContourBorderDimensionDirectionXBackward;
                                appendStrips(&borderStrips[0], *pStrip);
                            }
                            else {//} if ( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionYForward ) {
                                if ( pStrip->endPoint.x == rightEdge ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                pStrip->startBorderdirection = CPTContourBorderDimensionDirectionYForward;
                                pStrip->endBorderdirection = CPTContourBorderDimensionDirectionXBackward;
                                appendStrips(&borderStrips[1], *pStrip);
                            }
                            foundBorder = YES;
                        }
                        break;
                    default:
                    case CPTContourBorderDimensionDirectionYBackward:
                        if ( pStrip->startPoint.x == leftEdge && pStrip->startPoint.y < topEdge && pStrip->startPoint.y >= bottomEdge ) {
                            if( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                                if( pStrip->endPoint.y > pStrip->startPoint.y ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                appendStrips(&borderStrips[3], *pStrip);
                            }
                            else if ( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                                if ( pStrip->endPoint.x == leftEdge ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                appendStrips(&borderStrips[3], *pStrip);
                            }
                            else if ( pStrip->endBorderdirection == CPTContourBorderDimensionDirectionYForward ) {
                                if ( pStrip->endPoint.x == rightEdge ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                pStrip->startBorderdirection = CPTContourBorderDimensionDirectionYForward;
                                pStrip->endBorderdirection = CPTContourBorderDimensionDirectionXBackward;
                                appendStrips(&borderStrips[1], *pStrip);
                            }
                            else { //if ( borderStrip.endBorderdirection == CPTContourBorderDimensionDirectionXBackward ) {
                                if ( pStrip->startPoint.x == leftEdge ) {
                                    tempPoint = pStrip->startPoint;
                                    pStrip->startPoint = pStrip->endPoint;
                                    pStrip->endPoint = tempPoint;
                                    pStrip->reverse = 1;
                                }
                                pStrip->startBorderdirection = CPTContourBorderDimensionDirectionXBackward;
                                pStrip->endBorderdirection = CPTContourBorderDimensionDirectionYBackward;
                                appendStrips(&borderStrips[2], *pStrip);
                            }
                            foundBorder = YES;
                        }
                        break;
                }
                if( foundBorder ) {
                    break;
                }
            }
        }
    }
}

- (BOOL)checkIfProcessNonExtrapolateToLimitsInAscendingOrder:(nonnull CGContextRef)context contours:(CPTContours *)contours usedExtraLineStripLists:(BOOL*)usedExtraLineStripLists  {
    NSUInteger actualPlane = [[self.isoCurvesIndices firstObject] unsignedIntegerValue];
    BOOL ascendingOrder = [self checkIfEndRegionsContainAllOtherRegionsWhenNonExtrapolateToLimits:context contours:contours usedExtraLineStripLists:usedExtraLineStripLists plane:actualPlane ascendingOrder:YES];
    actualPlane = [[self.isoCurvesIndices lastObject] unsignedIntegerValue];
    BOOL __unused second = [self checkIfEndRegionsContainAllOtherRegionsWhenNonExtrapolateToLimits:context contours:contours usedExtraLineStripLists:usedExtraLineStripLists plane:actualPlane ascendingOrder:NO];
    
    return ascendingOrder;
}

-(BOOL)checkIfEndRegionsContainAllOtherRegionsWhenNonExtrapolateToLimits:(nonnull CGContextRef)context contours:(CPTContours *)contours usedExtraLineStripLists:(BOOL*)usedExtraLineStripLists plane:(NSUInteger)actualPlane ascendingOrder:(BOOL)ascendingOrder {
    
    Strips closedStrips;
    initStrips(&closedStrips, 8);
    [self searchPlaneClosedIsoCurves:context contours:contours Plane:actualPlane ClosedStrips:&closedStrips useExtraLineStripList:usedExtraLineStripLists[actualPlane]];
    if ( usedExtraLineStripLists[actualPlane] ) {
        for( NSUInteger j = 0; j < closedStrips.used; j ++ ) {
            closedStrips.array[j].extra = 1;
        }
        [self searchPlaneClosedIsoCurves:context contours:contours Plane:actualPlane ClosedStrips:&closedStrips useExtraLineStripList:NO];
        for( NSUInteger j = 0; j < (NSUInteger)closedStrips.used; j++ ) {
            if ( closedStrips.array[j].usedInExtra ) {
                removeStripsAtIndex(&closedStrips, (size_t)j);
                j--;
            }
        }
    }
    BOOL *containsAllOthers = (BOOL*)malloc((size_t)closedStrips.used * sizeof(BOOL));
    for( NSUInteger j = 0; j < closedStrips.used; j ++ ) {
        containsAllOthers[j] = YES;
    }
    BOOL containsAllOther = YES;
    NSUInteger indexedPlane = [self findIsoCurveIndicesIndex:actualPlane];
    if ( (ascendingOrder && indexedPlane < self.isoCurvesIndices.count) || (!ascendingOrder && (NSInteger)indexedPlane >= 0) ) {
        indexedPlane = ascendingOrder ? indexedPlane + 1 : indexedPlane - 1;
    }
    CGAffineTransform transform = CGAffineTransformIdentity;
    Strips workingStrips;
    initStrips(&workingStrips, 8);
    if( [self checkForClosedIsoCurvesInsideOuterIsoCurve:context contours:contours Plane:indexedPlane Strips:&workingStrips ascendingOrder:ascendingOrder useExtraLineStripList:usedExtraLineStripLists[[self.isoCurvesIndices[indexedPlane] unsignedIntegerValue]]] ) {
        
        for ( NSUInteger i = 0; i < (NSUInteger)closedStrips.used; i++ ) {
            CGMutablePathRef refDataLinePath = CGPathCreateMutable();
            CGPoint startPoint, centerOfPath;
            [self createClosedDataLinePath:&refDataLinePath context:context contours:contours strip:closedStrips index:i startPoint:&startPoint];
#if TARGET_OS_OSX
            NSBezierPath *bezierPath = [NSBezierPath bezierPathWithCGPath:refDataLinePath];
#else
            UIBezierPath *bezierPath = [UIBezierPath bezierPathWithCGPath:refDataLinePath];
#endif
            for( NSUInteger j = 0; j < workingStrips.used; j++ ) {
                CGMutablePathRef workingDataLinePath = CGPathCreateMutable();
                [self createClosedDataLinePath:&workingDataLinePath context:context contours:contours strip:workingStrips index:j startPoint:&startPoint];
#if TARGET_OS_OSX
                NSBezierPath *bezierPath0 = [NSBezierPath bezierPathWithCGPath:workingDataLinePath];
                [bezierPath appendBezierPath:bezierPath0];
#else
                UIBezierPath *bezierPath0 = [UIBezierPath bezierPathWithCGPath:workingDataLinePath];
                [bezierPath appendPath:bezierPath0];
#endif
                centerOfPath = GetCenterPointOfCGPath(workingDataLinePath);
                CGPathRelease(workingDataLinePath);
                if( !CGPathContainsPoint(refDataLinePath, &transform, centerOfPath, YES) ) {
                    containsAllOthers[i] = NO;
                    break;
                }
                
            }
            CGPathRelease(refDataLinePath);
        }
    }
    freeStrips(&workingStrips);
    for( NSUInteger j = 0; j < closedStrips.used; j ++ ) {
        containsAllOther &= containsAllOthers[j] ;
    }
    clearStrips(&closedStrips);
    free(containsAllOthers);
    
    return containsAllOther;
}


-(BOOL)checkIfNextNodeIsInside:(NSUInteger)nextPosition currentNode:(NSUInteger)currentPosition borderStrips:(Strips*)borderStrips leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    NSAssert(currentPosition < borderStrips->used && nextPosition < borderStrips->used, @"nextPosition or currentPosition not valid!");
    BOOL isInside = NO;
    CPTContourBorderDimensionDirection startDirection = borderStrips->array[currentPosition].startBorderdirection;
    CPTContourBorderDimensionDirection endDirection = borderStrips->array[currentPosition].endBorderdirection;
    CGPoint startPoint = borderStrips->array[currentPosition].startPoint;
    CGPoint endPoint = borderStrips->array[currentPosition].endPoint;
    CGPoint startNextPoint =  borderStrips->array[nextPosition].startPoint;
    CGPoint endNextPoint =  borderStrips->array[nextPosition].endPoint;
    if ( startDirection == CPTContourBorderDimensionDirectionXForward && endDirection == CPTContourBorderDimensionDirectionXForward ) {
        if ( startNextPoint.x > startPoint.x && startNextPoint.x < endPoint.x && endNextPoint.x > startPoint.x && endNextPoint.x < endPoint.x ) {
            isInside = YES;
        }
    }
    else if ( startDirection == CPTContourBorderDimensionDirectionXBackward && endDirection == CPTContourBorderDimensionDirectionXBackward && startNextPoint.x > endPoint.x && startNextPoint.x < startPoint.x && endNextPoint.x > endPoint.x && endNextPoint.x < startPoint.x ) {
        isInside = YES;
    }
    else if ( startDirection == CPTContourBorderDimensionDirectionYForward && endDirection == CPTContourBorderDimensionDirectionYForward && startNextPoint.y > startPoint.y && startNextPoint.y < endPoint.y && endNextPoint.y > startPoint.y && endNextPoint.y < endPoint.y ) {
        isInside = YES;
    }
    else if ( startDirection == CPTContourBorderDimensionDirectionYBackward && endDirection == CPTContourBorderDimensionDirectionYBackward && startNextPoint.y > endPoint.y && startNextPoint.y < startPoint.y && endNextPoint.y > endPoint.y && endNextPoint.y < startPoint.y ) {
        isInside = YES;
    }
    else if ( startDirection == CPTContourBorderDimensionDirectionXForward && endDirection == CPTContourBorderDimensionDirectionYForward && startNextPoint.x > startPoint.x && startNextPoint.x <= endPoint.x && startNextPoint.y >= startPoint.y && startNextPoint.y < endPoint.y && endNextPoint.x > startPoint.x && startNextPoint.x <= endPoint.x && endNextPoint.y >= startPoint.y && endNextPoint.y < endPoint.y ) {
        isInside = YES;
    }
    else if ( startDirection == CPTContourBorderDimensionDirectionYForward && endDirection == CPTContourBorderDimensionDirectionXBackward && startNextPoint.y > startPoint.y && startNextPoint.y <= endPoint.y && startNextPoint.x <= startPoint.x && startNextPoint.x > endPoint.x && endNextPoint.y > startPoint.y && endNextPoint.y <= endPoint.y && endNextPoint.x <= startPoint.x && endNextPoint.x > endPoint.x ) {
        isInside = YES;
    }
    else if ( startDirection == CPTContourBorderDimensionDirectionXBackward && endDirection == CPTContourBorderDimensionDirectionYBackward && startNextPoint.x < startPoint.x && startNextPoint.x >= endPoint.x && startNextPoint.y <= startPoint.y && startNextPoint.y > endPoint.y && endNextPoint.x < startPoint.x && endNextPoint.x >= endPoint.x && endNextPoint.y <= startPoint.y && endNextPoint.y > endPoint.y ) {
        isInside = YES;
    }
    else if ( startDirection == CPTContourBorderDimensionDirectionYBackward && endDirection == CPTContourBorderDimensionDirectionXForward && startNextPoint.y < startPoint.y && startNextPoint.y >= endPoint.y && startNextPoint.x >= startPoint.x && startNextPoint.x < endPoint.x && endNextPoint.y < startPoint.y && endNextPoint.y >= endPoint.y && endNextPoint.x >= startPoint.x && endNextPoint.x < endPoint.x ) {
        isInside = YES;
    }
    else if ( startDirection == CPTContourBorderDimensionDirectionXForward && endDirection == CPTContourBorderDimensionDirectionXBackward && startNextPoint.x > startPoint.x && startNextPoint.x < rightEdge && startNextPoint.y >= startPoint.y && startNextPoint.y <= endPoint.y && endNextPoint.x > startPoint.x && endNextPoint.x < rightEdge && endNextPoint.y >= startPoint.y && endNextPoint.y <= endPoint.y ) {
        isInside = YES;
    }
    else if ( startDirection == CPTContourBorderDimensionDirectionYForward && endDirection == CPTContourBorderDimensionDirectionYBackward && startNextPoint.y > startPoint.y && startNextPoint.y < topEdge && startNextPoint.x >= startPoint.x && startNextPoint.x <= endPoint.x && endNextPoint.y > startPoint.y && endNextPoint.y < topEdge && endNextPoint.x >= startPoint.x && endNextPoint.x <= endPoint.x) {
        isInside = YES;
    }
    return isInside;
}

-(NSUInteger)checkAnyNodesBetweenEndPoint:(CGPoint)endPoint startPoint:(CGPoint)startPoint betweenCurrentPosition:(NSUInteger)currentPosition andNextPosition:(NSUInteger)nextPosition discardedPosition:(NSUInteger)discardedPosition BorderStrips:(Strips*)borderStrips Nodes:(NSUInteger**)nodes {
    NSUInteger count = 0;
    NSUInteger *pointerNodes = *nodes;
    NSAssert(currentPosition < borderStrips->used && nextPosition < borderStrips->used, @"currentPosition or nextPosition not valid!");
    for( NSUInteger i = currentPosition + 1; i < nextPosition; i++ ) {
        if ( i != discardedPosition && ((borderStrips->array[i].startPoint.x > startPoint.x && borderStrips->array[i].startPoint.x < endPoint.x) || (borderStrips->array[i].startPoint.y > startPoint.y && borderStrips->array[i].startPoint.y < endPoint.y)) ) {
            pointerNodes[count] = (NSUInteger)i;
            count++;
            pointerNodes = (NSUInteger*)realloc(pointerNodes, (size_t)(count + 1) * sizeof(NSUInteger));
        }
    }
    *nodes = pointerNodes;
    return count;
}

-(NSUInteger)checkAnyNodesBetweenCurrentPosition:(NSUInteger)startPosition nextPosition:(NSUInteger)endPosition BorderStrips:(Strips*)borderStrips Nodes:(NSUInteger**)nodes leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
     NSAssert(endPosition < borderStrips->used && startPosition < borderStrips->used, @"endPosition or startPosition not valid!");
    NSUInteger *pointerNodes = *nodes;
    NSUInteger count = 0;
    CGPoint startPoint = borderStrips->array[startPosition].endPoint;
    CGFloat deltaNearestPoint0 = sqrt(pow(startPoint.x - borderStrips->array[endPosition].startPoint.x, 2.0) + pow(startPoint.y - borderStrips->array[endPosition].startPoint.y, 2.0));
    CGFloat deltaNearestPoint1 = sqrt(pow(startPoint.x - borderStrips->array[endPosition].endPoint.x, 2.0) + pow(startPoint.y - borderStrips->array[endPosition].endPoint.y, 2.0));
    CGPoint endPoint = deltaNearestPoint0 < deltaNearestPoint1 ? borderStrips->array[endPosition].startPoint : borderStrips->array[endPosition].endPoint;
    CPTContourBorderDimensionDirection startDirection, endDirection;
    CPTContourBorderDimensionDirection startRegionDirection = borderStrips->array[startPosition].endBorderdirection;
    CPTContourBorderDimensionDirection endRegionDirection = deltaNearestPoint0 < deltaNearestPoint1 ? borderStrips->array[endPosition].startBorderdirection : borderStrips->array[endPosition].endBorderdirection;
    CGPoint point;
    BOOL foundOne = NO;
    for ( NSUInteger i = 0; i < borderStrips->used; i++ ) {
        if ( i == startPosition ) {
            continue;
        }
        foundOne = NO;
        startDirection = borderStrips->array[i].startBorderdirection;
        endDirection = borderStrips->array[i].endBorderdirection;
        point = deltaNearestPoint0 < deltaNearestPoint1 ? borderStrips->array[i].startPoint : borderStrips->array[i].endPoint;
        if ( (startDirection == startRegionDirection || startDirection == endRegionDirection) && (endDirection == startRegionDirection || endDirection == endRegionDirection) ) {
            if ( ((startDirection == CPTContourBorderDimensionDirectionXForward && endDirection == CPTContourBorderDimensionDirectionXForward) || (startDirection == CPTContourBorderDimensionDirectionXBackward && endDirection == CPTContourBorderDimensionDirectionXBackward)) && point.x > startPoint.x && point.x < endPoint.x ) {
                foundOne = YES;
            }
            else if ( ((startDirection == CPTContourBorderDimensionDirectionYForward && endDirection == CPTContourBorderDimensionDirectionYForward) || (startDirection == CPTContourBorderDimensionDirectionYBackward && endDirection == CPTContourBorderDimensionDirectionYBackward)) && point.y > startPoint.y && point.y < endPoint.y ) {
                foundOne = YES;
            }
            else if ( startDirection == CPTContourBorderDimensionDirectionXForward && endDirection == CPTContourBorderDimensionDirectionYForward && point.x > startPoint.x && point.x < endPoint.x && point.y > startPoint.y && point.y < endPoint.y ) {
                foundOne = YES;
            }
            else if ( startDirection == CPTContourBorderDimensionDirectionYForward && endDirection == CPTContourBorderDimensionDirectionXBackward && point.y > startPoint.y && point.y < endPoint.y && point.x > startPoint.x && point.x < endPoint.x ) {
                foundOne = YES;
            }
            else if ( startDirection == CPTContourBorderDimensionDirectionXBackward && endDirection == CPTContourBorderDimensionDirectionYBackward && point.x > endPoint.x && point.x < startPoint.x && point.y > endPoint.y && point.y < startPoint.y ) {
                foundOne = YES;
            }
            else if ( startDirection == CPTContourBorderDimensionDirectionYBackward && endDirection == CPTContourBorderDimensionDirectionXForward && point.y > endPoint.y && point.y < startPoint.y && point.x > startPoint.x && point.x < endPoint.x ) {
                foundOne = YES;
            }
            else if ( startDirection == CPTContourBorderDimensionDirectionXForward && endDirection == CPTContourBorderDimensionDirectionXBackward && point.x > startPoint.x && point.x < rightEdge && point.y > startPoint.y && point.y < endPoint.y ) {
                foundOne = YES;
            }
            else if ( startDirection == CPTContourBorderDimensionDirectionYForward && endDirection == CPTContourBorderDimensionDirectionYBackward && point.y > startPoint.y && point.y < topEdge && point.x > startPoint.x && point.x < endPoint.x ) {
                foundOne = YES;
            }
            if ( foundOne ) {
                pointerNodes[count] = (NSUInteger)i;
                count++;
                pointerNodes = (NSUInteger*)realloc(pointerNodes, (size_t)(count + 1) * sizeof(NSUInteger));
            }
        }
    }
    *nodes = pointerNodes;
    return count;
}

/*-(void) DijkstraWithAdjacency:(CGFloat**)adjacency noVertices:(NSUInteger)n startNode:(NSUInteger)start {
    CGFloat **cost = (CGFloat**)calloc(n, sizeof(CGFloat*));
    for( NSUInteger i = 0; i < n; i++ ) {
        cost[i] = (CGFloat*)calloc(n, sizeof(CGFloat));
    }
    CGFloat *distance = (CGFloat*)calloc(n, sizeof(CGFloat));
    NSUInteger *pred = (NSUInteger*)calloc(n, sizeof(NSUInteger));
    BOOL *visited = (BOOL*)calloc(n, sizeof(BOOL));
    CGFloat mindistance;
    NSUInteger count, nextnode = 0;

    // Creating cost matrix
    for (NSUInteger i = 0; i < n; i++) {
        for (NSUInteger j = 0; j < n; j++) {
            if (adjacency[i][j] == 0.0) {
                cost[i][j] = CGFLOAT_MAX;
            }
            else {
                cost[i][j] = adjacency[i][j];
            }
        }
    }

    for (NSUInteger i = 0; i < n; i++) {
        distance[i] = cost[start][i];
        pred[i] = start;
        visited[i] = false;
    }

    distance[start] = 0.0;
    visited[start] = true;
    count = 1;

    while (count < n - 1) {
        mindistance = CGFLOAT_MAX;
        for (NSUInteger i = 0; i < n; i++) {
            if (distance[i] < mindistance && !visited[i]) {
                mindistance = distance[i];
                nextnode = i;
            }
        }
        visited[nextnode] = true;
        for (NSUInteger i = 0; i < n; i++) {
            if (!visited[i]) {
                if (mindistance + cost[nextnode][i] < distance[i]) {
                    distance[i] = mindistance + cost[nextnode][i];
                    pred[i] = nextnode;
                }
            }
        }
        count++;
    }

    // Printing the distance
    NSUInteger j;
    for (NSUInteger i = 0; i < n; i++) {
        if (i != start) {
            NSLog(@"\nDistance from source to %ld: %f", i, distance[i]);
            NSLog(@"\nPath=%ld",i);
            j = i;
            do {
                j = pred[j];
                NSLog(@"<-%ld",j);
            }   while(j != start);
        }
    }
    for( NSUInteger i = 0; i < n; i++ ) {
        free(cost[i]);
    }
    free(cost);
    free(distance);
    free(pred);
    free(visited);
}*/

-(CPTContourBorderDimensionDirection)findEndPointBorderDirection:(CGPoint)endPoint leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    CPTContourBorderDimensionDirection borderdirection;
    if ( endPoint.y == bottomEdge && endPoint.x >= leftEdge && endPoint.x <= rightEdge ) {
        borderdirection = CPTContourBorderDimensionDirectionXForward;
    }
    else if ( endPoint.x == rightEdge && endPoint.y >= bottomEdge && endPoint.y <= topEdge ) {
        borderdirection = CPTContourBorderDimensionDirectionYForward;
    }
    else if ( endPoint.y == topEdge && endPoint.x >= leftEdge && endPoint.x <= rightEdge ) {
        borderdirection = CPTContourBorderDimensionDirectionXBackward;
    }
    else {
        borderdirection = CPTContourBorderDimensionDirectionYBackward;
    }
    return borderdirection;
}

-(CPTContourBorderDimensionDirection)findPointBorderDirection:(CGPoint)point leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    CPTContourBorderDimensionDirection borderdirection;
    if ( point.y == bottomEdge && point.x >= leftEdge && point.x <= rightEdge ) {
        borderdirection = CPTContourBorderDimensionDirectionXForward;
    }
    else if ( point.x == rightEdge && point.y >= bottomEdge && point.y <= topEdge ) {
        borderdirection = CPTContourBorderDimensionDirectionYForward;
    }
    else if ( point.y == topEdge && point.x >= leftEdge && point.x <= rightEdge ) {
        borderdirection = CPTContourBorderDimensionDirectionXBackward;
    }
    else {
        borderdirection = CPTContourBorderDimensionDirectionYBackward;
    }
    return borderdirection;
}

-(BOOL)checkForBorderIsoCurvesInsideOuterIsoCurve:(nonnull CGContextRef)context contours:(CPTContours*)contours Plane:(NSUInteger)plane Strips:(Strips*)edgeBorderStrips leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge ascendingOrder:(BOOL)ascendingOrder useExtraLineStripList:(BOOL)useExtraLineStripList {
    BOOL isoCurveFound = NO;;
    if ( (ascendingOrder && plane  < self.isoCurvesIndices.count) || (!ascendingOrder && (NSInteger)plane >= 0) ) {
        Strips edgeStrips[4];
        for ( NSUInteger i = 0; i < 4; i++ ) {
            initStrips(&edgeStrips[i], 4);
        }
        while(ascendingOrder ? plane < self.isoCurvesIndices.count : (NSInteger)(plane) >= 0) {
            // look for all closed strips ie not touching boundary
            [self searchPlaneBorderIsoCurves:context contours:contours Plane:[[self.isoCurvesIndices objectAtIndex:plane] unsignedIntegerValue] BorderStrips:edgeStrips useExtraLineStripList:useExtraLineStripList leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
            
            for ( NSUInteger i = 0; i < 4; i++ ) {
                for( NSUInteger j = 0; j < edgeStrips[i].used; j++ ) {
                    appendStrips(&edgeBorderStrips[i], edgeStrips[i].array[j]);
                }
                clearStrips(&edgeStrips[i]);
            }
            plane = ascendingOrder ? plane + 1 : plane - 1;
        };
        for ( NSUInteger i = 0; i < 4; i++ ) {
            freeStrips(&edgeStrips[i]);
        }
    }
    for ( NSUInteger i = 0; i < 4; i++ ) {
        if ( edgeBorderStrips[i].used > 0 ) {
            isoCurveFound = YES;
            break;
        }
    }
    return isoCurveFound;
}

-(BOOL) checkForClosedIsoCurvesInsideOuterIsoCurve:(nonnull CGContextRef)context contours:(CPTContours *)contours Plane:(NSUInteger)plane Strips:(Strips*)strips ascendingOrder:(BOOL)ascendingOrder useExtraLineStripList:(BOOL)useExtraLineStripList {
    if ( (ascendingOrder && plane < self.isoCurvesIndices.count) || (!ascendingOrder && (NSInteger)plane >= 0) ) {
        while(ascendingOrder ? plane < self.isoCurvesIndices.count : (NSInteger)(plane) >= 0) {
            // look for all closed strips ie not touching boundary
            [self searchPlaneClosedIsoCurves:context contours:contours Plane:[[self.isoCurvesIndices objectAtIndex:plane] unsignedIntegerValue] ClosedStrips:strips useExtraLineStripList:useExtraLineStripList];
            plane = ascendingOrder ? plane + 1 : plane - 1;
        };
    }
    return strips->used > 0;
}

-(BOOL) checkForClosedIsoCurvesOutsideInnerIsoCurve:(nonnull CGContextRef)context contours:(CPTContours *)contours Plane:(NSUInteger)plane Strips:(Strips *)strips  ascendingOrder:(BOOL)ascendingOrder useExtraLineStripList:(BOOL)useExtraLineStripList {
    BOOL isoCurveFound = NO;
    if ( (ascendingOrder && (NSInteger)plane /*- 1*/ >= 0) || (!ascendingOrder && plane /*+ 1*/ < self.isoCurvesIndices.count) ) {
//        plane = ascendingOrder ? plane - 1 : plane + 1;
        while(ascendingOrder ?  (NSInteger)(plane) >= 0 : plane < self.isoCurvesIndices.count) {
            // look for all closed strips ie not touching boundary
            [self searchPlaneClosedIsoCurves:context contours:contours Plane:[[self.isoCurvesIndices objectAtIndex:plane] unsignedIntegerValue] ClosedStrips:strips useExtraLineStripList:useExtraLineStripList];
            plane = ascendingOrder ? plane - 1 : plane + 1;
        };
    }
    if( strips->used > 0 ) {
        isoCurveFound = YES;
    }
    return isoCurveFound;
}

-(NSUInteger) checkForIntersectingContoursAndCreateNewBorderContours:(nonnull CGContextRef)context contours:(CPTContours *)contours plane:(NSUInteger)plane {
    NSUInteger noReorganisedLineStrips = 0;
    LineStripList *pStripList;
    if ( (pStripList = [contours getStripListForIsoCurve:plane] ) != NULL ) {
        
        NSUInteger indexStart0, indexEnd0;
        NSUInteger indexStart1, indexEnd1;
        Intersections intersections;
        initIntersections(&intersections, 8);
        Intersections borderIntersections;
        initIntersections(&borderIntersections, 8);
        
        const NSUInteger diffSecondaryToPrimaryColumns = [contours getNoColumnsSecondaryGrid] / [contours getNoColumnsFirstGrid];
        const NSUInteger diffSecondaryToPrimaryRows = [contours getNoRowsSecondaryGrid] / [contours getNoRowsFirstGrid];
        NSUInteger tolerance = MAX(diffSecondaryToPrimaryColumns, diffSecondaryToPrimaryRows) / 4;
        
        // now list the strip intersections
        for (NSUInteger pos0 = 0; pos0 < pStripList->used; pos0++) {
            LineStrip *pStrip0 = &pStripList->array[pos0];
#if DEBUG
            CGMutablePathRef workingPath = CGPathCreateMutable();
            CGPoint startPoint, endPoint;
            [self createDataLinePath:&workingPath fromStrip:pStrip0 context:context contours:contours startPoint:&startPoint endPoint:&endPoint reverseOrder:NO closed:NO extraStripList:NO];
#if TARGET_OS_OSX
            NSBezierPath *bezierPath = [NSBezierPath bezierPath];
            NSBezierPath *bezierPath0 = [NSBezierPath bezierPathWithCGPath:workingPath];
            [bezierPath appendBezierPath:bezierPath0];
#else
            UIBezierPath *bezierPath = [UIBezierPath bezierPath];
            UIBezierPath *bezierPath0 = [UIBezierPath bezierPathWithCGPath:workingPath];
            [bezierPath appendPath:bezierPath0];
#endif
            CGPathRelease(workingPath);
#endif
            if ( pStrip0 != NULL && pStrip0->used > 0 ) {
                indexStart0 = pStrip0->array[0];
                indexEnd0 = pStrip0->array[pStrip0->used-1];
                if ( indexStart0 != indexEnd0 ) {  // if the start index and end index are the same then contour is closed
                    for (NSUInteger pos1 = pos0 + 1; pos1 < (NSUInteger)pStripList->used; pos1++) {
                        LineStrip *pStrip1 = &pStripList->array[pos1];
                        workingPath = CGPathCreateMutable();
                        [self createDataLinePath:&workingPath fromStrip:pStrip1 context:context contours:contours startPoint:&startPoint endPoint:&endPoint reverseOrder:NO closed:NO extraStripList:NO];
#if TARGET_OS_OSX
                        NSBezierPath *bezierPath1 = [NSBezierPath bezierPathWithCGPath:workingPath];
                        [bezierPath appendBezierPath:bezierPath1];
#else
                        UIBezierPath *bezierPath1 = [UIBezierPath bezierPathWithCGPath:workingPath];
                        [bezierPath appendPath:bezierPath1];
#endif
                        CGPathRelease(workingPath);
                        if (pStrip1 != NULL && pStrip1->used > 0 ) {
                            indexStart1 = pStrip1->array[0];
                            indexEnd1 = pStrip1->array[pStrip1->used-1];
                            if ( indexStart1 != indexEnd1 ) {
                                [contours intersectionsWithAnotherList:pStrip0 Other:pStrip1 Tolerance:(NSUInteger)tolerance];
                                IndicesList *indices = [contours getIntersectionIndicesList];
                                if ( indices->used > 0 ) {
                                    for ( NSUInteger pos = 0; pos < indices->used; pos++) {
                                        Indices indexes = indices->array[pos];
                                        [self insertIntersection:&intersections index:indexes.index jndex:indexes.jndex pStrip0:pStrip0 pStrip1:pStrip1 useStrips:YES context:context contours:contours];
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        sortIntersectionsByPointXCoordinate(&intersections);
        removeDuplicatesIntersections(&intersections, 5.0);
        
        
        if ( intersections.used > 0 ) {
            // now list the border intersections
            for (NSUInteger pos0 = 0; pos0 < pStripList->used; pos0++) {
                LineStrip *pStrip0 = &pStripList->array[pos0];
                if ( pStrip0 != NULL && pStrip0->used > 0 ) {
                    indexStart0 = pStrip0->array[0];
                    indexEnd0 = pStrip0->array[ pStrip0->used - 1];
                    if ( indexStart0 != indexEnd0 ) {  // if the start index and end index are the same then contour is closed
                        [self insertIntersection:&borderIntersections index:indexStart0 jndex:indexStart0 pStrip0:pStrip0 pStrip1:NULL  useStrips:NO context:context contours:contours];
                        [self insertIntersection:&borderIntersections index:indexEnd0 jndex:indexEnd0 pStrip0:pStrip0 pStrip1:NULL useStrips:NO context:context contours:contours];
                    }
                }
            }
            sortIntersectionsByPointXCoordinate(&borderIntersections);
            // make sure we haven't picked up any border intersections
            removeSimilarIntersections(&intersections, &borderIntersections);
            
            NSUInteger index;
            CGPoint borderCorners[4];
            // corners could be contour border Intersections so check on insertCorner
            if ( (index = [self insertCorner:&borderIntersections x:[contours getLimits][0] y:[contours getLimits][2] context:context contours:contours]) != NSNotFound) {
                borderCorners[0] = borderIntersections.array[index].point;
            }
            if ( (index = [self insertCorner:&borderIntersections x:[contours getLimits][1] y:[contours getLimits][2] context:context contours:contours]) != NSNotFound) {
                borderCorners[1] = borderIntersections.array[index].point;
            }
            if ( (index = [self insertCorner:&borderIntersections x:[contours getLimits][1] y:[contours getLimits][3] context:context contours:contours]) != NSNotFound) {
                borderCorners[2] = borderIntersections.array[index].point;
            }
            if ( (index = [self insertCorner:&borderIntersections x:[contours getLimits][0] y:[contours getLimits][3] context:context contours:contours]) != NSNotFound) {
                borderCorners[3] = borderIntersections.array[index].point;
            }
            
            for( NSUInteger i = 0; i < intersections.used; i++) {
                intersections.array[i].intersectionIndex = i;
            }
            sortIntersectionsByPointXCoordinate(&borderIntersections);
            for( NSUInteger i = 0; i < borderIntersections.used; i++) {
                borderIntersections.array[i].intersectionIndex = i + (NSUInteger)intersections.used;
            }
            
            noReorganisedLineStrips = [self reorganiseIntersectingContours:&intersections borderIntersections:&borderIntersections context:context contours:contours plane:plane borderCorners:borderCorners];
        }
        freeIntersections(&intersections);
        freeIntersections(&borderIntersections);
    }
    return noReorganisedLineStrips;
}

-(NSUInteger) checkForMirroredContoursAndCreateNewBorderContours:(nonnull CGContextRef)context contours:(CPTContours *)contours plane:(NSUInteger)plane {
    LineStripList *pStripList = [contours getStripListForIsoCurve:plane];
    LineStrip *pStrip0 = NULL;
    LineStrip *pStrip1 = NULL;
    LineStrip strip1, newStrip0, newStrip1, newPStrip0, newPStrip1;
    NSUInteger index[4];
    CGFloat x[4], y[4];
    
    NSUInteger noReorganisedLineStrips = 0;
    // now list the strip intersections
    for (NSUInteger pos0 = 0; pos0 < pStripList->used - 1; pos0++) {
        pStrip0 = &pStripList->array[pos0];
        pStrip1 = &pStripList->array[pos0 + 1];
        if ( pStrip0 != NULL && pStrip0->used > 1 && pStrip1 != NULL && pStrip1->used > 1 && pStrip0->used == pStrip1->used ) {
            index[0] = pStrip0->array[0];
            x[0] = (CGFloat)[contours getXAt:index[0]];
            y[0] = (CGFloat)[contours getYAt:index[0]];
            index[1] = pStrip0->array[pStrip0->used - 1];
            x[1] = (CGFloat)[contours getXAt:index[1]];
            y[1] = (CGFloat)[contours getYAt:index[1]];
            if ( x[0] == x[1] || y[0] == y[1] ) {
                continue;
            }
            index[2] = pStrip1->array[0];
            x[2] = (CGFloat)[contours getXAt:index[2]];
            y[2] = (CGFloat)[contours getYAt:index[2]];
            index[3] = pStrip1->array[pStrip1->used - 1];
            x[3] = (CGFloat)[contours getXAt:index[3]];
            y[3] = (CGFloat)[contours getYAt:index[3]];
            if ( x[2] == x[3] || y[2] == y[3] ) {
                continue;
            }
            if ( (x[0] == x[2] && x[1] == x[3]) || (y[0] == y[2] && y[1] == y[3]) ) {
                continue;
            }
            CGPoint *pts0 = (CGPoint*)calloc(pStrip0->used, sizeof(CGPoint));
            CGPoint *pts1 = (CGPoint*)calloc(pStrip1->used, sizeof(CGPoint));
            initLineStrip(&strip1, pStrip1->used);
            copyLineStrip(pStrip1, &strip1);
            reverseLineStrip(&strip1);
            BOOL skip = NO;
            LineStrip *ptr1[2] = { pStrip1, &strip1 };
            NSUInteger count = 0;
            for (NSUInteger j = 0; j < 2; j++ ) {
                count = 0;
                skip = NO;
                for ( NSUInteger pos2 = 0; pos2 < pStrip0->used; pos2++ ) {
                    index[0] = pStrip0->array[pos2];
                    x[0] = (CGFloat)[contours getXAt:index[0]];
                    y[0] = (CGFloat)[contours getYAt:index[0]];
                    index[1] = ptr1[j]->array[pos2];
                    x[1] = (CGFloat)[contours getXAt:index[1]];
                    y[1] = (CGFloat)[contours getYAt:index[1]];
                    if ( (x[0] + x[1]) / 2 != 0.0 && (y[0] + y[1]) / 2 != 0.0 ) {
                        skip = YES;
                        break;
                    }
                    pts0[pos2] = CGPointMake(x[0], y[0]);
                    pts1[pos2] = CGPointMake(x[1], y[1]);
                    count++;
                }
                if ( !skip && count == pStrip0->used ) {
                    initLineStrip(&newStrip0, pStrip0->used);
                    initLineStrip(&newStrip1, pStrip0->used);
                    CGPoint line[2] = { CGPointMake(([self.limits[0] doubleValue] + [self.limits[1] doubleValue]) / 2.0, [self.limits[2] doubleValue]), CGPointMake(([self.limits[0] doubleValue] + [self.limits[1] doubleValue]) / 2.0, [self.limits[3] doubleValue]) };
                    for ( NSUInteger pos2 = 0; pos2 < pStrip0->used; pos2++ ) {
                        pts0[pos2] = [self mirrorPoint:pts0[pos2] aboutALine:line];
                        pts1[pos2] = [self mirrorPoint:pts1[pos2] aboutALine:line];
                        index[0] = [contours getIndexAtX:pts0[pos2].x Y:pts0[pos2].y];
                        appendLineStrip(&newStrip0, index[0]);
                        index[1] = [contours getIndexAtX:pts1[pos2].x Y:pts1[pos2].y];
                        appendLineStrip(&newStrip1, index[1]);
                    }
                    // clear any Strips in contours->extraIsoCurvesLists at isoCurve
                    LineStripList *pExtraList = [contours getExtraIsoCurvesListsAtIsoCurve:plane];
                    if ( pExtraList->used > 0 ) {
                        clearLineStripList(pExtraList);
                    }
                    initLineStrip(&newPStrip0, pStrip0->used);
                    copyLineStrip(pStrip0, &newPStrip0);
                    appendLineStripList(pExtraList, newPStrip0);
                    appendLineStripList(pExtraList, newStrip0);
                    initLineStrip(&newPStrip1, pStrip1->used);
                    copyLineStrip(pStrip1, &newPStrip1);
                    appendLineStripList(pExtraList, newPStrip1);
                    appendLineStripList(pExtraList, newStrip1);
                    noReorganisedLineStrips = 4;
                    freeLineStrip(&newStrip0);
                    freeLineStrip(&newStrip1);
                    freeLineStrip(&newPStrip0);
                    freeLineStrip(&newPStrip1);
                }
            }
            free(pts0);
            free(pts1);
            freeLineStrip(&strip1);

        }
    }
   
    return noReorganisedLineStrips;
}

-(CGPoint) rotatePoint:(CGPoint)target aroundOrigin:(CGPoint)origin rotation:(CGFloat)rotation {
    CGFloat dx = target.x - origin.x;
    CGFloat dy = target.y - origin.y;
    CGFloat radius = sqrt(dx * dx + dy * dy);
    CGFloat azimuth = atan2(dy, dx); // in radians
    CGFloat newAzimuth = azimuth + rotation;
    return CGPointMake(origin.x + radius * cos(newAzimuth), origin.y + radius * sin(newAzimuth));
}
//// 2D Points P=[x,y] and R are points on line,
//// Q is point for which we want to find reflection
//function mirror(Q,[P,R]) {
//  let [vx,vy]= [ R[0]-P[0], R[1]-P[1] ];
//  let [x,y]  = [ P[0]-Q[0], P[1]-Q[1] ];
//  let r= 1/(vx*vx+vy*vy);
//  return [ Q[0] +2*(x -x*vx*vx*r -y*vx*vy*r),
//           Q[1] +2*(y -y*vy*vy*r -x*vx*vy*r)  ];
//}

// 2D Points P=[x,y] and R are points on line,
// Q is point for which we want to find reflection
-(CGPoint) mirrorPoint:(CGPoint)point aboutALine:(CGPoint*)line {
    CGFloat vx = line[1].x - line[0].x;
    CGFloat vy = line[1].y - line[0].y;
    CGFloat x = line[0].x - point.x;
    CGFloat y = line[0].y - point.y;
    CGFloat r = 1 / (vx * vx + vy * vy);
    return CGPointMake(point.x + 2.0 * (x - x * vx * vx * r - y * vx * vy * r), point.y + 2.0 * (y - y * vy * vy * r - x * vx * vy * r));
}



-(NSUInteger)reorganiseIntersectingContours:(Intersections* _Nonnull)pIntersections borderIntersections:(Intersections* _Nonnull)pBorderIntersections context:(nonnull CGContextRef)context contours:(CPTContours * _Nonnull)contours plane:(NSUInteger)plane borderCorners:(CGPoint* _Nonnull)borderCorners {
    
    sortIntersectionsByPointXCoordinate(pIntersections);
    
    // clear any Strips in contours->extraIsoCurvesLists at isoCurve
    LineStripList *pExtraList = [contours getExtraIsoCurvesListsAtIsoCurve:plane];
    if ( pExtraList->used > 0 ) {
        clearLineStripList(pExtraList);
    }
    
//    // now let's get the surrounding intersection points of these internal intersection points
//    _CPTHull *Hull = [[_CPTHull alloc] init];
//    [Hull quickConvexHullOnIntersections:pIntersections];
//
//    NSUInteger index;
//    Intersections outerIntersections;
//    initIntersections(&outerIntersections, [Hull hullpoints]->used);
//    for( NSUInteger i = 0; i < (NSUInteger)[Hull hullpoints]->used; i++) {
//        if ( (index = searchForIndexIntersection(pIntersections, [Hull hullpoints]->array[i].index)) != NSNotFound ) {
//            appendIntersections(&outerIntersections, pIntersections->array[index]);
//        }
//    }
//    Hull = nil;
    
//    sortIntersectionsByOrderAntiClockwiseFromBottomLeftCorner(pBorderIntersections, borderCorners, 0.01);
    
    // internal Intersection Indices will be from 0-maxInternal#-1, border from maxInternal# to ??
    Intersections allIntersections;
    initIntersections(&allIntersections, pIntersections->used + pBorderIntersections->used);
    for( NSUInteger i = 0; i < (NSUInteger)pIntersections->used; i++) {
        appendIntersections(&allIntersections, pIntersections->array[i]);
    }
    for( NSUInteger i = 0; i < (NSUInteger)pBorderIntersections->used; i++) {
        appendIntersections(&allIntersections, pBorderIntersections->array[i]);
    }
    
    LineStrip interSectionIndices, alternativeInterSectionIndices;
    initLineStrip(&interSectionIndices, pIntersections->used);
    initLineStrip(&alternativeInterSectionIndices, pIntersections->used);
    for ( NSUInteger i = 0; i < (NSUInteger)pIntersections->used; i++) {
        appendLineStrip(&interSectionIndices, pIntersections->array[i].index);
        appendLineStrip(&alternativeInterSectionIndices, pIntersections->array[i].jndex);
    }
    
    // unweighted bidirectional BFS
    _CPTContourGraph *graph = [[_CPTContourGraph alloc] initWithNoNodes:(NSUInteger)(pIntersections->used + pBorderIntersections->used)];
    for( NSUInteger i = 0, j = 1; i < (NSUInteger)pBorderIntersections->used; i++, j++) {
        if ( j == (NSUInteger)pBorderIntersections->used ) {
            j = 0;
        }
        if( pBorderIntersections->array[i].pStrip0 != NULL )  {
            for ( NSUInteger l = j + 1; l < pBorderIntersections->used; l++ ) {
                if ( [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:pBorderIntersections->array[i].pStrip0 Index:pBorderIntersections->array[i].index Jndex:pBorderIntersections->array[l].index IndicesList:&interSectionIndices JndicesList:&alternativeInterSectionIndices] ) {
                    [graph addEdgeFrom:i + /*outerIntersections.used*/pIntersections->used to:l + /*outerIntersections.used*/pIntersections->used];
                }
            }
        }
        // Inner intersections have contour index Index & Jndex, they may not be the same as 2 contour lines may have intersected
        // with a tolerance
        for ( NSUInteger k = 0; k < /*outerIntersections.used*/pIntersections->used; k++ ) {

            if( [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:pIntersections->array[k].pStrip0 Index:pIntersections->array[k].index Jndex:pBorderIntersections->array[i].index IndicesList:&interSectionIndices JndicesList:&alternativeInterSectionIndices] || [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:pIntersections->array[k].pStrip1 Index:pIntersections->array[k].index Jndex:pBorderIntersections->array[i].index IndicesList:&interSectionIndices JndicesList:&alternativeInterSectionIndices] || [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:pIntersections->array[k].pStrip0 Index:pIntersections->array[k].jndex Jndex:pBorderIntersections->array[i].index IndicesList:&interSectionIndices JndicesList:&alternativeInterSectionIndices] || [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:pIntersections->array[k].pStrip1 Index:pIntersections->array[k].jndex Jndex:pBorderIntersections->array[i].index IndicesList:&interSectionIndices JndicesList:&alternativeInterSectionIndices] ) {
                    [graph addEdgeFrom:i + pIntersections->used to:k];
            }
        }
    }
    for ( NSUInteger i = 0; i < pIntersections->used; i++ ) {
        for( NSUInteger j = i + 1; j < pIntersections->used; j++ ) {
            if ( [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:pIntersections->array[i].pStrip0 Index:pIntersections->array[i].index Jndex:pIntersections->array[j].index IndicesList:&interSectionIndices JndicesList:&alternativeInterSectionIndices] || [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:pIntersections->array[i].pStrip1 Index:pIntersections->array[i].index Jndex:pIntersections->array[j].index IndicesList:&interSectionIndices JndicesList:&alternativeInterSectionIndices] ) {
                [graph addEdgeFrom:i to:j];
            }
        }
    }
    freeLineStrip(&interSectionIndices);
    freeLineStrip(&alternativeInterSectionIndices);
    // start a first border intersection in btm left corner, then iterate around the edges back to start
    // find each shape, some shapes will be repeats so eliminate them from the list.
    sortIntersectionsByOrderAntiClockwiseFromBottomLeftCorner(pBorderIntersections, borderCorners, 5.0);
    
    LineStripList paths;
    initLineStripList(&paths, 8);

    BOOL pathFound = YES;
    NSUInteger start = 0;
    if( pBorderIntersections->array[0].isCorner ) { // which it probably always will be
        start = 1;
    }
    for( NSUInteger i = start, j = start + 1; i < (NSUInteger)pBorderIntersections->used; i++, j++) {
        if ( j == (NSUInteger)pBorderIntersections->used ) {
            j = 0;
        }
        pathFound = YES;
        if ( [graph biDirSearchFromSource:pBorderIntersections->array[i].intersectionIndex toTarget:pBorderIntersections->array[j].intersectionIndex paths:&paths] == NSNotFound ) {
//                NSLog(@"Path don't exist between %ld and %ld\n", pBorderIntersections->array[i].intersectionIndex, pBorderIntersections->array[j].intersectionIndex);
            pathFound = NO;
            //            if( !(pBorderIntersections->array[i].isCorner || pBorderIntersections->array[j].isCorner) ) {
            NSUInteger k = j + 1, count = 0;
            if ( k == pBorderIntersections->used ) {
                k = 0;
            }
            while(  count < pBorderIntersections->used ) {
                pathFound = YES;
                if ( [graph biDirSearchFromSource:pBorderIntersections->array[i].intersectionIndex toTarget:pBorderIntersections->array[k].intersectionIndex paths:&paths] == NSNotFound ) {
//                        NSLog(@"Path don't exist between %ld and %ld\n", pBorderIntersections->array[i].intersectionIndex, pBorderIntersections->array[k].intersectionIndex);
                    pathFound = NO;
                    k++;
                    count++;
                    if ( k == pBorderIntersections->used ) {
                        k = 0;
                    }
                }
                else {
                    break;
                }
            }
        }
        if ( !pathFound ) {
            NSUInteger k = j;
            if ( pBorderIntersections->array[j].isCorner ) {
                k++;
            }
            if( pBorderIntersections->array[i].pStrip0 == pBorderIntersections->array[k].pStrip0 ) {
                LineStrip path;
                initLineStrip(&path, 2);
                if( pBorderIntersections->array[i].index < pBorderIntersections->array[k].index ) {
                    appendLineStrip(&path, pBorderIntersections->array[k].intersectionIndex);
                    appendLineStrip(&path, pBorderIntersections->array[i].intersectionIndex);
                }
                else {
                    appendLineStrip(&path, pBorderIntersections->array[i].intersectionIndex);
                    appendLineStrip(&path, pBorderIntersections->array[k].intersectionIndex);
                }
                appendLineStripList(&paths, path);
            }
        }
    }
    
    // now do the inner nodes
    if ( pIntersections->used > 1 ) {
        Intersections temp;
        initIntersections(&temp, pIntersections->used);
        for ( NSUInteger i = 0; i < pIntersections->used; i++ ) {
            copyIntersections(pIntersections, &temp);
            removeIntersectionsAtIndex(&temp, (size_t)i);
            closestKIntersections(&temp, pIntersections->array[i]);
    //        NSUInteger *nearestIndices = (NSUInteger*)calloc(2, sizeof(NSUInteger));
    //        NSUInteger noNearestIndices = searchForNearestInnerIndicesIntersection(pIntersections, pIntersections->array[i].intersectionIndex, &nearestIndices);
            NSUInteger k;
            for ( NSUInteger j = 0; j < 2; j++ ) {
                k = searchForIndexIntersection(pIntersections, temp.array[j].intersectionIndex);
                if ( [graph biDirSearchFromSource:i toTarget:k paths:&paths] == NSNotFound ) {
                    NSLog(@"Path don't exist between %ld and %ld\n", pIntersections->array[i].intersectionIndex, temp.array[j].intersectionIndex);
                }
                else {
                    if ( paths.array[paths.used - 1].used != 4 ) {
                        removeLineStripListAtIndex(&paths, paths.used - 1);
                    }
                }
            }
    //        free(nearestIndices);
        }
        freeIntersections(&temp);
    }
    
    // initialise variable
    CGPoint *vertices = (CGPoint*)calloc(1, sizeof(CGPoint));
    NSUInteger countVertices = 0;
    CGPoint vertex;
    Centroids centroids;
    initCentroids(&centroids, 8);
    
    CPTContourPolygonStatus status;
    Intersections intersections;
    initIntersections(&intersections, 8);
    CGFloat grad0, grad1;
    BOOL breakOut = NO;
    for( NSUInteger i = 0; i < paths.used; i++ ) {
        NSUInteger k = 0;
        breakOut = NO;
        for( NSUInteger j = 0; j < paths.array[i].used; j++ ) {
            if( k > 0 && k < paths.array[i].used - 1 ) { // check if 3 nodes on a straight line and rid if so
                grad0 = (allIntersections.array[paths.array[i].array[j]].point.y - allIntersections.array[paths.array[i].array[j-1]].point.y) / (allIntersections.array[paths.array[i].array[j]].point.x - allIntersections.array[paths.array[i].array[j-1]].point.x);
                grad1 = (allIntersections.array[paths.array[i].array[j+1]].point.y - allIntersections.array[paths.array[i].array[j]].point.y) / (allIntersections.array[paths.array[i].array[j+1]].point.x - allIntersections.array[paths.array[i].array[j]].point.x);
                if ( fabs(grad0 - grad1) < 0.001 ) {
                    breakOut = YES;
                    break;
                }
            }
            appendIntersections(&intersections, allIntersections.array[paths.array[i].array[j]]);
            vertex = allIntersections.array[paths.array[i].array[j]].point;
            vertices[countVertices] = vertex;
            countVertices++;
            vertices = (CGPoint*)realloc(vertices, (size_t)(countVertices+1) * sizeof(CGPoint));
            k++;
        }
        if ( breakOut ) {
            NSLog(@"Status: can't create shape as 3 nodes in a line, but will use original LineStrip");
            for ( NSUInteger l = 0, m = 1; l < paths.array[i].used; l++, m++ ) {
                if ( m == paths.array[i].used ) {
                    m = 0;
                }
                if ( allIntersections.array[paths.array[i].array[l]].pStrip0 == allIntersections.array[paths.array[i].array[m]].pStrip0) {
                    LineStrip element;
                    initLineStrip(&element, allIntersections.array[paths.array[i].array[l]].pStrip0->used);
                    copyLineStrip(allIntersections.array[paths.array[i].array[l]].pStrip0, &element);
                    appendLineStripList(pExtraList, element);
                    break;
                }
                else if (allIntersections.array[paths.array[i].array[l]].pStrip1 == allIntersections.array[paths.array[i].array[m]].pStrip1) {
                    LineStrip element;
                    initLineStrip(&element, allIntersections.array[paths.array[i].array[l]].pStrip1->used);
                    copyLineStrip(allIntersections.array[paths.array[i].array[l]].pStrip1, &element);
                    appendLineStripList(pExtraList, element);
                    break;
                }
            }
        }
        else {
            status = [self createPolygonFromIntersections:intersections.array Vertices:vertices noVertices:paths.array[i].used Centroids:&centroids isoCurve:plane contours:contours];
            NSLog(@"Status: %d", status);
        }
        countVertices = 0;
        vertices = (CGPoint*)realloc(vertices, (size_t)(countVertices+1) * sizeof(CGPoint));
        clearIntersections(&intersections);
        freeLineStrip(&paths.array[i]);
    }
    freeLineStripList(&paths);
    free(vertices);
    freeIntersections(&intersections);
    
    // Weighted search using Dijkstra algorithm
//    NSUInteger noVertices = (NSUInteger)(outerIntersections.used + pBorderIntersections->used);
//    CGFloat** adjMatrix = (CGFloat**)calloc((size_t)noVertices, sizeof(CGFloat*));
//    for( NSUInteger i = 0; i < noVertices; i++ ) {
//        adjMatrix[i] = (CGFloat*)calloc((size_t)noVertices, sizeof(CGFloat));
//        for( NSUInteger j = 0; j < noVertices; j++ ) {
//            adjMatrix[i][j] = 0.0;
//        }
//    }
//
//    for( NSUInteger i = 0, j = 1, k = (NSUInteger)pBorderIntersections->used - 1; i < (NSUInteger)pBorderIntersections->used-1; i++, j++, k++) {
//        if ( j == (NSUInteger)pBorderIntersections->used ) {
//            j = 0;
//        }
//        if ( k == (NSUInteger)pBorderIntersections->used ) {
//            k = 0;
//        }
//        adjMatrix[i+outerIntersections.used][j+outerIntersections.used] = sqrt(pow(pBorderIntersections->array[i].point.x - pBorderIntersections->array[j].point.x, 2.0) + pow(pBorderIntersections->array[i].point.y - pBorderIntersections->array[j].point.y , 2.0));
//
//        if( pBorderIntersections->array[i].pStrip0 != NULL )  {
//            for ( NSUInteger l = 0; l < pBorderIntersections->used; l++ ) {
//                if ( l != i && [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:pBorderIntersections->array[i].pStrip0 Index:pBorderIntersections->array[i].index Jndex:pBorderIntersections->array[l].index IndicesList:&interSectionIndices] ) {
//                    adjMatrix[k+outerIntersections.used][i+outerIntersections.used] = sqrt(pow(pBorderIntersections->array[i].point.x - pBorderIntersections->array[l].point.x, 2.0) + pow(pBorderIntersections->array[i].point.y - pBorderIntersections->array[l].point.y , 2.0));
//                    adjMatrix[i+outerIntersections.used][k+outerIntersections.used] = adjMatrix[k+outerIntersections.used][i+outerIntersections.used];
//                }
//            }
//        }
//
//        for ( NSUInteger l = 0; l < outerIntersections.used; l++ ) {
//            if( [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:outerIntersections.array[l].pStrip0 Index:pBorderIntersections->array[i].index Jndex:outerIntersections.array[l].index IndicesList:&interSectionIndices] || [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:outerIntersections.array[l].pStrip1 Index:pBorderIntersections->array[i].index Jndex:outerIntersections.array[l].index IndicesList:&interSectionIndices] ) {
////                CGFloat P12 = sqrt(pow(pBorderIntersections->array[k].point.x - pBorderIntersections->array[i].point.x, 2.0) + pow(pBorderIntersections->array[k].point.y - pBorderIntersections->array[i].point.y, 2.0));
////                CGFloat P13 = sqrt(pow(pBorderIntersections->array[k].point.x - outerIntersections.array[l].point.x, 2.0) + pow(pBorderIntersections->array[k].point.y - outerIntersections.array[l].point.y, 2.0));
////                CGFloat P23 = sqrt(pow(pBorderIntersections->array[i].point.x - outerIntersections.array[l].point.x, 2.0) + pow(pBorderIntersections->array[i].point.y - outerIntersections.array[l].point.y, 2.0));
////                CGFloat subtendedAngle = acos((P12 * P12 + P13 * P13 + P23 * P23) / 2 / P12 / P13);
////                if ( subtendedAngle <= M_PI_2 ) {
//                    adjMatrix[i+outerIntersections.used][l] = sqrt(pow(pBorderIntersections->array[i].point.x - outerIntersections.array[l].point.x, 2.0) + pow(pBorderIntersections->array[i].point.y - outerIntersections.array[l].point.y , 2.0));
////                }
//            }
//        }
//    }
//    for ( NSUInteger l = 0; l < outerIntersections.used; l++ ) {
//        for( NSUInteger m = 0; m < outerIntersections.used; m++ ) {
//            if ( m != l && ([contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:outerIntersections.array[l].pStrip0 Index:outerIntersections.array[l].index Jndex:outerIntersections.array[m].index IndicesList:&interSectionIndices] || [contours checkForDirectConnectWithoutOtherIndicesBetween2IndicesInAStrip:outerIntersections.array[l].pStrip1 Index:outerIntersections.array[l].index Jndex:outerIntersections.array[m].index IndicesList:&interSectionIndices]) ) {
//                adjMatrix[l][m] = sqrt(pow(outerIntersections.array[l].point.x - outerIntersections.array[m].point.x, 2.0) + pow( outerIntersections.array[l].point.y - outerIntersections.array[m].point.y , 2.0));
//                adjMatrix[m][l] = adjMatrix[l][m];
//            }
//        }
//    }
//    [self DijkstraWithAdjacency:adjMatrix noVertices:(NSUInteger)(outerIntersections.used + pBorderIntersections->used) startNode:10];
//
//    for( NSUInteger i = 0; i < noVertices; i++ ) {
//        free(adjMatrix[i]);
//    }
//    free(adjMatrix);
    
    // now iterated through the border intersection in anticlockwise direction (contour to border meeting points and corners)
    // start at the bottom left corner as the first vertex and see if there is a direct contour line to any of the outer inside
    // intersections establish through the convex hull method. If not, add next border intersection in anticlockwise direction to
    // the vertices array, check whether this vertex has direct contour line to any of the outer inside intersections, iterating
    // through till one is found

    freeCentroids(&centroids);

    return (NSUInteger)pExtraList->used;
}


-(CPTContourPolygonStatus)createPolygonFromIntersections:(Intersection*)intersections Vertices:(CGPoint*)vertices noVertices:(NSUInteger)noVertices Centroids:(Centroids*)pCentroids isoCurve:(NSUInteger)plane contours:(CPTContours *)contours {
    Centroid centroid;
    qsort(pCentroids->array, pCentroids->used, sizeof(Centroid), compareCentroidsByXCoordinate);
    centroid.centre = [self findCentroidOfShape:vertices noPoints:noVertices];
    centroid.noVertices = noVertices;
    if( bsearch(&centroid, pCentroids->array, pCentroids->used, sizeof(Centroid), compareCentroids) != NULL ) {
        return CPTContourPolygonStatusAlreadyExists;
    }
    else {
        [self createNPointShapeFromIntersections:intersections noVertices:noVertices isoCurve:plane contours:contours];
        appendCentroids(pCentroids, centroid);
        return CPTContourPolygonStatusCreated;
    }
}

-(void)insertIntersection:(Intersections*)pIntersections index:(NSUInteger)index jndex:(NSUInteger)jndex pStrip0:(LineStrip *)pStrip0 pStrip1:(LineStrip *)pStrip1 useStrips:(BOOL)useStrips context:(nonnull CGContextRef)context contours:(CPTContours *)contours {
    CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
    Intersection newIntersection;
    newIntersection.index = index;
    newIntersection.jndex = jndex;
    newIntersection.pStrip0 = pStrip0;
    newIntersection.pStrip1 = pStrip1;
    CGPoint point = CGPointMake(([contours getXAt:index] - thePlotSpace.xRange.locationDouble) * self.scaleX, ([contours getYAt:index] - thePlotSpace.yRange.locationDouble) * self.scaleY);
    newIntersection.point = point;
    newIntersection.useStrips = useStrips;
    newIntersection.isCorner = NO;
    newIntersection.usedCount = 0;
    newIntersection.intersectionIndex = NSNotFound;
    newIntersection.dummy = 0;
    appendIntersections(pIntersections, newIntersection);
}

-(NSUInteger)insertCorner:(Intersections*)pIntersections x:(double)x y:(double)y context:(nonnull CGContextRef)context contours:(CPTContours *)contours {
    CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
    
    NSUInteger index = [contours getIndexAtX:x Y:y];
    double _x = (x - thePlotSpace.xRange.locationDouble) * self.scaleX;
    double _y = (y - thePlotSpace.yRange.locationDouble) * self.scaleY;
    CGPoint point = CGPointMake(_x, _y);
    NSUInteger check;
    if ( (check = searchForPointIntersection(pIntersections, point, 1.0)) == NSNotFound ) {
        Intersection newIntersection;
        newIntersection.index = index;
        newIntersection.jndex = index;
        newIntersection.pStrip0 = NULL;
        newIntersection.pStrip1 = NULL;
        newIntersection.point = point;
        newIntersection.useStrips = NO;
        newIntersection.isCorner = YES;
        newIntersection.usedCount = 0;
        newIntersection.intersectionIndex = NSNotFound;
        newIntersection.dummy = 0;
        if( containsIntersection(pIntersections, newIntersection) == NSNotFound ) {
            appendIntersections(pIntersections, newIntersection);
            check = (NSUInteger)pIntersections->used-1;
        }
    }
    else {
        pIntersections->array[check].isCorner = NO;
    }
    return check;
}

-(void)createNPointShapeFromIntersections:(Intersection*)intersections noVertices:(NSUInteger)noVertices isoCurve:(NSUInteger)plane contours:(CPTContours *)contours {
    // use the contours extraLineStripList to created new shapes
    LineStripList *pReOrganisedLineStripList = [contours getExtraIsoCurvesListsAtIsoCurve:plane];
    
    LineStripList stripList0, stripList1;
    initLineStripList(&stripList0, 8);
    initLineStripList(&stripList1, 8);
    NSUInteger *indexes = (NSUInteger*)malloc((size_t)noVertices * sizeof(NSUInteger));
    NSUInteger *jndexes = (NSUInteger*)malloc((size_t)noVertices * sizeof(NSUInteger));
    NSUInteger count = 0;
    CGFloat deltaX, deltaY;
    BOOL onBoundary1, onBoundary2, anyOnBoundary1 = NO, anyOnBoundary2 = NO;
    NSUInteger m = 0, n = 1;
    while( m < noVertices ) {
        if ( n == noVertices ) {
            n = 0;
        }
        if ( !intersections[m].isCorner ) {
           // now we have established a shape get rid of boundary nodes unless start/end of new contour Strip
            onBoundary1 = [contours isNodeOnBoundary:intersections[m].index];
            onBoundary2 = [contours isNodeOnBoundary:intersections[n].index];
            anyOnBoundary1 |= onBoundary1;
            anyOnBoundary2 |= onBoundary2;
            deltaX = fabs(intersections[m].point.x - intersections[n].point.x);
            deltaY = fabs(intersections[m].point.y - intersections[n].point.y);
            if ( intersections[m].pStrip0 != NULL ) {
                appendLineStripList(&stripList0, *intersections[m].pStrip0);
            }
            else {
                LineStrip element;
                initLineStrip(&element, 1);
                appendLineStripList(&stripList0, element);
            }
            if( intersections[m].pStrip1 != NULL ) {
                appendLineStripList(&stripList1, *intersections[m].pStrip1);
            }
            else {
                LineStrip element;
                initLineStrip(&element, 1);
                appendLineStripList(&stripList1, element);
            }
            indexes[count] = intersections[m].index;
            jndexes[count] = intersections[m].jndex;
            count++;
            if ( (deltaX == 0.0 || deltaY == 0.0) && onBoundary1 && onBoundary2 && count > 1 ) {
                [contours createNPointShapeFromIntersectionPtToLineStripList:pReOrganisedLineStripList striplist1:&stripList0 striplist2:&stripList1 indices:indexes jndices:jndexes NPoints:count isoCurve:plane];
                count = 0;
            }
        }
        m++;
        n++;
    }

    if ( count > 1 ) {
        if ( !(anyOnBoundary1 || anyOnBoundary2) ) {
            indexes = (NSUInteger*)realloc(indexes, (size_t)(noVertices + 1) * sizeof(NSUInteger));
            jndexes = (NSUInteger*)realloc(jndexes, (size_t)(noVertices + 1) * sizeof(NSUInteger));
            indexes[count] = intersections[0].index;
            jndexes[count] = intersections[0].jndex;
            count++;
        }
        [contours createNPointShapeFromIntersectionPtToLineStripList:pReOrganisedLineStripList striplist1:&stripList0 striplist2:&stripList1 indices:indexes jndices:jndexes NPoints:count isoCurve:plane];
    }
    freeLineStripList(&stripList0);
    freeLineStripList(&stripList1);
    free(indexes);
    free(jndexes);
}

-(CGPoint)findCentroidOfShape:(CGPoint*)points noPoints:(NSUInteger)nPts {
    CGPoint off = points[0];
    CGFloat twicearea = 0;
    CGFloat x = 0;
    CGFloat y = 0;
    CGPoint p1, p2;
    CGFloat f;
    for (NSUInteger i = 0, j = nPts - 1; i < nPts; j = i++) {
        p1 = points[i];
        p2 = points[j];
        f = (p1.x - off.x) * (p2.y - off.y) - (p2.x - off.x) * (p1.y - off.y);
        twicearea += f;
        x += (p1.x + p2.x - 2 * off.x) * f;
        y += (p1.y + p2.y - 2 * off.y) * f;
    }

    f = twicearea * 3;

    return CGPointMake(x / f + off.x, y / f + off.y);
}

#pragma mark -
#pragma mark Discontinuities

-(NSUInteger)pathsDiscontinuityRegions:(CGMutablePathRef**)boundaryLimitsDataLinePaths context:(CGContextRef)context contours:(CPTContours*)contours discontinuityStrips:(Strips*)discontinuityStrips leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    
//#if DEBUG
//    CPTPlotSymbol *symbol = [[CPTPlotSymbol alloc] init];
//    symbol.fill               = [CPTFill fillWithColor:[CPTColor darkGrayColor]];
//    symbol.size               = CGSizeMake(2.0, 2.0);
//#endif
    NSUInteger noClusters = 0;
    CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
    Discontinuities *_discontinuities = [contours getDiscontinuities];
    if ( _discontinuities->used > 0 ) {
        size_t discontinuousCount = _discontinuities->used;
        self.hasDiscontinuity = YES;
        CGPoint *discontinuousPoints = (CGPoint*)malloc(_discontinuities->used * sizeof(CGPoint));
        for ( NSUInteger i = 0; i < (NSUInteger)_discontinuities->used; i++ ) {
            discontinuousPoints[i] = CGPointMake(([contours getXAt:_discontinuities->array[i]] - thePlotSpace.xRange.locationDouble) * self.scaleX, ([contours getYAt:_discontinuities->array[i]] - thePlotSpace.yRange.locationDouble) * self.scaleY);
        }
#pragma mark Clustering
        // Use  the Gaussian Mixed Model GMMCluster
        GMMCluster *gmmCluster = [[GMMCluster alloc] init];
        GMMPoints samples[1];
        initGMMPoints(&samples[0], discontinuousCount);
        GMMPoint element;
        for ( size_t i = 0; i < discontinuousCount; i++ ) {
#if defined(__STRICT_ANSI__)
            element.v[0] = discontinuousPoints[i].x;
            element.v[1] = discontinuousPoints[i].y;
#else
            element.x = discontinuousPoints[i].x;
            element.y = discontinuousPoints[i].y;
#endif
            appendGMMPoints(&samples[0], element);
        }
        
        [gmmCluster initialiseUsingGMMPointsWithNoClasses:1 vector_dimension:2 samples:samples];
                gmmCluster.init_num_of_subclasses = 19;
        [gmmCluster cluster];
        
        SigSet *signatureSet = [gmmCluster getSignatureSet];
        NSLog(@"No classes: %d", signatureSet->nclasses);
        
        // use ConcaveHull method to get outer points of area of discontinuity
        // find the boundary of drawnViewPoints
        // CGFLOAT_MAX is convex, 20.0 default, 1 thin shape
        _CPTHull *hull = [[_CPTHull alloc] initWithConcavity:5];
        
        NSUInteger countAllSubclasses = 0;
        for ( NSUInteger i = 0; i < (NSUInteger)signatureSet->nclasses; i++ ) {
            ClassSig *classSignature = &signatureSet->classSig[i];
            NSLog(@"Class: %ld No SubClasses: %ld", i, (NSUInteger)classSignature->nsubclasses);
            countAllSubclasses += (NSUInteger)classSignature->nsubclasses;
        }
        *boundaryLimitsDataLinePaths = (CGMutablePathRef*)calloc(countAllSubclasses, sizeof(CGMutablePathRef));
        CGPoint **clustersOuterPoints = (CGPoint**)calloc((size_t)countAllSubclasses, sizeof(CGPoint*));
        NSUInteger *clustersOuterNoPoints = (NSUInteger*)calloc((size_t)countAllSubclasses, sizeof(NSUInteger));
//        NSMutableArray<NSString*> *clustersOuterName = [NSMutableArray new];
//        CGAffineTransform transform = CGAffineTransformIdentity;
//#if DEBUG
//        CGAffineTransform transformEllipse;
//        double **eigenVectors = (double**)calloc(2, sizeof(double*));
//        eigenVectors[0] = (double*)calloc(2, sizeof(double));
//        eigenVectors[1] = (double*)calloc(2, sizeof(double));
//        double eigenValues[2] = { 0, 0 };
//        NSUInteger largest_eigenvec_index;
//    #if TARGET_OS_OSX
//        NSFont *font = [NSFont systemFontOfSize:30];
//    #else
//        UIFont *font = [UIFont systemFontOfSize:30];
//    #endif
//#endif
        
        NSUInteger clusterCount = 0;//, symbolType = 0;
        for ( NSUInteger i = 0; i < (NSUInteger)signatureSet->nclasses; i++ ) {
            ClassSig *classSignature = &signatureSet->classSig[i];
            for ( NSUInteger j = 0; j < (NSUInteger)classSignature->nsubclasses; j++ ) {
                CGPoint *discontinuities = (CGPoint*)malloc(discontinuousCount * sizeof(CGPoint));
//#if DEBUG
//                symbolType++;
//                if( symbolType >= CPTPlotSymbolTypeCustom ) {
//                    symbolType = 0;
//                }
//                symbol.symbolType = (CPTPlotSymbolType)symbolType;
////                symbol.symbolType = (CPTPlotSymbolType)(i * (NSUInteger)signatureSet->nclasses + j + 1);
////                SubSig *subSig = &classSignature->subSig[j];
//#endif
                NSUInteger m = 0, nearestSubclassIndex = 0;
                CGFloat nearestMeanToPointDistance, meanToPointDistance;
                for ( size_t k = 0; k < discontinuousCount; k++ ) {
                    nearestMeanToPointDistance = CGFLOAT_MAX;
                    for ( size_t l = 0; l < (NSUInteger)classSignature->nsubclasses; l++ ) {
                        SubSig *_subSig = &classSignature->subSig[l];
                        meanToPointDistance = sqrt(pow(_subSig->means[0] - discontinuousPoints[k].x, 2.0) + pow(_subSig->means[1] - discontinuousPoints[k].y, 2.0));
                        if ( meanToPointDistance < nearestMeanToPointDistance ) {
                            nearestSubclassIndex = l;
                            nearestMeanToPointDistance = meanToPointDistance;
                        }
                    }
                    if ( nearestSubclassIndex == j ) {
                        discontinuities[m] = discontinuousPoints[k];
//#if DEBUG
//                        CGPoint symbolPoint = CGPointMake(discontinuities[m].x - self.originOfContext.x, discontinuities[m].y - self.originOfContext.y);
//                        [symbol renderAsVectorInContext:context atPoint:symbolPoint scale:(CGFloat)1.0];
//#endif
                        m++;
                    }
                }
                
                [hull concaveHullOnViewPoints:discontinuities dataCount:m];
                free(discontinuities);
                
                clustersOuterPoints[clusterCount] = (CGPoint*)malloc(((size_t)[hull hullpointsCount] + 1) * sizeof(CGPoint));
                for ( NSUInteger k = 0; k < [hull hullpointsCount]; k++ ) {
                    clustersOuterPoints[clusterCount][k] = CGPointMake([hull hullpointsArray][k].point.x, [hull hullpointsArray][k].point.y);
//#if DEBUG
//                    CGPoint symbolPoint = CGPointMake(clustersOuterPoints[clusterCount][k].x - self.originOfContext.x, clustersOuterPoints[clusterCount][k].y - self.originOfContext.y);
//                    [symbol renderAsVectorInContext:context atPoint:symbolPoint scale:(CGFloat)1.0];
//#endif
                }
                // add first to end for controlpoints if need to fit curve
                clustersOuterPoints[clusterCount][[hull hullpointsCount]] = CGPointMake([hull hullpointsArray][0].point.x, [hull hullpointsArray][0].point.y);
                clustersOuterNoPoints[clusterCount] = [hull hullpointsCount] + 1;
//                [clustersOuterName addObject: [NSString stringWithFormat:@"%ld", clusterCount]];
                
//                CGPoint centre = centroidCGPoints(clustersOuterPoints[clusterCount], clustersOuterNoPoints[clusterCount]);
//                CGPoint symbolPoint = CGPointMake(centre.x - self.originOfContext.x, centre.y - self.originOfContext.y);
//                [symbol renderAsVectorInContext:context atPoint:symbolPoint scale:(CGFloat)1.0];
//
//                NSAttributedString *string = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%ld", clusterCount] attributes:@{ NSFontAttributeName: font }];
//                [string drawAtPoint:CGPointMake(symbolPoint.x - string.size.width / 2, symbolPoint.y - string.size.height / 2)];
        
                clusterCount++;
            }
        }
        freeGMMPoints(&samples[0]);
        gmmCluster = nil;
        free(discontinuousPoints);
        
        const NSUInteger diffSecondaryToPrimaryColumns = [contours getNoColumnsSecondaryGrid] / [contours getNoColumnsFirstGrid];
        const NSUInteger diffSecondaryToPrimaryRows = [contours getNoRowsSecondaryGrid] / [contours getNoRowsFirstGrid];
        const double weldDistMultiplier = sqrt(pow(diffSecondaryToPrimaryColumns, 2) + pow(diffSecondaryToPrimaryRows, 2));
        const double weldDist = weldDistMultiplier * (pow([contours getDX] * self.scaleX, 2.0) + pow([contours getDY] * self.scaleY, 2.0));

        noClusters = countAllSubclasses;
        kdtree *tree = NULL;
        kdtree_iterator *result = NULL;
        for ( NSUInteger m = 0; m < 4 ; m++) {
            for( NSUInteger i = 0; i < noClusters; i++) {
                double *x = (double*)calloc((size_t)clustersOuterNoPoints[i], sizeof(double)); /* array of points */
                double *y = (double*)calloc((size_t)clustersOuterNoPoints[i], sizeof(double));
                double *z = (double*)calloc((size_t)clustersOuterNoPoints[i], sizeof(double));
                /* build tree based on current cluster */
                for( NSUInteger j = 0; j < clustersOuterNoPoints[i]; j++ ) {
                    x[j] = (double)clustersOuterPoints[i][j].x;
                    y[j] = (double)clustersOuterPoints[i][j].y;
                    z[i] = 0.0;
                }
                kdtree_build(x, y, z, (size_t)clustersOuterNoPoints[i], &tree); /* tree obj recycled */
                for( NSUInteger j = i + 1; j < noClusters; j++ ) {
                    /* search for neighbours */
                    BOOL foundOne = NO;
                    for ( NSUInteger k = 0; k < clustersOuterNoPoints[j]; k++ ) {
                        kdtree_search(tree, &result, (double)clustersOuterPoints[j][k].x, (double)clustersOuterPoints[j][k].y, 0, weldDist); /* result obj recycled */
                        /* loop through each neighbour */
//                        size_t pos;
                        while ( /*(pos =*/ kdtree_iterator_get_next(result)/*)*/ != KDTREE_END ) {
//                            double distance = sqrt( ((double)clustersOuterPoints[j][k].x-x[pos])*((double)clustersOuterPoints[j][k].x-x[pos]) + ((double)clustersOuterPoints[j][k].y-y[pos])*((double)clustersOuterPoints[j][k].y-y[pos]) );
//                            printf("distance: %f cluster %ld to cluster %ld  .. %s, %s\n", distance , i , j, [clustersOuterName[i] cStringUsingEncoding: NSUTF8StringEncoding], [clustersOuterName[j] cStringUsingEncoding: NSUTF8StringEncoding]);
                            foundOne = YES;
                            break;
                        }
                        if (foundOne) {
                            // if meets adjacent criteria merge 2 to grow i cluster and get rid of this cluster
                            clustersOuterPoints[i] = (CGPoint*)realloc(clustersOuterPoints[i], (size_t)(clustersOuterNoPoints[i] + clustersOuterNoPoints[j]) * sizeof(CGPoint));
                            for ( NSUInteger l = 0; l < clustersOuterNoPoints[j]; l++ ) {
                                clustersOuterPoints[i][l + clustersOuterNoPoints[i]] = clustersOuterPoints[j][l];
                            }
                            // now remove element j from clustersOuterPoints
                            free(clustersOuterPoints[j]);
                            clustersOuterNoPoints[i] += clustersOuterNoPoints[j];
                            
                            [hull concaveHullOnViewPoints:clustersOuterPoints[i] dataCount:clustersOuterNoPoints[i]];

                            clustersOuterPoints[i] = (CGPoint*)realloc(clustersOuterPoints[i], (size_t)([hull hullpointsCount] + 1) * sizeof(CGPoint));
                            for ( NSUInteger l = 0; l < [hull hullpointsCount]; l++ ) {
                                clustersOuterPoints[i][l] = CGPointMake([hull hullpointsArray][l].point.x, [hull hullpointsArray][l].point.y);
                            }
                            // add first to end for controlpoints if need to fit curve
                            clustersOuterPoints[i][[hull hullpointsCount]] = CGPointMake([hull hullpointsArray][0].point.x, [hull hullpointsArray][0].point.y);
                            clustersOuterNoPoints[i] = [hull hullpointsCount] + 1;
//                            [clustersOuterName replaceObjectAtIndex:i withObject: [NSString stringWithFormat:@"%@, %@", clustersOuterName[i], clustersOuterName[j]]];
//                            [clustersOuterName removeObjectAtIndex:j];

                            x = (double*)realloc(x, (size_t)clustersOuterNoPoints[i] * sizeof(double)); /* array of points */
                            y = (double*)realloc(y, (size_t)clustersOuterNoPoints[i] * sizeof(double));
                            z = (double*)realloc(z, (size_t)clustersOuterNoPoints[i] * sizeof(double));
                            /* build tree based on current cluster */
                            for( NSUInteger l = 0; l < clustersOuterNoPoints[i]; l++ ) {
                                x[l] = (double)clustersOuterPoints[i][l].x;
                                y[l] = (double)clustersOuterPoints[i][l].y;
                                z[l] = 0.0;
                            }
                            kdtree_build(x, y, z, (size_t)clustersOuterNoPoints[i], &tree); /* tree obj recycled */

                            // then move up other clusters
                            for( NSUInteger l = j; l < noClusters - 1; l++ ) {
                                clustersOuterPoints[l] = clustersOuterPoints[l + 1];
                                clustersOuterNoPoints[l] = clustersOuterNoPoints[l + 1];
                            }
                            noClusters--;
                            clustersOuterPoints = realloc(clustersOuterPoints, (size_t)noClusters * sizeof(CGPoint*));
                            clustersOuterNoPoints = (NSUInteger*)realloc(clustersOuterNoPoints, (size_t)noClusters * sizeof(NSUInteger));
                            j--;
                            break;
                        }
                    }
                    if ( noClusters < 3 ) {
                        break;
                    }
                }
                free(x);
                free(y);
                free(z);
                if (noClusters < 3) {
                    break;
                }
            }
            if ( noClusters < 3 ) {
                break;
            }
        }
        /* clean at the end */
        kdtree_delete(&tree);
        kdtree_iterator_delete(&result);

        for( NSUInteger i = 0; i < noClusters; i++) {
//#if DEBUG
//            symbolType++;
//            if( symbolType >= CPTPlotSymbolTypeCustom ) {
//                symbolType = 0;
//            }
//            symbol.symbolType = (CPTPlotSymbolType)symbolType;
//
//            for ( NSUInteger k = 0; k < clustersOuterNoPoints[i]; k++ ) {
//
//                    CGPoint symbolPoint = CGPointMake(clustersOuterPoints[i][k].x - self.originOfContext.x, clustersOuterPoints[i][k].y - self.originOfContext.y);
//                    [symbol renderAsVectorInContext:context atPoint:symbolPoint scale:(CGFloat)1.0];
//
//            }
//            CGPoint centre = centroidCGPoints(clustersOuterPoints[i], clustersOuterNoPoints[i]);
//            CGPoint symbolPoint = CGPointMake(centre.x - self.originOfContext.x, centre.y - self.originOfContext.y);
//            [symbol renderAsVectorInContext:context atPoint:symbolPoint scale:(CGFloat)1.0];
//
//            NSAttributedString *string = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%ld%ld", i, i] attributes:@{ NSFontAttributeName: font }];
//            [string drawAtPoint:CGPointMake(symbolPoint.x - string.size.width / 2, symbolPoint.y - string.size.height / 2)];
//#endif
            // now let's try to get a better discontinuity trace for this region
            // CPTContourPlot uses an initial user defined grid ie 256 * 256
            // this resolution may not be good enough to present a neat discontinuity line,
            // we need to trace this with closer resolution
//            [self traceDiscontinuityLine:clustersOuterPoints[i] noPoints:clustersOuterNoPoints[i] contours:contours];

            // redo concavity on larger value
            [hull setConcavity:20.0];
            [hull concaveHullOnViewPoints:clustersOuterPoints[i] dataCount:clustersOuterNoPoints[i]];

            if ( [hull hullpointsCount] > 0 ) {
                clustersOuterPoints[i] = (CGPoint*)realloc(clustersOuterPoints[i], ((size_t)[hull hullpointsCount]/* + 1*/) * sizeof(CGPoint));
                for ( NSUInteger k = 0; k < [hull hullpointsCount]; k++ ) {
                    clustersOuterPoints[i][k] = CGPointMake([hull hullpointsArray][k].point.x, [hull hullpointsArray][k].point.y);
                    //#if DEBUG
                    //                    CGPoint symbolPoint = CGPointMake(clustersOuterPoints[i][k].x - self.originOfContext.x, clustersOuterPoints[i][k].y - self.originOfContext.y);
                    //                    [symbol renderAsVectorInContext:context atPoint:symbolPoint scale:(CGFloat)1.0];
                    //#endif
                }
                // add first to end for controlpoints if need to fit curve
                //            clustersOuterPoints[i][[hull hullpointsCount]] = CGPointMake([hull hullpointsArray][0].point.x, [hull hullpointsArray][0].point.y);
                clustersOuterNoPoints[i] = [hull hullpointsCount] /*+ 1*/;
            }
            if ( self.alignsPointsToPixels && clustersOuterPoints[i] != NULL ) {
                [self alignViewPointsToUserSpace:clustersOuterPoints[i] withContext:context numberOfPoints:clustersOuterNoPoints[i]];
            }
        }
        hull = nil;
        
        CGAffineTransform transform = CGAffineTransformIdentity;
        CGPoint controlPoints1[4];
        CGPoint controlPoints2[4];
        CGPoint bezierPoints[4];
        NSRange bezierIndexRange;
        if ( discontinuityStrips->array == NULL || discontinuityStrips->size == 0 ) {
            initStrips(discontinuityStrips, noClusters);
        }
        else {
            clearStrips(discontinuityStrips);
        }
        for( NSUInteger i = 0; i < noClusters; i++) {
            Strip strip = initStrip();
            // create heap memory for next boundaryLimitsDataLinePath
            // and create the respective paths for boundaries
            *(*boundaryLimitsDataLinePaths + i) = CGPathCreateMutable();
            CGMutablePathRef *boundaryLimitsDataLinePath = (*boundaryLimitsDataLinePaths + i);
            
            NSUInteger k = 0;
            for ( k = 0; k < clustersOuterNoPoints[i]; k++) {
                if ( clustersOuterPoints[i][k].x == leftEdge || clustersOuterPoints[i][k].x == rightEdge || clustersOuterPoints[i][k].y == bottomEdge || clustersOuterPoints[i][k].y == topEdge ) {
                    if ( k > 0 ) {
                        clustersOuterPoints[i] = realloc(clustersOuterPoints[i], ((size_t)clustersOuterNoPoints[i] + 1) * sizeof(CGPoint));
                        clustersOuterPoints[i][clustersOuterNoPoints[i]] = clustersOuterPoints[i][k];
                        clustersOuterNoPoints[i] = clustersOuterNoPoints[i] + 1;
                    }
                    break;
                }
            }
            while ( (clustersOuterPoints[i][k].x == leftEdge && clustersOuterPoints[i][k+1].x == leftEdge) || (clustersOuterPoints[i][k].x == rightEdge && clustersOuterPoints[i][k+1].x == rightEdge) || (clustersOuterPoints[i][k].y == bottomEdge && clustersOuterPoints[i][k+1].y == bottomEdge) || (clustersOuterPoints[i][k].y == topEdge && clustersOuterPoints[i][k+1].y == topEdge) ) {
                k++;
                if ( k == clustersOuterNoPoints[i] ) {
                    break;
                }
            }
            CGPathMoveToPoint(*boundaryLimitsDataLinePath, &transform, (clustersOuterPoints[i][k].x - self.originOfContext.x) * self.scaleOfContext, (clustersOuterPoints[i][k].y - self.originOfContext.y) * self.scaleOfContext);
            strip.startBorderdirection = [self findPointBorderDirection:clustersOuterPoints[i][k] leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
            strip.startPoint = clustersOuterPoints[i][k];
            
            NSUInteger n = 0;
            for( NSUInteger j = k + 1; j < clustersOuterNoPoints[i]; j++ ) {
                // if a straight line parallel x or y axis
                if ( (clustersOuterPoints[i][j].x == leftEdge && clustersOuterPoints[i][j-1].x == leftEdge) || (clustersOuterPoints[i][j].x == rightEdge && clustersOuterPoints[i][j-1].x == rightEdge) || (clustersOuterPoints[i][j].y == bottomEdge && clustersOuterPoints[i][j-1].y == bottomEdge) || (clustersOuterPoints[i][j].y == topEdge && clustersOuterPoints[i][j-1].y == topEdge) ) {
                    if ( n == 0 ) {
                        n = j - 1;
                    }
                }
                else if ( j < clustersOuterNoPoints[i] - 1 && ((clustersOuterPoints[i][j-1].x == leftEdge && clustersOuterPoints[i][j+1].x == leftEdge) || (clustersOuterPoints[i][j-1].x == rightEdge && clustersOuterPoints[i][j+1].x == rightEdge) || (clustersOuterPoints[i][j-1].y == bottomEdge && clustersOuterPoints[i][j+1].y == bottomEdge) || (clustersOuterPoints[i][j-1].y == topEdge && clustersOuterPoints[i][j+1].y == topEdge)) ) {
                    CGPathAddLineToPoint(*boundaryLimitsDataLinePath, &transform, (clustersOuterPoints[i][j-1].x - self.originOfContext.x) * self.scaleOfContext, (clustersOuterPoints[i][j+1].y - self.originOfContext.y) * self.scaleOfContext);
                }
                else if ( (clustersOuterPoints[i][j].x - clustersOuterPoints[i][j-1].x == 0) || (clustersOuterPoints[i][j].y - clustersOuterPoints[i][j-1].y == 0) || j == clustersOuterNoPoints[i] - 1 ) {
                    CGPathAddLineToPoint(*boundaryLimitsDataLinePath, &transform, (clustersOuterPoints[i][j].x - self.originOfContext.x) * self.scaleOfContext, (clustersOuterPoints[i][j].y - self.originOfContext.y) * self.scaleOfContext);
                }
                else { // fit a curve instead
                    bezierIndexRange = j < 2 ? NSMakeRange(0, 3) : NSMakeRange(0, 4);
                    NSUInteger jj = j < 2 ? j - 1 : j - 2;
                    for ( NSUInteger l = 0; l < NSMaxRange(bezierIndexRange); l++) {
                        bezierPoints[l] = clustersOuterPoints[i][jj];
                        jj++;
                    }
                    [self computeCatmullRomControlPoints:controlPoints1 points2:controlPoints2 withAlpha:0.5 forViewPoints:bezierPoints indexRange:bezierIndexRange];
                    //  [self computeHermiteControlPoints:controlPoints1 points2:controlPoints2 forViewPoints:bezierPoints indexRange:bezierIndexRange];
                    //  [self computeBezierControlPoints:controlPoints1 points2:controlPoints2 forViewPoints:bezierPoints indexRange:bezierIndexRange];
                    
                    CGPathAddCurveToPoint(*boundaryLimitsDataLinePath, NULL, (controlPoints1[1].x - self.originOfContext.x) * self.scaleOfContext, (controlPoints1[1].y - self.originOfContext.y) * self.scaleOfContext, (controlPoints2[1].x - self.originOfContext.x) * self.scaleOfContext, (controlPoints2[1].y - self.originOfContext.y) * self.scaleOfContext, (bezierPoints[1].x - self.originOfContext.x) * self.scaleOfContext, (bezierPoints[1].y - self.originOfContext.y) * self.scaleOfContext);
                   // j++;
                    //                                    CGPathAddCurveToPoint(*boundaryLimitsDataLinePath, NULL, controlPoints1[2].x, controlPoints1[2].y, controlPoints2[2].x, controlPoints2[1].y, clustersOuterPoints[i][j].x, clustersOuterPoints[i][j].y);
                }
            }
            if ( n == 0 ) {
                n = clustersOuterNoPoints[i] - 1;
            }
            CGPathAddLineToPoint(*boundaryLimitsDataLinePath, &transform, (clustersOuterPoints[i][n].x - self.originOfContext.x) * self.scaleOfContext, (clustersOuterPoints[i][n].y - self.originOfContext.y) * self.scaleOfContext);
#if DEBUG
#if TARGET_OS_OSX
            NSBezierPath __unused *bezierPath = [NSBezierPath bezierPathWithCGPath:*boundaryLimitsDataLinePath];
#else
            UIBezierPath __unused *bezierPath = [UIBezierPath bezierPathWithCGPath:*boundaryLimitsDataLinePath];
#endif
            
#endif
            strip.endBorderdirection = [self findPointBorderDirection:clustersOuterPoints[i][n] leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
            strip.endPoint = clustersOuterPoints[i][n];
            strip.pStripList = NULL;
            strip.index = i;
            strip.plane = NSNotFound;
            strip.reverse = [self reverseStripPath:&strip];
            appendStrips(discontinuityStrips, strip);

//#if DEBUG
//                // to show the ellipse of uncertainty and the boundary path
//                CGContextSaveGState(context);
//                CGContextBeginPath(context);
//                CGContextAddPath(context, *(*boundaryLimitsDataLinePaths + i * (NSUInteger)signatureSet->nclasses + j));
//                CGContextClosePath(context);
//
//                CGFloat components[4] = { 1, (CGFloat)(i * (NSUInteger)signatureSet->nclasses + j) / (CGFloat)noBoundaryLimitsDataLinePaths, 0.0, 1 };
//                CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
//                CGColorRef color = CGColorCreate(colorspace, components);
//                CGContextSetStrokeColorWithColor(context, color);
//                CGContextSetLineWidth(context, 4.0);
//                CGContextStrokePath(context);
//                CGColorRelease(color);
//                CGColorSpaceRelease(colorspace);

//                eigenValuesAndEigenVectorsOfCoVariance(subSig, eigenValues, eigenVectors, 2);
//                // Get the largest eigenvalue
//                if ( eigenValues[0] > eigenValues[1] ) {
//                    largest_eigenvec_index = 0;
//                }
//                else {
//                    largest_eigenvec_index = 1;
//                }
//                // Calculate the angle between the x-axis and the largest eigenvector
//                // This angle is between -pi and pi.
//                // Let's shift it such that the angle is between 0 and 2pi
//                CGFloat angle;
//                if ( (angle = atan2((CGFloat)eigenVectors[largest_eigenvec_index][1], (CGFloat)eigenVectors[largest_eigenvec_index][0])) < 0.0 ) {
//                    angle+= 2.0 * M_PI;
//                }
//
//                // Get the 99%/95% confidence interval error ellipse
//                CGFloat chisquare_val = 3.0;//2.4477;
//                CGFloat pearson = (CGFloat)subSig->R[0][1] / sqrt((CGFloat)subSig->R[0][0] * (CGFloat)subSig->R[1] [1]);
//                CGFloat ell_radius_x = sqrt(1.0 + pearson) * (CGFloat)sqrt(subSig->R[0][0]) * chisquare_val;
//                CGFloat ell_radius_y = sqrt(1.0 - pearson) * (CGFloat)sqrt(subSig->R[1][1]) * chisquare_val;
//                CGMutablePathRef ellipsePath = CGPathCreateMutable();
//                transformEllipse = CGAffineTransformIdentity;
//                transformEllipse = CGAffineTransformRotate(transformEllipse, angle);
//                transformEllipse = CGAffineTransformTranslate(transformEllipse, subSig->means[0], subSig->means[1]);
//
//
//                CGPathAddEllipseInRect(ellipsePath, &transformEllipse, CGRectMake( /*subSig->means[0]*/ - ell_radius_x / 2.0,  /*subSig->means[1]*/ - ell_radius_y / 2.0, ell_radius_x, ell_radius_y));
//                CGContextSaveGState(context);
//                CGContextBeginPath(context);
//                CGContextAddPath(context, ellipsePath);
//                CGContextClosePath(context);
//                CGPathRelease(ellipsePath);
//
//                CGFloat components1[4] = { 1, (CGFloat)(i * (NSUInteger)signatureSet->nclasses + j) / (CGFloat)noBoundaryLimitsDataLinePaths, 1, 1 };
//                CGColorSpaceRef colorspace1 = CGColorSpaceCreateDeviceRGB();
//                CGColorRef color1 = CGColorCreate(colorspace1, components1);
//                CGContextSetStrokeColorWithColor(context, color1);
//                CGContextSetLineWidth(context, 4.0);
//                CGFloat lengths[4] = { (CGFloat)1.0, (CGFloat)3.0, (CGFloat)4.0, (CGFloat)2.0 } ;
//                CGContextSetLineDash(context, 0.0, lengths, 4.0);
//                CGContextStrokePath(context);
//                CGColorRelease(color1);
//                CGColorSpaceRelease(colorspace1);
//                          Do your stuff here
//                CGImageRef imgRef = CGBitmapContextCreateImage(context);
//#if TARGET_OS_OSX
//                NSImage* img = [[NSImage alloc] initWithCGImage:imgRef size: NSZeroSize];
//
//                NSImage* __unused flippedImage = [NSImage imageWithSize:img.size flipped:YES drawingHandler:^BOOL(NSRect dstRect) {
//                    [img drawInRect:dstRect];
//                    return YES;
//                }];
//#else
//                UIImage* img = [UIImage imageWithCGImage:imgRef];
//                CGSize size = img.size;
//                UIGraphicsBeginImageContext(CGSizeMake(size.height, size.width));
//                [[UIImage imageWithCGImage:imgRef scale:1.0 orientation:UIImageOrientationDownMirrored] drawInRect:CGRectMake(0,0,size.height ,size.width)];
//                UIImage* __unused flippedImage = UIGraphicsGetImageFromCurrentImageContext();
//                UIGraphicsEndImageContext();
//#endif
//                CGImageRelease(imgRef);
//                CGContextRestoreGState(context);
//#endif
        }
//#if DEBUG
//        free(eigenVectors[0]);
//        free(eigenVectors[1]);
//        free(eigenVectors);
//#endif
        for( NSUInteger i = 0; i < noClusters; i++ ) {
            free(clustersOuterPoints[i]);
        }
        free(clustersOuterPoints);
        free(clustersOuterNoPoints);
    }
    
    return noClusters;
}

// resolution of the firstgrid of contour algorithm may produce a poor curve, so let's improve this by iteration of each concave
// hull point of the initial formation of this region
-(void)traceDiscontinuityLine:(CGPoint*)regionPoints noPoints:(NSUInteger)noPoints contours:(CPTContours*)contours {
    
    CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
    
    CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX, maxX = -CGFLOAT_MAX, maxY = -CGFLOAT_MAX;
    for( NSUInteger i = 0; i < noPoints; i++ ) {
        minX = MIN(minX, regionPoints[i].x);
        minY = MIN(minY, regionPoints[i].y);
        maxX = MAX(maxX, regionPoints[i].x);
        maxY = MAX(maxY, regionPoints[i].y);
    }
    
    double resolutionX = [contours getDX];
    double resolutionY = [contours getDY];
    double resolutionFirstGridX = resolutionX * [contours getNoColumnsSecondaryGrid] / [contours getNoColumnsFirstGrid];
    double resolutionFirstGridY = resolutionY * [contours getNoRowsSecondaryGrid] / [contours getNoRowsFirstGrid];
    CGFloat deltaX, deltaY, distance;
    double x1, y1, x2, y2, xMiddle = 0.0, yMiddle = 0.0, functionValueMiddle;
    CGPoint centroid = [self findCentroidOfShape:regionPoints noPoints:noPoints];
    x1 = (double)centroid.x / self.scaleX + thePlotSpace.xRange.locationDouble;
    y1 = (double)centroid.y / self.scaleY + thePlotSpace.yRange.locationDouble;
    centroid = CGPointMake(x1, y1);
    for ( NSUInteger i = 0; i < noPoints - 1; i++ ) {
        deltaX = regionPoints[i + 1].x - regionPoints[i].x;
        deltaY = regionPoints[i + 1].y - regionPoints[i].y;
        x1 = (double)regionPoints[i].x / self.scaleX + thePlotSpace.xRange.locationDouble;
        y1 = (double)regionPoints[i].y / self.scaleY + thePlotSpace.yRange.locationDouble;
        distance = sqrt(pow(x1 - centroid.x, 2.0) + pow(y1 - centroid.y, 2.0));
        if ( fabs(deltaX) > 0 || regionPoints[i].y == minY || regionPoints[i].y == maxY ) {
            y2 = y1;
            x2 = x1;
            if ( sqrt(pow(x2 - centroid.x, 2.0) + pow(y2 + resolutionFirstGridY - centroid.y, 2.0)) > distance ) {
                y2 += resolutionFirstGridY * 2.0;
            }
            else {
                y2 -= resolutionFirstGridY * 2.0;
            }
            if ( y2 >= [contours getLimits][2] && y2 <= [contours getLimits][3] ) {
                while( fabs(y1 - y2) >= resolutionY ) {
                    yMiddle = (y1 + y2) / 2.0;
                    functionValueMiddle = self.dataSourceBlock(x1, yMiddle);
                    if ( isnan(functionValueMiddle) ) {
                        y1 = yMiddle;
                    }
                    else {
                        y2 = yMiddle;
                    }
                }
                regionPoints[i] = CGPointMake(regionPoints[i].x, (yMiddle - thePlotSpace.yRange.locationDouble) * self.scaleY);
            }
        }
        x1 = (double)regionPoints[i].x / self.scaleX + thePlotSpace.xRange.locationDouble;
        y1 = (double)regionPoints[i].y / self.scaleY + thePlotSpace.yRange.locationDouble;
        distance = sqrt(pow(x1 - centroid.x, 2.0) + pow(y1 - centroid.y, 2.0));
        if ( fabs(deltaY) > 0 || regionPoints[i].x == minX || regionPoints[i].x == maxX ) {
            x2 = x1;
            y2 = y1;
            if ( sqrt(pow(x2 + resolutionFirstGridX - centroid.x, 2.0) + pow(y2 - centroid.y, 2.0)) > distance ) {
                x2 += resolutionFirstGridX * 2.0;
            }
            else {
                x2 -= resolutionFirstGridX * 2.0;
            }
            if ( x2 >= [contours getLimits][0] && x2 <= [contours getLimits][1] ) {
                while( fabs(x1 - x2) >= resolutionX ) {
                    xMiddle = (x1 + x2) / 2.0;
                    functionValueMiddle = self.dataSourceBlock(xMiddle, y1);
                    if ( isnan(functionValueMiddle) ) {
                        x1 = xMiddle;
                    }
                    else {
                        x2 = xMiddle;
                    }
                }
                regionPoints[i] = CGPointMake((xMiddle - thePlotSpace.xRange.locationDouble) * self.scaleX, regionPoints[i].y);
            }
        }
    }
}

#pragma mark -
#pragma mark Create CGPaths from contour indices


-(void)createClosedDataLinePath:(CGMutablePathRef*)dataLineClosedPath context:(nonnull CGContextRef)context contours:(CPTContours *)contours strip:(Strips)closedStrip index:(NSUInteger)index startPoint:(CGPoint*)startPoint {
    
    if ( closedStrip.used > 0 ) {
        LineStrip *pStrip = NULL;
        NSUInteger pos = closedStrip.array[index].index;
        pStrip = &closedStrip.array[index].pStripList->array[pos];
        if (pStrip != NULL && pStrip->used > 0) {
            CGPoint _startPoint, _endPoint;
            [self createDataLinePath:dataLineClosedPath fromStrip:pStrip context:context contours:contours startPoint:&_startPoint endPoint:&_endPoint reverseOrder:NO closed:YES extraStripList:closedStrip.array[index].pStripList == [contours getExtraIsoCurvesListsAtIsoCurve:closedStrip.array[index].plane]];
            if( !CGPointEqualToPoint(_startPoint, _endPoint)) {
                CGPathAddLineToPoint(*dataLineClosedPath, NULL, _startPoint.x, _startPoint.y);
            }
            *startPoint = _startPoint;
        }
    }
}

-(NSUInteger)includeCornerIfRequiredUsingStartEdge:(CPTContourBorderDimensionDirection)startEdge endEdge:(CPTContourBorderDimensionDirection)endEdge cornerPoints:(CGPoint*)cornerPoints startPoint:(CGPoint)startPoint endPoint:(CGPoint)endPoint leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge useAllCorners:(BOOL)useAllCorners {   // every thing is anti-clockwise
    NSUInteger noCorners = 0;

    if ( startEdge == endEdge && !useAllCorners ) {
        return noCorners;
    }

    cornerPoints[0] = CGPointMake(-0.0, -0.0);
    cornerPoints[1] = CGPointMake(-0.0, -0.0);
    cornerPoints[2] = CGPointMake(-0.0, -0.0);
    cornerPoints[3] = CGPointMake(-0.0, -0.0);
    switch (startEdge) {
        case CPTContourBorderDimensionDirectionXForward:   // bottom edge
            switch (endEdge) {
                case CPTContourBorderDimensionDirectionXForward:
                    if( useAllCorners ) {
                        cornerPoints[0] = CGPointMake(rightEdge, bottomEdge);
                        cornerPoints[1] = CGPointMake(rightEdge, topEdge);
                        cornerPoints[2] = CGPointMake(leftEdge, topEdge);
                        cornerPoints[3] = CGPointMake(leftEdge, bottomEdge);
                        noCorners = 4;
                    }
                    break;
                case CPTContourBorderDimensionDirectionYForward:
                    cornerPoints[0] = CGPointMake(rightEdge, bottomEdge);
                    noCorners = 1;
                    break;
                case CPTContourBorderDimensionDirectionXBackward:
                    cornerPoints[0] = CGPointMake(rightEdge, bottomEdge);
                    cornerPoints[1] = CGPointMake(rightEdge, topEdge);
                    noCorners = 2;
                    break;
                case CPTContourBorderDimensionDirectionYBackward:
                default:
                    cornerPoints[0] = CGPointMake(rightEdge, bottomEdge);
                    cornerPoints[1] = CGPointMake(rightEdge, topEdge);
                    cornerPoints[2] = CGPointMake(leftEdge, topEdge);
                    noCorners = 3;
                    break;
            }
//            if ( !useAllCorners && ((endPoint.x == rightEdge && startPoint.x != endPoint.x) || (endPoint.y == bottomEdge && endPoint.x < startPoint.x)) ) {
//                cornerPoints[0] = CGPointMake(rightEdge, bottomEdge);
//                noCorners = 1;
//            }
//            else if ( !useAllCorners && endPoint.y == topEdge && startPoint.y != endPoint.y ) {
//                cornerPoints[0] = CGPointMake(rightEdge, bottomEdge);
//                cornerPoints[1] = CGPointMake(rightEdge, topEdge);
//                noCorners = 2;
//            }
//            else if ( !useAllCorners && endPoint.x == leftEdge && startPoint.x != endPoint.x ) {
//                cornerPoints[0] = CGPointMake(rightEdge, bottomEdge);
//                cornerPoints[1] = CGPointMake(rightEdge, topEdge);
//                cornerPoints[2] = CGPointMake(leftEdge, topEdge);
//                noCorners = 3;
//            }
//            else if (useAllCorners && endPoint.y == bottomEdge && endPoint.x < startPoint.x ) {
//                cornerPoints[0] = CGPointMake(rightEdge, bottomEdge);
//                cornerPoints[1] = CGPointMake(rightEdge, topEdge);
//                cornerPoints[2] = CGPointMake(leftEdge, topEdge);
//                cornerPoints[3] = CGPointMake(leftEdge, bottomEdge);
//                noCorners = 4;
//            }
            break;
        case CPTContourBorderDimensionDirectionYForward:   // right edge
            switch (endEdge) {
                case CPTContourBorderDimensionDirectionXForward:
                    cornerPoints[0] = CGPointMake(rightEdge, topEdge);
                    cornerPoints[1] = CGPointMake(leftEdge, topEdge);
                    cornerPoints[2] = CGPointMake(leftEdge, bottomEdge);
                    noCorners = 3;
                    break;
                case CPTContourBorderDimensionDirectionYForward:
                    if( useAllCorners ) {
                        cornerPoints[0] = CGPointMake(rightEdge, topEdge);
                        cornerPoints[1] = CGPointMake(leftEdge, topEdge);
                        cornerPoints[2] = CGPointMake(leftEdge, bottomEdge);
                        cornerPoints[3] = CGPointMake(rightEdge, bottomEdge);
                        noCorners = 4;
                    }
                    break;
                case CPTContourBorderDimensionDirectionXBackward:
                    cornerPoints[0] = CGPointMake(rightEdge, topEdge);
                    noCorners = 1;
                    break;
                case CPTContourBorderDimensionDirectionYBackward:
                default:
                    cornerPoints[0] = CGPointMake(rightEdge, topEdge);
                    cornerPoints[1] = CGPointMake(leftEdge, topEdge);
                    noCorners = 2;
                    break;
            }
//            if ( !useAllCorners && ((endPoint.y == topEdge && startPoint.y != endPoint.y) || (endPoint.x == rightEdge && endPoint.y < startPoint.y)) ) {
//                cornerPoints[0] = CGPointMake(rightEdge, topEdge);
//                noCorners = 1;
//            }
//            else if ( !useAllCorners && endPoint.x == leftEdge && startPoint.x != endPoint.x ) {
//                cornerPoints[0] = CGPointMake(rightEdge, topEdge);
//                cornerPoints[1] = CGPointMake(leftEdge, topEdge);
//                noCorners = 2;
//            }
//            else if ( !useAllCorners && endPoint.y == bottomEdge && startPoint.y != endPoint.y ) {
//                cornerPoints[0] = CGPointMake(rightEdge, topEdge);
//                cornerPoints[1] = CGPointMake(leftEdge, topEdge);
//                cornerPoints[2] = CGPointMake(leftEdge, bottomEdge);
//                noCorners = 3;
//            }
//            else if ( useAllCorners && endPoint.x == rightEdge && endPoint.y < startPoint.y ) {
//                cornerPoints[0] = CGPointMake(rightEdge, topEdge);
//                cornerPoints[1] = CGPointMake(leftEdge, topEdge);
//                cornerPoints[2] = CGPointMake(leftEdge, bottomEdge);
//                cornerPoints[3] = CGPointMake(rightEdge, bottomEdge);
//                noCorners = 4;
//            }
            break;
        case CPTContourBorderDimensionDirectionXBackward:   // top edge
            switch (endEdge) {
                case CPTContourBorderDimensionDirectionXForward:
                    cornerPoints[0] = CGPointMake(leftEdge, topEdge);
                    cornerPoints[1] = CGPointMake(leftEdge, bottomEdge);
                    noCorners = 2;
                    break;
                case CPTContourBorderDimensionDirectionYForward:
                    cornerPoints[0] = CGPointMake(leftEdge, topEdge);
                    cornerPoints[1] = CGPointMake(leftEdge, bottomEdge);
                    cornerPoints[2] = CGPointMake(rightEdge, bottomEdge);
                    noCorners = 3;
                    break;
                case CPTContourBorderDimensionDirectionXBackward:
                    if( useAllCorners ) {
                        cornerPoints[0] = CGPointMake(leftEdge, topEdge);
                        cornerPoints[1] = CGPointMake(leftEdge, bottomEdge);
                        cornerPoints[2] = CGPointMake(rightEdge, bottomEdge);
                        cornerPoints[3] = CGPointMake(rightEdge, topEdge);
                        noCorners = 4;
                    }
                    break;
                case CPTContourBorderDimensionDirectionYBackward:
                default:
                    cornerPoints[0] = CGPointMake(leftEdge, topEdge);
                    noCorners = 1;
                    break;
            }
//            if ( !useAllCorners && ((endPoint.x == leftEdge && startPoint.x != endPoint.x) || (endPoint.y == topEdge && endPoint.x > startPoint.x)) ) {
//                cornerPoints[0] = CGPointMake(leftEdge, topEdge);
//                noCorners = 1;
//            }
//            else if (!useAllCorners && endPoint.y == bottomEdge && startPoint.y != endPoint.y ) {
//                cornerPoints[0] = CGPointMake(leftEdge, topEdge);
//                cornerPoints[1] = CGPointMake(leftEdge, bottomEdge);
//                noCorners = 2;
//            }
//            else if ( !useAllCorners && endPoint.x == rightEdge && startPoint.x != endPoint.x ) {
//                cornerPoints[0] = CGPointMake(leftEdge, topEdge);
//                cornerPoints[1] = CGPointMake(leftEdge, bottomEdge);
//                cornerPoints[2] = CGPointMake(rightEdge, bottomEdge);
//                noCorners = 3;
//            }
//            else if ( useAllCorners && endPoint.y == topEdge && endPoint.x > startPoint.x ) {
//                cornerPoints[0] = CGPointMake(leftEdge, topEdge);
//                cornerPoints[1] = CGPointMake(leftEdge, bottomEdge);
//                cornerPoints[2] = CGPointMake(rightEdge, bottomEdge);
//                cornerPoints[3] = CGPointMake(rightEdge, topEdge);
//                noCorners = 4;
//            }
            break;
        case CPTContourBorderDimensionDirectionYBackward:
        default:   // left edge
            switch (endEdge) {
                case CPTContourBorderDimensionDirectionXForward:
                    cornerPoints[0] = CGPointMake(leftEdge, bottomEdge);
                    noCorners = 1;
                    break;
                case CPTContourBorderDimensionDirectionYForward:
                    cornerPoints[0] = CGPointMake(leftEdge, bottomEdge);
                    cornerPoints[1] = CGPointMake(rightEdge, bottomEdge);
                    noCorners = 2;
                    break;
                case CPTContourBorderDimensionDirectionXBackward:
                    cornerPoints[0] = CGPointMake(leftEdge, bottomEdge);
                    cornerPoints[1] = CGPointMake(rightEdge, bottomEdge);
                    cornerPoints[2] = CGPointMake(rightEdge, topEdge);
                    noCorners = 3;
                    break;
                case CPTContourBorderDimensionDirectionYBackward:
                default:
                    if( useAllCorners ) {
                        cornerPoints[0] = CGPointMake(leftEdge, bottomEdge);
                        cornerPoints[1] = CGPointMake(rightEdge, bottomEdge);
                        cornerPoints[2] = CGPointMake(rightEdge, topEdge);
                        cornerPoints[3] = CGPointMake(leftEdge, topEdge);
                        noCorners = 4;
                    }
                    break;
            }
//                if ( !useAllCorners && ((endPoint.y == bottomEdge && startPoint.y != endPoint.y) || (endPoint.x == leftEdge && endPoint.y > startPoint.y)) ) {
//                    cornerPoints[0] = CGPointMake(leftEdge, bottomEdge);
//                    noCorners = 1;
//                }
//                else if ( !useAllCorners && endPoint.x == rightEdge && startPoint.x != endPoint.x ) {
//                    cornerPoints[0] = CGPointMake(leftEdge, bottomEdge);
//                    cornerPoints[1] = CGPointMake(rightEdge, bottomEdge);
//                    noCorners = 2;
//                }
//                else if ( !useAllCorners && endPoint.y == topEdge && startPoint.y != endPoint.y ) {
//                    cornerPoints[0] = CGPointMake(leftEdge, bottomEdge);
//                    cornerPoints[1] = CGPointMake(rightEdge, bottomEdge);
//                    cornerPoints[2] = CGPointMake(rightEdge, topEdge);
//                    noCorners = 3;
//                }
//                else if ( useAllCorners && endPoint.x == leftEdge && endPoint.y > startPoint.y ) {
//                    cornerPoints[0] = CGPointMake(leftEdge, bottomEdge);
//                    cornerPoints[1] = CGPointMake(rightEdge, bottomEdge);
//                    cornerPoints[2] = CGPointMake(rightEdge, topEdge);
//                    cornerPoints[3] = CGPointMake(leftEdge, topEdge);
//                    noCorners = 4;
//                }
            break;
    }

    return noCorners;
}

-(BOOL)reverseStripPath:(Strip*)strip {
    // make sure all paths are anticlockwise
    BOOL reverseOrder = NO;
    switch (strip->startBorderdirection) {
        case CPTContourBorderDimensionDirectionXForward:
            if ( (strip->endBorderdirection == CPTContourBorderDimensionDirectionXForward && strip->startPoint.x > strip->endPoint.x) || strip->endBorderdirection == CPTContourBorderDimensionDirectionYBackward ) {
                reverseOrder = YES;
            }
            break;
        case CPTContourBorderDimensionDirectionYForward:
            if ( (strip->endBorderdirection == CPTContourBorderDimensionDirectionYForward && strip->startPoint.y > strip->endPoint.y) || strip->endBorderdirection == CPTContourBorderDimensionDirectionXForward ) {
                reverseOrder = YES;
            }
            break;
        case CPTContourBorderDimensionDirectionXBackward:
            if ( (strip->endBorderdirection == CPTContourBorderDimensionDirectionXBackward && strip->startPoint.x < strip->endPoint.x) || strip->endBorderdirection == CPTContourBorderDimensionDirectionYForward  ) {
                reverseOrder = YES;
            }
            break;
        case CPTContourBorderDimensionDirectionYBackward:
        default:
            if ( (strip->endBorderdirection == CPTContourBorderDimensionDirectionYBackward && strip->startPoint.y < strip->endPoint.y) || strip->endBorderdirection == CPTContourBorderDimensionDirectionXBackward
                ) {
                reverseOrder = YES;
            }
            break;
    }
    
    return reverseOrder;
}

#pragma mark -
#pragma mark Create CGPath

-(void)createDataLinePath:(CGMutablePathRef*)dataLinePath fromStrip:(nullable LineStrip *)pStrip context:(nonnull CGContextRef)context contours:(CPTContours *)contours startPoint:(CGPoint*)startPoint endPoint:(CGPoint*)endPoint reverseOrder:(BOOL)reverse closed:(BOOL)closed extraStripList:(BOOL)useExtraStripList {
    if (pStrip != NULL && pStrip->used > 0) {
        NSUInteger index;
        double x, y;
        CGPoint point;
        CPTXYPlotSpace *thePlotSpace = (CPTXYPlotSpace *)self.plotSpace;
        ContourPoints stripContours;
        initContourPoints(&stripContours, 32);
        // check there are only 2 boundary touches, else get rid of outer ones and use inner, else messes up code for
        // splitSelfIntersectingCGPath when a multi-contour path touches itself
        NSUInteger *boundaryPositions;
        if ( closed ) {
            boundaryPositions = (NSUInteger*)calloc(2, sizeof(NSUInteger));
            boundaryPositions[0] = 0;
            boundaryPositions[1] = (NSUInteger)pStrip->used-1;
        }
        else {
            boundaryPositions = (NSUInteger*)calloc(1, sizeof(NSUInteger));
            [contours searchExtraLineStripOfTwoBoundaryPoints:pStrip boundaryPositions:&boundaryPositions];
//            for (NSUInteger pos = 0; pos < (NSUInteger)pStrip->used; pos++) {
//                // retreiving index
//                index = pStrip->array[pos];
//                if ( [contours isNodeOnBoundary:index] ) { // if a border contour should only touch border twice
//                    // yet CPTContour class may have 2 or more boundary points next to each other, for CPTContourPlot can only have 2 border points
//                    boundaryPositions[countBoundaryPositions] = pos;
//                    countBoundaryPositions++;
//                    boundaryPositions = (NSUInteger*)realloc(boundaryPositions, (size_t)(countBoundaryPositions + 1) * sizeof(NSUInteger));
//                }
//            }
//            if ( countBoundaryPositions > 2 ) {
//                NSUInteger pos, pos2, n, i = 0, halfway = countBoundaryPositions / 2;
//                while ( i < halfway ) {
//                    pos = boundaryPositions[i];
//                    pos2 = boundaryPositions[i+1];
//                    if( pos2 - pos < 5 ) {
//                        n = countBoundaryPositions;
//                        if ( i < n ) {
//                            for( NSUInteger j = i + 1; j < n; j++ ) {
//                                boundaryPositions[j-1] = boundaryPositions[j];
//                            }
//                            countBoundaryPositions--;
//                        }
//                    }
//                    i++;
//                }
//                i = countBoundaryPositions - 1;
//                while ( i > 1 ) {
//                    pos = boundaryPositions[i];
//                    pos2 = boundaryPositions[i-1];
//                    if( pos - pos2 < 5 ) {
//                        n = countBoundaryPositions;
//                        if ( i < n ) {
//                            for( NSUInteger j = n-1; j > 1; j-- ) {
//                                boundaryPositions[j] = boundaryPositions[j-1];
//                            }
//                            countBoundaryPositions--;
//                        }
//                    }
//                    i--;
//                }
//            }
        }
        if ( boundaryPositions[0] != NSNotFound && boundaryPositions[1] != NSNotFound) {
            for (NSUInteger pos = boundaryPositions[0]; pos < boundaryPositions[1] + 1; pos++) {
                // retreiving index
                index = pStrip->array[pos];
                // drawing
                x = [contours getXAt:index];
                y = [contours getYAt:index];
                point = CGPointMake(((x - thePlotSpace.xRange.locationDouble) * self.scaleX - self.originOfContext.x) * self.scaleOfContext, ((y - thePlotSpace.yRange.locationDouble) * self.scaleY - self.originOfContext.y) * self.scaleOfContext);
                appendContourPoints(&stripContours, point);
            }
        }
        free(boundaryPositions);
        BOOL pixelAlign = self.alignsPointsToPixels;
        if ( pixelAlign ) {
            [self alignViewPointsToUserSpace:stripContours.array withContext:context numberOfPoints:stripContours.used];
        }
        
        if ( stripContours.used > 0 ) {
            if ( reverse ) {
                reverseContourPoints(&stripContours);
            }
            CGPathRef _dataLinePath = [self newDataLinePathForViewPoints:stripContours.array indexRange: NSMakeRange(0, stripContours.used) extraStripList:useExtraStripList];
            *dataLinePath = CGPathCreateMutableCopy(_dataLinePath);
            CGPathRelease(_dataLinePath);
            *startPoint = CGPointMake(stripContours.array[0].x, stripContours.array[0].y);
            *endPoint = CGPointMake(stripContours.array[stripContours.used - 1].x, stripContours.array[stripContours.used - 1].y);
        }
        freeContourPoints(&stripContours);
    }
}
    
-(nonnull CGMutablePathRef)newDataLinePathForViewPoints:(nonnull CGPoint *)viewPoints indexRange:(NSRange)indexRange extraStripList:(BOOL)isExtraStripList {

    CPTContourPlotInterpolation theInterpolation = self.interpolation;

    if ( theInterpolation == CPTContourPlotInterpolationCurved ) {
        return [self newCurvedDataLinePathForViewPoints:viewPoints indexRange:indexRange];
    }
    CGFloat deltaXLimit;
    CGFloat deltaYLimit;
    if ( [self.dataSource isKindOfClass:[CPTFieldFunctionDataSource class]] ) {
        CPTFieldFunctionDataSource *contourFunctionDataSource = (CPTFieldFunctionDataSource*)self.dataSource;
        deltaXLimit = (CGFloat)self.maxWidthPixels / (CGFloat)[contourFunctionDataSource getDataXCount] * 2.0;
        deltaYLimit = (CGFloat)self.maxHeightPixels / (CGFloat)[contourFunctionDataSource getDataYCount] * 2.0;
    }
    else {
        deltaXLimit = (CGFloat)self.maxWidthPixels / 25.0;
        deltaYLimit = (CGFloat)self.maxWidthPixels / 33.0;
    }
    CGMutablePathRef dataLinePath  = CGPathCreateMutable();
    
    CGPoint lastPoint = viewPoints[indexRange.location];
    CGPathMoveToPoint(dataLinePath, NULL, lastPoint.x, lastPoint.y);
    for ( NSUInteger i = indexRange.location + 1; i < NSMaxRange(indexRange); i++ ) {
        CGPoint viewPoint = viewPoints[i];
        if( CGPointEqualToPoint(viewPoint, lastPoint) ) {
            ;
        }
        else if ( (fabs(lastPoint.x - viewPoint.x) > deltaXLimit || fabs(lastPoint.y - viewPoint.y) > deltaYLimit) && !isExtraStripList ) {
            CGPathMoveToPoint(dataLinePath, NULL, viewPoint.x, viewPoint.y);
//            if ( self.hasDiscontinuity ) {
//                CGPathRelease(dataLinePath);
//                CPTContourPlotCurvedInterpolationOption interpolationOption = self.curvedInterpolationOption;
//                self.curvedInterpolationOption = CPTContourPlotCurvedInterpolationNormal;
//                dataLinePath = [self newCurvedDataLinePathForViewPoints:viewPoints indexRange:indexRange];
//                self.curvedInterpolationOption = interpolationOption;
//                break;
//            }
        }
        else {
            CGPathAddLineToPoint(dataLinePath, NULL, viewPoint.x, viewPoint.y);
        }
        lastPoint = viewPoint;
    }

    return dataLinePath;
}

-(nonnull CGMutablePathRef)newCurvedDataLinePathForViewPoints:(nonnull CGPoint *)viewPoints indexRange:(NSRange)indexRange { CGMutablePathRef dataLinePath  = CGPathCreateMutable();
    BOOL lastPointSkipped          = YES;
//    CGPoint firstPoint             = CGPointZero;
//    CGPoint lastPoint              = CGPointZero;
    NSUInteger firstIndex          = indexRange.location;
    NSUInteger lastDrawnPointIndex = NSMaxRange(indexRange);

    CPTContourPlotCurvedInterpolationOption interpolationOption = self.curvedInterpolationOption;

    if ( lastDrawnPointIndex > 0 ) {
        CGPoint *controlPoints1 = (CGPoint*)calloc(lastDrawnPointIndex, sizeof(CGPoint));
        CGPoint *controlPoints2 = (CGPoint*)calloc(lastDrawnPointIndex, sizeof(CGPoint));

        lastDrawnPointIndex--;

        // Compute control points for each sub-range
        for ( NSUInteger i = indexRange.location; i <= lastDrawnPointIndex; i++ ) {
            CGPoint viewPoint = viewPoints[i];

            if ( isnan(viewPoint.x) || isnan(viewPoint.y) ) {
                if ( !lastPointSkipped ) {
                    switch ( interpolationOption ) {
                        case CPTContourPlotCurvedInterpolationNormal:
                            [self computeBezierControlPoints:controlPoints1
                                                     points2:controlPoints2
                                               forViewPoints:viewPoints
                                                  indexRange:NSMakeRange(firstIndex, i - firstIndex)];
                            break;

                        case CPTContourPlotCurvedInterpolationCatmullRomUniform:
                            [self computeCatmullRomControlPoints:controlPoints1
                                                         points2:controlPoints2
                                                       withAlpha:(CGFloat)0.0
                                                   forViewPoints:viewPoints
                                                      indexRange:NSMakeRange(firstIndex, i - firstIndex)];
                            break;

                        case CPTContourPlotCurvedInterpolationCatmullRomCentripetal:
                            [self computeCatmullRomControlPoints:controlPoints1
                                                         points2:controlPoints2
                                                       withAlpha:(CGFloat)0.5
                                                   forViewPoints:viewPoints
                                                      indexRange:NSMakeRange(firstIndex, i - firstIndex)];
                            break;

                        case CPTContourPlotCurvedInterpolationCatmullRomChordal:
                            [self computeCatmullRomControlPoints:controlPoints1
                                                         points2:controlPoints2
                                                       withAlpha:(CGFloat)1.0
                                                   forViewPoints:viewPoints
                                                      indexRange:NSMakeRange(firstIndex, i - firstIndex)];

                            break;

                        case CPTContourPlotCurvedInterpolationHermiteCubic:
                            [self computeHermiteControlPoints:controlPoints1
                                                      points2:controlPoints2
                                                forViewPoints:viewPoints
                                                   indexRange:NSMakeRange(firstIndex, i - firstIndex)];
                            break;

                        case CPTContourPlotCurvedInterpolationCatmullCustomAlpha:
                            [self computeCatmullRomControlPoints:controlPoints1
                                                         points2:controlPoints2
                                                       withAlpha:self.curvedInterpolationCustomAlpha
                                                   forViewPoints:viewPoints
                                                      indexRange:NSMakeRange(firstIndex, i - firstIndex)];
                            break;
                    }

                    lastPointSkipped = YES;
                }
            }
            else {
                if ( lastPointSkipped ) {
                    lastPointSkipped = NO;
                    firstIndex       = i;
                }
            }
        }

        if ( !lastPointSkipped ) {
            switch ( interpolationOption ) {
                case CPTContourPlotCurvedInterpolationNormal:
                    [self computeBezierControlPoints:controlPoints1
                                             points2:controlPoints2
                                       forViewPoints:viewPoints
                                          indexRange:NSMakeRange(firstIndex, NSMaxRange(indexRange) - firstIndex)];
                    break;

                case CPTContourPlotCurvedInterpolationCatmullRomUniform:
                    [self computeCatmullRomControlPoints:controlPoints1
                                                 points2:controlPoints2
                                               withAlpha:(CGFloat)0.0
                                           forViewPoints:viewPoints
                                              indexRange:NSMakeRange(firstIndex, NSMaxRange(indexRange) - firstIndex)];

                    break;

                case CPTContourPlotCurvedInterpolationCatmullRomCentripetal:
                    [self computeCatmullRomControlPoints:controlPoints1
                                                 points2:controlPoints2
                                               withAlpha:(CGFloat)0.5
                                           forViewPoints:viewPoints
                                              indexRange:NSMakeRange(firstIndex, NSMaxRange(indexRange) - firstIndex)];
                    break;

                case CPTContourPlotCurvedInterpolationCatmullRomChordal:
                    [self computeCatmullRomControlPoints:controlPoints1
                                                 points2:controlPoints2
                                               withAlpha:(CGFloat)1.0
                                           forViewPoints:viewPoints
                                              indexRange:NSMakeRange(firstIndex, NSMaxRange(indexRange) - firstIndex)];

                    break;

                case CPTContourPlotCurvedInterpolationHermiteCubic:
                    [self computeHermiteControlPoints:controlPoints1
                                              points2:controlPoints2
                                        forViewPoints:viewPoints
                                           indexRange:NSMakeRange(firstIndex, NSMaxRange(indexRange) - firstIndex)];
                    break;

                case CPTContourPlotCurvedInterpolationCatmullCustomAlpha:
                    [self computeCatmullRomControlPoints:controlPoints1
                                                 points2:controlPoints2
                                               withAlpha:self.curvedInterpolationCustomAlpha
                                           forViewPoints:viewPoints
                                              indexRange:NSMakeRange(firstIndex, NSMaxRange(indexRange) - firstIndex)];
                    break;
            }
        }

        // Build the path
        lastPointSkipped = YES;
        for ( NSUInteger i = indexRange.location; i <= lastDrawnPointIndex; i++ ) {
            CGPoint viewPoint = viewPoints[i];

            if ( isnan(viewPoint.x) || isnan(viewPoint.y) ) {
                if ( !lastPointSkipped ) {
                    lastPointSkipped = YES;
                }
            }
            else {
                if ( lastPointSkipped ) {
                    CGPathMoveToPoint(dataLinePath, NULL, viewPoint.x, viewPoint.y);
                    lastPointSkipped = NO;
//                    firstPoint       = viewPoint;
                }
                else {
                    CGPoint cp1 = controlPoints1[i];
                    CGPoint cp2 = controlPoints2[i];

#ifdef DEBUG_CURVES
                    CGPoint currentPoint = CGPathGetCurrentPoint(dataLinePath);

                    // add the control points
                    CGPathMoveToPoint(dataLinePath, NULL, cp1.x - CPTFloat(5.0), cp1.y);
                    CGPathAddLineToPoint(dataLinePath, NULL, cp1.x + CPTFloat(5.0), cp1.y);
                    CGPathMoveToPoint(dataLinePath, NULL, cp1.x, cp1.y - CPTFloat(5.0) );
                    CGPathAddLineToPoint(dataLinePath, NULL, cp1.x, cp1.y + CPTFloat(5.0) );

                    CGPathMoveToPoint(dataLinePath, NULL, cp2.x - CPTFloat(3.5), cp2.y - CPTFloat(3.5) );
                    CGPathAddLineToPoint(dataLinePath, NULL, cp2.x + CPTFloat(3.5), cp2.y + CPTFloat(3.5) );
                    CGPathMoveToPoint(dataLinePath, NULL, cp2.x + CPTFloat(3.5), cp2.y - CPTFloat(3.5) );
                    CGPathAddLineToPoint(dataLinePath, NULL, cp2.x - CPTFloat(3.5), cp2.y + CPTFloat(3.5) );

                    // add a line connecting the control points
                    CGPathMoveToPoint(dataLinePath, NULL, cp1.x, cp1.y);
                    CGPathAddLineToPoint(dataLinePath, NULL, cp2.x, cp2.y);

                    CGPathMoveToPoint(dataLinePath, NULL, currentPoint.x, currentPoint.y);
#endif

                    CGPathAddCurveToPoint(dataLinePath, NULL, cp1.x, cp1.y, cp2.x, cp2.y, viewPoint.x, viewPoint.y);
                }
//                lastPoint = viewPoint;
            }
        }

        free(controlPoints1);
        free(controlPoints2);
    }

    return dataLinePath;
}

/** @brief Compute the control points using a catmull-rom spline.
 *  @param points A pointer to the array which should hold the first control points.
 *  @param points2 A pointer to the array which should hold the second control points.
 *  @param alpha The alpha value used for the catmull-rom interpolation.
 *  @param viewPoints A pointer to the array which holds all view points for which the interpolation should be calculated.
 *  @param indexRange The range in which the interpolation should occur.
 *  @warning The @par{indexRange} must be valid for all passed arrays otherwise this method crashes.
 **/
-(void)computeCatmullRomControlPoints:(nonnull CGPoint *)points points2:(nonnull CGPoint *)points2 withAlpha:(CGFloat)alpha forViewPoints:(nonnull CGPoint *)viewPoints indexRange:(NSRange)indexRange {
    if ( indexRange.length >= 2 ) {
        NSUInteger startIndex   = indexRange.location;
        NSUInteger endIndex     = NSMaxRange(indexRange) - 1; // the index starts at zero
        NSUInteger segmentCount = endIndex - 1;               // there are n - 1 segments

        CGFloat epsilon = (CGFloat)1.0e-5; // the minimum point distance. below that no interpolation happens.

        for ( NSUInteger index = startIndex; index <= segmentCount; index++ ) {
            // calculate the control for the segment from index -> index + 1
            CGPoint p0, p1, p2, p3; // the view point

            // the internal points are always valid
            p1 = viewPoints[index];
            p2 = viewPoints[index + 1];
            // account for first and last segment
            if ( index == startIndex ) {
                p0 = p1;
            }
            else {
                p0 = viewPoints[index - 1];
            }
            if ( index == segmentCount ) {
                p3 = p2;
            }
            else {
                p3 = viewPoints[index + 2];
            }

            // distance between the points
            CGFloat d1 = hypot(p1.x - p0.x, p1.y - p0.y);
            CGFloat d2 = hypot(p2.x - p1.x, p2.y - p1.y);
            CGFloat d3 = hypot(p3.x - p2.x, p3.y - p2.y);
            // constants
            CGFloat d1_a  = pow(d1, alpha);            // d1^alpha
            CGFloat d2_a  = pow(d2, alpha);            // d2^alpha
            CGFloat d3_a  = pow(d3, alpha);            // d3^alpha
            CGFloat d1_2a = pow(d1_a, (CGFloat)2.0); // d1^alpha^2 = d1^2*alpha
            CGFloat d2_2a = pow(d2_a, (CGFloat)2.0); // d2^alpha^2 = d2^2*alpha
            CGFloat d3_2a = pow(d3_a, (CGFloat)2.0); // d3^alpha^2 = d3^2*alpha

            // calculate the control points
            // see : http://www.cemyuksel.com/research/catmullrom_param/catmullrom.pdf under point 3.
            CGPoint cp1, cp2; // the calculated view points;
            if ( fabs(d1) <= epsilon ) {
                cp1 = p1;
            }
            else {
                CGFloat divisor = (CGFloat)3.0 * d1_a * (d1_a + d2_a);
                cp1 = CGPointMake((CGFloat)((p2.x * d1_2a - p0.x * d2_2a + (2 * d1_2a + 3 * d1_a * d2_a + d2_2a) * p1.x) / divisor),
                                  (CGFloat)((p2.y * d1_2a - p0.y * d2_2a + (2 * d1_2a + 3 * d1_a * d2_a + d2_2a) * p1.y) / divisor));
            }

            if ( fabs(d3) <= epsilon ) {
                cp2 = p2;
            }
            else {
                CGFloat divisor = (CGFloat)3.0 * d3_a * (d3_a + d2_a);
                cp2 = CGPointMake((CGFloat)((d3_2a * p1.x - d2_2a * p3.x + (2 * d3_2a + 3 * d3_a * d2_a + d2_2a) * p2.x) / divisor),
                                  (CGFloat)((d3_2a * p1.y - d2_2a * p3.y + (2 * d3_2a + 3 * d3_a * d2_a + d2_2a) * p2.y) / divisor));
            }

            points[index + 1]  = cp1;
            points2[index + 1] = cp2;
        }
    }
}

/** @brief Compute the control points using a hermite cubic spline.
 *
 *  If the view points are monotonically increasing or decreasing in both @par{x} and @par{y},
 *  the smoothed curve will be also.
 *
 *  @param points A pointer to the array which should hold the first control points.
 *  @param points2 A pointer to the array which should hold the second control points.
 *  @param viewPoints A pointer to the array which holds all view points for which the interpolation should be calculated.
 *  @param indexRange The range in which the interpolation should occur.
 *  @warning The @par{indexRange} must be valid for all passed arrays otherwise this method crashes.
 **/
-(void)computeHermiteControlPoints:(nonnull CGPoint *)points points2:(nonnull CGPoint *)points2 forViewPoints:(nonnull CGPoint *)viewPoints indexRange:(NSRange)indexRange {
    // See https://en.wikipedia.org/wiki/Cubic_Hermite_spline and https://en.m.wikipedia.org/wiki/Monotone_cubic_interpolation for a discussion of algorithms used.
    if ( indexRange.length >= 2 ) {
        NSUInteger startIndex = indexRange.location;
        NSUInteger lastIndex  = NSMaxRange(indexRange) - 1; // last accessible element in view points

        BOOL monotonic = [self monotonicViewPoints:viewPoints indexRange:indexRange];

        for ( NSUInteger index = startIndex; index <= lastIndex; index++ ) {
            CGVector m;
            CGPoint p1 = viewPoints[index];

            if ( index == startIndex ) {
                CGPoint p2 = viewPoints[index + 1];

                m.dx = p2.x - p1.x;
                m.dy = p2.y - p1.y;
            }
            else if ( index == lastIndex ) {
                CGPoint p0 = viewPoints[index - 1];

                m.dx = p1.x - p0.x;
                m.dy = p1.y - p0.y;
            }
            else { // index > startIndex && index < numberOfPoints
                CGPoint p0 = viewPoints[index - 1];
                CGPoint p2 = viewPoints[index + 1];

                m.dx = p2.x - p0.x;
                m.dy = p2.y - p0.y;

                if ( monotonic ) {
                    if ( m.dx > 0.0 ) {
                        m.dx = MIN(p2.x - p1.x, p1.x - p0.x);
                    }
                    else if ( m.dx < 0.0 ) {
                        m.dx = MAX(p2.x - p1.x, p1.x - p0.x);
                    }

                    if ( m.dy > 0.0 ) {
                        m.dy = MIN(p2.y - p1.y, p1.y - p0.y);
                    }
                    else if ( m.dy < 0.0 ) {
                        m.dy = MAX(p2.y - p1.y, p1.y - p0.y);
                    }
                }
            }

            // get control points
            m.dx /= (CGFloat)6.0;
            m.dy /= (CGFloat)6.0;

            CGPoint rhsControlPoint = CGPointMake((CGFloat)(p1.x + m.dx), (CGFloat)(p1.y + m.dy));
            CGPoint lhsControlPoint = CGPointMake((CGFloat)(p1.x - m.dx), (CGFloat)(p1.y - m.dy));

            // We calculated the lhs & rhs control point. The rhs control point is the first control point for the curve to the next point. The lhs control point is the second control point for the curve to the current point.

            points2[index] = lhsControlPoint;
            if ( index + 1 <= lastIndex ) {
                points[index + 1] = rhsControlPoint;
            }
        }
    }
}

/** @brief Determine whether the plot points form a monotonic series.
 *  @param viewPoints A pointer to the array which holds all view points for which the interpolation should be calculated.
 *  @param indexRange The range in which the interpolation should occur.
 *  @return Returns @YES if the viewpoints are monotonically increasing or decreasing in both @par{x} and @par{y}.
 *  @warning The @par{indexRange} must be valid for all passed arrays otherwise this method crashes.
 **/
-(BOOL)monotonicViewPoints:(nonnull CGPoint *)viewPoints indexRange:(NSRange)indexRange {
    if ( indexRange.length < 2 ) {
        return YES;
    }

    NSUInteger startIndex = indexRange.location;
    NSUInteger lastIndex  = NSMaxRange(indexRange) - 2;

    BOOL foundTrendX   = NO;
    BOOL foundTrendY   = NO;
    BOOL isIncreasingX = NO;
    BOOL isIncreasingY = NO;

    for ( NSUInteger index = startIndex; index <= lastIndex; index++ ) {
        CGPoint p1 = viewPoints[index];
        CGPoint p2 = viewPoints[index + 1];

        if ( !foundTrendX ) {
            if ( p2.x > p1.x ) {
                isIncreasingX = YES;
                foundTrendX   = YES;
            }
            else if ( p2.x < p1.x ) {
                foundTrendX = YES;
            }
        }

        if ( foundTrendX ) {
            if ( isIncreasingX ) {
                if ( p2.x < p1.x ) {
                    return NO;
                }
            }
            else {
                if ( p2.x > p1.x ) {
                    return NO;
                }
            }
        }

        if ( !foundTrendY ) {
            if ( p2.y > p1.y ) {
                isIncreasingY = YES;
                foundTrendY   = YES;
            }
            else if ( p2.y < p1.y ) {
                foundTrendY = YES;
            }
        }

        if ( foundTrendY ) {
            if ( isIncreasingY ) {
                if ( p2.y < p1.y ) {
                    return NO;
                }
            }
            else {
                if ( p2.y > p1.y ) {
                    return NO;
                }
            }
        }
    }

    return YES;
}

// Compute the control points using the algorithm described at http://www.particleincell.com/blog/2012/bezier-splines/
// cp1, cp2, and viewPoints should point to arrays of points with at least NSMaxRange(indexRange) elements each.
-(void)computeBezierControlPoints:(nonnull CGPoint *)cp1 points2:(nonnull CGPoint *)cp2 forViewPoints:(nonnull CGPoint *)viewPoints indexRange:(NSRange)indexRange {
    if ( indexRange.length == 2 ) {
        NSUInteger rangeEnd = NSMaxRange(indexRange) - 1;
        cp1[rangeEnd] = viewPoints[indexRange.location];
        cp2[rangeEnd] = viewPoints[rangeEnd];
    }
    else if ( indexRange.length > 2 ) {
        NSUInteger n = indexRange.length - 1;

        // rhs vector
        CGPoint *a = (CGPoint*)calloc(n, sizeof(CGPoint));
        CGPoint *b = (CGPoint*)calloc(n, sizeof(CGPoint));
        CGPoint *c = (CGPoint*)calloc(n, sizeof(CGPoint));
        CGPoint *r = (CGPoint*)calloc(n, sizeof(CGPoint));

        // left most segment
        a[0] = CGPointZero;
        b[0] = CGPointMake((CGFloat)2.0, (CGFloat)2.0);
        c[0] = CGPointMake((CGFloat)1.0, (CGFloat)1.0);

        CGPoint pt0 = viewPoints[indexRange.location];
        CGPoint pt1 = viewPoints[indexRange.location + 1];
        r[0] = CGPointMake(pt0.x + (CGFloat)2.0 * pt1.x,
                           pt0.y + (CGFloat)2.0 * pt1.y);

        // internal segments
        for ( NSUInteger i = 1; i < n - 1; i++ ) {
            a[i] = CGPointMake(1.0, 1.0);
            b[i] = CGPointMake(4.0, 4.0);
            c[i] = CGPointMake(1.0, 1.0);

            CGPoint pti  = viewPoints[indexRange.location + i];
            CGPoint pti1 = viewPoints[indexRange.location + i + 1];
            r[i] = CGPointMake((CGFloat)4.0 * pti.x + (CGFloat)2.0 * pti1.x,
                               (CGFloat)4.0 * pti.y + (CGFloat)2.0 * pti1.y);
        }

        // right segment
        a[n - 1] = CGPointMake(2.0, 2.0);
        b[n - 1] = CGPointMake(7.0, 7.0);
        c[n - 1] = CGPointZero;

        CGPoint ptn1 = viewPoints[indexRange.location + n - 1];
        CGPoint ptn  = viewPoints[indexRange.location + n];
        r[n - 1] = CGPointMake((CGFloat)8.0 * ptn1.x + ptn.x,
                               (CGFloat)8.0 * ptn1.y + ptn.y);

        // solve Ax=b with the Thomas algorithm (from Wikipedia)
        for ( NSUInteger i = 1; i < n; i++ ) {
            CGPoint m = CGPointMake(a[i].x / b[i - 1].x,
                                    a[i].y / b[i - 1].y);
            b[i] = CGPointMake(b[i].x - m.x * c[i - 1].x,
                               b[i].y - m.y * c[i - 1].y);
            r[i] = CGPointMake(r[i].x - m.x * r[i - 1].x,
                               r[i].y - m.y * r[i - 1].y);
        }

        cp1[indexRange.location + n] = CGPointMake(r[n - 1].x / b[n - 1].x,
                                                   r[n - 1].y / b[n - 1].y);
        for ( NSUInteger i = n - 2; i > 0; i-- ) {
            cp1[indexRange.location + i + 1] = CGPointMake( (r[i].x - c[i].x * cp1[indexRange.location + i + 2].x) / b[i].x,
                                                            (r[i].y - c[i].y * cp1[indexRange.location + i + 2].y) / b[i].y );
        }
        cp1[indexRange.location + 1] = CGPointMake( (r[0].x - c[0].x * cp1[indexRange.location + 2].x) / b[0].x,
                                                    (r[0].y - c[0].y * cp1[indexRange.location + 2].y) / b[0].y );

        // we have p1, now compute p2
        NSUInteger rangeEnd = NSMaxRange(indexRange) - 1;
        for ( NSUInteger i = indexRange.location + 1; i < rangeEnd; i++ ) {
            cp2[i] = CGPointMake((CGFloat)2.0 * viewPoints[i].x - cp1[i + 1].x,
                                 (CGFloat)2.0 * viewPoints[i].y - cp1[i + 1].y);
        }

        cp2[rangeEnd] = CGPointMake((CGFloat)0.5 * (viewPoints[rangeEnd].x + cp1[rangeEnd].x),
                                    (CGFloat)0.5 * (viewPoints[rangeEnd].y + cp1[rangeEnd].y) );

        // clean up
        free(a);
        free(b);
        free(c);
        free(r);
    }
}

/// @endcond

#pragma mark -
#pragma mark Create overlapping CGPath from 2 CGPaths with common edge

/// @cond

-(BOOL) createCGPathFrom2OverlappingPathsWithCommonEdge:(CGPathRef) aPath1 aPath2:(CGPathRef) aPath2 overlapPaths:(CGMutablePathRef**) overlapPaths noOverlapPaths:(NSUInteger*)noOverlapPaths {
    
    BOOL OK = NO;
    // Convert path to an array
    NSMutableArray* a = [NSMutableArray new];
    CGPathApply(aPath1, (__bridge void *)(a), convertToListOfPoints);
    NSMutableArray* b = [NSMutableArray new];
    CGPathApply(aPath2, (__bridge void *)(b), convertToListOfPoints);

    if ( a.count < b.count ) {
        NSMutableArray* temp = [NSMutableArray arrayWithArray:a];
        a = [NSMutableArray arrayWithArray:b];
        b = [NSMutableArray arrayWithArray:temp];
        temp = nil;
    }
    
    // find a point where the 2 CGPaths have a common point
    BOOL breakOut = NO;
    NSUInteger startA = NSNotFound, startB = NSNotFound;
    for ( NSUInteger i = 0; i < a.count; i++ ) {
#if TARGET_OS_OSX
        NSPoint pa =  [(NSValue*)[a objectAtIndex:i] pointValue];
#else
        CGPoint pa =  [(NSValue*)[a objectAtIndex:i] CGPointValue];
#endif
        for ( NSUInteger j = 0; j < b.count; j++ ) {
#if TARGET_OS_OSX
            NSPoint pb =  [(NSValue*)[b objectAtIndex:j] pointValue];
#else
            CGPoint pb =  [(NSValue*)[b objectAtIndex:j] CGPointValue];
#endif
            if ( CGPointEqualToPoint(pa, pb)) {
                startB = j;
                startA = i;
                breakOut = YES;
                break;
            }
        }
        if ( breakOut ) {
            break;
        }
    }
    
    if (startA != NSNotFound && startB != NSNotFound ) {
        if ( startA > 0 ) {
            NSRange firstRangeA = NSMakeRange(0, startA);
            NSArray *firstA = [a subarrayWithRange:firstRangeA];
            [a removeObjectsInRange:firstRangeA];
            [a addObjectsFromArray:firstA];
        }
        if ( startB > 0 ) {
            NSRange firstRangeB = NSMakeRange(0, startB);
            NSArray *firstB = [b subarrayWithRange:firstRangeB];
            [b removeObjectsInRange:firstRangeB];
            [b addObjectsFromArray:firstB];
        }
//        NSPredicate *predicate1 = [NSPredicate predicateWithFormat:/*@"self IN %@ AND self IN %@"*/@"SELF != %@ AND NOT SELF IN %@", a, b];
//        NSArray * __unused c = [a filteredArrayUsingPredicate:predicate1];
//        NSPredicate *predicate2 = [NSPredicate predicateWithFormat:/*@"self IN %@ AND self IN %@"*/@"SELF != %@ AND NOT SELF IN %@", b, a];
//        NSArray * __unused d = [b filteredArrayUsingPredicate:predicate2];
        
        NSIndexSet *setA = [a indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger __unused idx, BOOL * __unused stop) {
            return ![b containsObject:(NSValue *)obj];
        }];
        NSIndexSet *setB = [b indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger __unused idx, BOOL * __unused stop) {
            return ![a containsObject:(NSValue *)obj];
        }];
        
        __block int counterA = 0, counterB = 0;
        __block NSMutableArray *rangesA = [NSMutableArray array], *rangesB = [NSMutableArray array];
        [setA enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull __unused stop) {
            counterA ++;
            [rangesA addObject:[NSValue valueWithRange: range]];
        }];
        [setB enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull __unused stop) {
            counterB ++;
            [rangesB addObject:[NSValue valueWithRange: range]];
        }];
        
        // remove ranges where length is 1
        NSIndexSet *setA1s = [rangesA indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger __unused idx, BOOL * __unused stop) {
            return [((NSValue*)obj) rangeValue].length == 1 ;
        }];
        NSIndexSet *setB1s = [rangesB indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger __unused idx, BOOL * __unused stop) {
            return [((NSValue*)obj) rangeValue].length == 1 ;
        }];
        if (setA1s.count > 0 ) {
            [rangesA removeObjectsAtIndexes:setA1s];
        }
        if (setB1s.count > 0 ) {
            [rangesB removeObjectsAtIndexes:setB1s];
        }
        
        OK = YES;
        if ( rangesA.count > 0 && rangesA.count == rangesB.count ) {
            *overlapPaths = (CGMutablePathRef*)calloc(rangesA.count, sizeof(CGMutablePathRef));
            *noOverlapPaths = rangesA.count;
            
            for ( NSUInteger k = 0; k < rangesA.count; k++ ) {
                CGMutablePathRef overlapPath = CGPathCreateMutable();
                NSRange range = [rangesA[k] rangeValue];
#if TARGET_OS_OSX
                NSPoint pa =  [(NSValue*)[a objectAtIndex:range.location] pointValue];
#else
                CGPoint pa =  [(NSValue*)[a objectAtIndex:range.location] CGPointValue];
#endif
                CGPathMoveToPoint(overlapPath, NULL, pa.x, pa.y);
                for ( NSUInteger l = range.location + 1; l < range.location + range.length; l++ ) {
#if TARGET_OS_OSX
                    NSPoint paa =  [(NSValue*)[a objectAtIndex:l] pointValue];
#else
                    CGPoint paa =  [(NSValue*)[a objectAtIndex:l] CGPointValue];
#endif
                    CGPathAddLineToPoint(overlapPath, NULL, paa.x, paa.y);
                }
                range = [rangesB[k] rangeValue];
                for ( NSUInteger l = range.location + range.length - 1; l >= range.location; l-- ) {
#if TARGET_OS_OSX
                    NSPoint pb =  [(NSValue*)[b objectAtIndex:l] pointValue];
#else
                    CGPoint pb =  [(NSValue*)[b objectAtIndex:l] CGPointValue];
#endif
                    CGPathAddLineToPoint(overlapPath, NULL, pb.x, pb.y);
                }
                CGPathAddLineToPoint(overlapPath, NULL, pa.x, pa.y);
                *(*overlapPaths + k) = CGPathCreateMutableCopy(overlapPath);
                CGPathRelease(overlapPath);
            }
        }
        else {
            OK = NO;
        }
        if ( *noOverlapPaths == 0 ) {
            OK = NO;
        }
//        NSUInteger *divergedAIndices = (NSUInteger*)calloc(1, sizeof(NSUInteger));
//        NSUInteger *divergedBIndices = (NSUInteger*)calloc(1, sizeof(NSUInteger));
//        NSUInteger *convergedAIndices = (NSUInteger*)calloc(1, sizeof(NSUInteger));
//        NSUInteger *convergedBIndices = (NSUInteger*)calloc(1, sizeof(NSUInteger));
//        NSUInteger countDivergedAIndices = 0, countDivergedBIndices = 0, countConvergedAIndices = 0, countConvergedBIndices = 0;
//
//        BOOL diverged = NO;
//        NSUInteger i = startA, j = startB;
//        NSInteger countA = 0, countB = 0;
//        while ( YES ) {
//            // find when 2 arrays diverge
//#if TARGET_OS_OSX
//            NSPoint pa =  [(NSValue*)[a objectAtIndex:i] pointValue];
//            NSPoint pb =  [(NSValue*)[b objectAtIndex:i] pointValue];
//#else
//            CGPoint pa =  [(NSValue*)[a objectAtIndex:i] CGPointValue];
//            CGPoint pb =  [(NSValue*)[b objectAtIndex:j] CGPointValue];
//#endif
//            if ( !diverged && (diverged = !CGPointEqualToPoint(pa, pb)) ) {
//                divergedAIndices[countDivergedAIndices] = i;
//                countDivergedAIndices++;
//                divergedAIndices = (NSUInteger*)realloc(divergedAIndices, (size_t)(countDivergedAIndices+1) * sizeof(NSUInteger));
//                divergedBIndices[countDivergedBIndices] = j;
//                countDivergedBIndices++;
//                divergedBIndices = (NSUInteger*)realloc(divergedBIndices, (size_t)(countDivergedBIndices+1) * sizeof(NSUInteger));
//            }
//            else if ( diverged && CGPointEqualToPoint(pa, pb) ) {
//                convergedAIndices[countConvergedAIndices] = i;
//                countConvergedAIndices++;
//                convergedAIndices = (NSUInteger*)realloc(convergedAIndices, (size_t)(countConvergedAIndices+1) * sizeof(NSUInteger));
//                convergedBIndices[countConvergedBIndices] = j;
//                countConvergedBIndices++;
//                convergedBIndices = (NSUInteger*)realloc(convergedBIndices, (size_t)(countConvergedBIndices+1) * sizeof(NSUInteger));
//                diverged = NO;
//            }
////            printf("%ld %ld\n", i, j);
//            if ( countA == (NSInteger)(a.count) ) {
//                break;
//            }
//
//            countA++;
//            i++;
//            if ( i == a.count ) {
//                i = 0;
//            }
//            countB++;
//            j++;
//            if ( j == b.count ) {
//                j = 0;
//            }
//        }
//        if ( countDivergedAIndices > 0 ) {
//
//            *overlapPaths = (CGMutablePathRef*)calloc(countDivergedAIndices, sizeof(CGMutablePathRef));
//            *noOverlapPaths = countDivergedAIndices;
//
//            for ( NSUInteger k = 0; k < countDivergedAIndices; k++ ) {
//                CGMutablePathRef overlapPath = CGPathCreateMutable();
//#if TARGET_OS_OSX
//                NSPoint pa =  [(NSValue*)[a objectAtIndex:divergedAIndices[k]] pointValue];
//#else
//                CGPoint pa =  [(NSValue*)[a objectAtIndex:divergedAIndices[k]] CGPointValue];
//#endif
//                CGPathMoveToPoint(overlapPath, NULL, pa.x, pa.y);
//                for ( NSUInteger l = divergedAIndices[k] + 1; l < convergedAIndices[k]; l++ ) {
//#if TARGET_OS_OSX
//                    NSPoint paa =  [(NSValue*)[a objectAtIndex:l] pointValue];
//#else
//                    CGPoint paa =  [(NSValue*)[a objectAtIndex:l] CGPointValue];
//#endif
//                    CGPathAddLineToPoint(overlapPath, NULL, paa.x, paa.y);
//                }
//                for ( NSUInteger l = convergedBIndices[k]; l >= divergedBIndices[k]; l-- ) {
//#if TARGET_OS_OSX
//                    NSPoint pb =  [(NSValue*)[b objectAtIndex:l] pointValue];
//#else
//                    CGPoint pb =  [(NSValue*)[b objectAtIndex:l] CGPointValue];
//#endif
//                    CGPathAddLineToPoint(overlapPath, NULL, pb.x, pb.y);
//                }
//                CGPathAddLineToPoint(overlapPath, NULL, pa.x, pa.y);
//
//                *(*overlapPaths + k) = CGPathCreateMutableCopy(overlapPath);
//                CGPathRelease(overlapPath);
//            }
//        }
//
//        free(divergedAIndices);
//        free(divergedBIndices);
//        free(convergedAIndices);
//        free(convergedBIndices);
    }
    return OK;
}

/// @endcond

#pragma mark -
#pragma mark Find CGPath Clockwise or Anti-clockwise

/// @cond

-(BOOL)isCGPathClockwise:(CGPathRef)cgPath {
    NSMutableArray<NSValue*> *bezierPoints = [NSMutableArray array];
    CGPathApply(cgPath, (__bridge void *)bezierPoints, pointsCGPathApplierFunc);
    
    double Ar = 0;//, x = 0, y = 0, x1, y1;
    CGPoint point0, point1;// = bezierPoints[0].CGPointValue;
//    double x0 = point.x;
//    double y0 = point.y;
    NSUInteger j;
    for( NSUInteger i = 0; i < bezierPoints.count; i++ ) {
        j = (i + 1) % bezierPoints.count;
#if TARGET_OS_OSX
        point0 = bezierPoints[i].pointValue;
        point1 = bezierPoints[j].pointValue;
#else
        point0 = bezierPoints[i].CGPointValue;
        point1 = bezierPoints[j].CGPointValue;
#endif
//        x1 = point.x;
//        y1 = point.y;
//        Ar += (x1 - x) * (y1 + y);
//        //Ar += (y1 - y) * (x1 + x) - (x1 - x) * (y1 + y);
//        x = x1;
//        y = y1;
        Ar += point0.x * point1.y;
        Ar -= point1.x * point0.y;
    }
//
//    Ar += (x0 - x) * (y0 + y);
////    Ar += (y0 - y) * (x0 + x) - (x0 - x) * (y0 + y);
    

//    Ar /= 2;
    // result is \int ydex/2 alone the implicit direction.
    if ( Ar < 0 ) {
        return YES;
    }
    else {
        return NO;
    }
}

void pointsCGPathApplierFunc(void *info, const CGPathElement *element) {
    NSMutableArray *bezierPoints = (__bridge NSMutableArray*)info;

    CGPoint *points = element->points;
    CGPathElementType type = element->type;

    switch(type) {
        case kCGPathElementMoveToPoint: // contains 1 point
#if TARGET_OS_OSX
            [bezierPoints addObject:[NSValue valueWithPoint:(NSPoint)points[0]]];
#else
            [bezierPoints addObject:[NSValue valueWithCGPoint:points[0]]];
#endif
            break;

        case kCGPathElementAddLineToPoint: // contains 1 point
#if TARGET_OS_OSX
            [bezierPoints addObject:[NSValue valueWithPoint:(NSPoint)points[0]]];
#else
            [bezierPoints addObject:[NSValue valueWithCGPoint:points[0]]];
#endif
            break;

        case kCGPathElementAddQuadCurveToPoint: // contains 2 points
#if TARGET_OS_OSX
            [bezierPoints addObject:[NSValue valueWithPoint:(NSPoint)points[0]]];
            [bezierPoints addObject:[NSValue valueWithPoint:(NSPoint)points[1]]];
#else
            [bezierPoints addObject:[NSValue valueWithCGPoint:points[0]]];
            [bezierPoints addObject:[NSValue valueWithCGPoint:points[1]]];
#endif
            break;

        case kCGPathElementAddCurveToPoint: // contains 3 points
#if TARGET_OS_OSX
            [bezierPoints addObject:[NSValue valueWithPoint:(NSPoint)points[0]]];
            [bezierPoints addObject:[NSValue valueWithPoint:(NSPoint)points[1]]];
            [bezierPoints addObject:[NSValue valueWithPoint:(NSPoint)points[2]]];
#else
            [bezierPoints addObject:[NSValue valueWithCGPoint:points[0]]];
            [bezierPoints addObject:[NSValue valueWithCGPoint:points[1]]];
            [bezierPoints addObject:[NSValue valueWithCGPoint:points[2]]];
#endif
            break;

        case kCGPathElementCloseSubpath: // contains no point
            break;
    }
}

void multipleMoveTosCGPathApplierFunc(void *info, const CGPathElement *element) {
    NSMutableArray *bezierPoints = (__bridge NSMutableArray*)info;

    CGPoint *points = element->points;
    CGPathElementType type = element->type;

    switch(type) {
        case kCGPathElementMoveToPoint: // contains 1 point
#if TARGET_OS_OSX
            [bezierPoints addObject:[NSValue valueWithPoint:(NSPoint)points[0]]];
#else
            [bezierPoints addObject:[NSValue valueWithCGPoint:points[0]]];
#endif
            break;

        case kCGPathElementAddLineToPoint: // contains 1 point
        case kCGPathElementAddQuadCurveToPoint: // contains 2 points
        case kCGPathElementAddCurveToPoint: // contains 3 points
        case kCGPathElementCloseSubpath: // contains no point
            break;
    }
}

void pathApplierSumCoordinatesOfAllPoints(void* info, const CGPathElement* element) {
    CGFloat* dataArray = (CGFloat*) info;
    CGFloat xTotal = dataArray[0];
    CGFloat yTotal = dataArray[1];
    CGFloat numPoints = dataArray[2];

    switch (element->type) {
        case kCGPathElementMoveToPoint:
        {
            /** for a move to, add the single target point only */

            CGPoint p = element->points[0];
            xTotal += p.x;
            yTotal += p.y;
            numPoints += 1.0;

        }
            break;
        case kCGPathElementAddLineToPoint:
        {
            /** for a line to, add the single target point only */

            CGPoint p = element->points[0];
            xTotal += p.x;
            yTotal += p.y;
            numPoints += 1.0;

        }
            break;
        case kCGPathElementAddQuadCurveToPoint:
            for( int i=0; i<2; i++ ) // note: quad has TWO not THREE
            {
                /** for a curve, we add all ppints, including the control poitns */
                CGPoint p = element->points[i];
                xTotal += p.x;
                yTotal += p.y;
                numPoints += 1.0;
            }
            break;
        case kCGPathElementAddCurveToPoint:
            for( int i=0; i<3; i++ ) // note: cubic has THREE not TWO
            {
                /** for a curve, we add all ppints, including the control poitns */
                CGPoint p = element->points[i];
                xTotal += p.x;
                yTotal += p.y;
                numPoints += 1.0;
            }
            break;
        case kCGPathElementCloseSubpath:
            /** for a close path, do nothing */
            break;
    }

    //NSLog(@"new x=%2.2f, new y=%2.2f, new num=%2.2f", xTotal, yTotal, numPoints);
    dataArray[0] = xTotal;
    dataArray[1] = yTotal;
    dataArray[2] = numPoints;
}


-(void)reverseCGPath:(CGMutablePathRef*)cgPath {
    
    NSMutableArray<NSValue*> *bezierPoints = [NSMutableArray array];
    CGPathApply(*cgPath, (__bridge void *)bezierPoints, pointsCGPathApplierFunc);
    
    if ( bezierPoints.count > 1 ) {
        CGMutablePathRef reversedCGPath = CGPathCreateMutable();
#if TARGET_OS_OSX
        CGPoint point = (CGPoint)bezierPoints[bezierPoints.count-1].pointValue;
#else
        CGPoint point = bezierPoints[bezierPoints.count-1].CGPointValue;
#endif
        CGPathMoveToPoint(reversedCGPath, NULL, point.x, point.y);
    
        for( NSUInteger i = bezierPoints.count - 2; i > 0; i-- ) {
#if TARGET_OS_OSX
            point = (CGPoint)bezierPoints[i].pointValue;
#else
            point = bezierPoints[i].CGPointValue;
#endif
            CGPathAddLineToPoint(reversedCGPath, NULL, point.x, point.y);
        }
#if TARGET_OS_OSX
        point = (CGPoint)bezierPoints[0].pointValue;
#else
        point = bezierPoints[0].CGPointValue;
#endif
        CGPathAddLineToPoint(reversedCGPath, NULL, point.x, point.y);
        
        CGPathRelease(*cgPath);
        *cgPath = CGPathCreateMutableCopy(reversedCGPath);
        
        CGPathRelease(reversedCGPath);
    }
}

-(void)filterBezierPointsBoundaryPoints:(NSMutableArray<NSValue*>*)bezierPoints boundaryPoints:(CGPathBoundaryPoints*)boundaryPoints  leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {
    if( boundaryPoints->size > 0 ) {
        CGPoint point;
        for ( NSUInteger i = 0; i < bezierPoints.count; i++ ) {
#if TARGET_OS_OSX
            point = (CGPoint)bezierPoints[i].pointValue;
#else
            point = bezierPoints[i].CGPointValue;
#endif
            if ( point.x == leftEdge || point.x == rightEdge || point.y == bottomEdge || point.y == topEdge ) {
                CGPathBoundaryPoint boundaryPoint;
                boundaryPoint.point = point;
                boundaryPoint.position = i;
                boundaryPoint.used = 0;
                boundaryPoint.direction = CPTContourBorderDimensionDirectionNone;
                if( point.y == bottomEdge ) {
                    boundaryPoint.direction = CPTContourBorderDimensionDirectionXForward;
                }
                if( point.x == rightEdge ) {
                    boundaryPoint.direction = CPTContourBorderDimensionDirectionYForward;
                }
                if( point.y == topEdge ) {
                    boundaryPoint.direction = CPTContourBorderDimensionDirectionXBackward;
                }
                if( point.x == leftEdge ) {
                    boundaryPoint.direction = CPTContourBorderDimensionDirectionYBackward;
                }
                appendCGPathBoundaryPoints(boundaryPoints, boundaryPoint);
            }
        }
        CGPathBoundaryPoints edgeBorderPoints[4];
        for ( NSUInteger i = 0; i < 4; i++ ) {
            initCGPathBoundaryPoints(&edgeBorderPoints[i], 4);
        }
        BOOL unique[4];
        CGFloat edge[4] = { bottomEdge, rightEdge, topEdge, leftEdge };
        void (*sortFunctions[4])(CGPathBoundaryPoints *a) = { &sortCGPathBoundaryPointsByBottomEdge, &sortCGPathBoundaryPointsByRightEdge, &sortCGPathBoundaryPointsByTopEdge, &sortCGPathBoundaryPointsByLeftEdge };
        for ( NSUInteger i = 0; i < 4; i++ ) {
            filterCGPathBoundaryPoints(boundaryPoints, callbackPlotEdge, &edgeBorderPoints[i], (CPTContourBorderDimensionDirection)i, edge[i]);
            if( (unique[i] = edgeBorderPoints[i].used > 1) ) {
                sortFunctions[i](&edgeBorderPoints[i]);
            }
        }

        clearCGPathBoundaryPoints(boundaryPoints);
        for ( NSUInteger i = 0; i < 4; i++ ) {
            if ( unique[i] ) {
                for( NSUInteger j = 0; j < edgeBorderPoints[i].used; j++ ) {
                    appendCGPathBoundaryPoints(boundaryPoints, edgeBorderPoints[i].array[j]);
                }
            }
            freeCGPathBoundaryPoints(&edgeBorderPoints[i]);
        }
        if ( boundaryPoints->used > 1 ) {
            if ( boundaryPoints->array[0].position == 0 ) {
                CGPathBoundaryPoint firstPoint = boundaryPoints->array[0];
                removeCGPathBoundaryPointsAtIndex(boundaryPoints, 0);
                appendCGPathBoundaryPoints(boundaryPoints, firstPoint);
            }
            CGPathBoundaryPoint lastPoint = boundaryPoints->array[boundaryPoints->used - 1];
            removeCGPathBoundaryPointsAtIndex(boundaryPoints, boundaryPoints->used - 1);
            removeDuplicatesCGPathBoundaryPoints(boundaryPoints);
            insertCGPathBoundaryPointsAtIndex(boundaryPoints, lastPoint, boundaryPoints->used - 1);
        }
    }
}

// since we're dealing with contour lines, should only intersect at the plot border edges
-(NSUInteger) splitSelfIntersectingCGPath:(CGMutablePathRef)originalPath SeparateCGPaths:(CGMutablePathRef**)separatePaths leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge {

    CGAffineTransform transform = CGAffineTransformIdentity;
    NSMutableArray<NSValue*> *bezierPoints = [NSMutableArray array];
    CGPathApply(originalPath, (__bridge void *)bezierPoints, pointsCGPathApplierFunc);
    
    // find points that lie on the boundary
    CGPathBoundaryPoints borderPoints;
    initCGPathBoundaryPoints(&borderPoints, 8);
    CGPoint point;
    for ( NSUInteger i = 0; i < bezierPoints.count; i++ ) {
#if TARGET_OS_OSX
        point = (CGPoint)bezierPoints[i].pointValue;
#else
        point = bezierPoints[i].CGPointValue;
#endif
        if ( point.x == leftEdge || point.x == rightEdge || point.y == bottomEdge || point.y == topEdge ) {
            CGPathBoundaryPoint boundaryPoint;
            boundaryPoint.point = point;
            boundaryPoint.position = i;
            boundaryPoint.used = 0;
            boundaryPoint.direction = CPTContourBorderDimensionDirectionNone;
            if( point.y == bottomEdge ) {
                boundaryPoint.direction = CPTContourBorderDimensionDirectionXForward;
            }
            if( point.x == rightEdge ) {
                boundaryPoint.direction = CPTContourBorderDimensionDirectionYForward;
            }
            if( point.y == topEdge ) {
                boundaryPoint.direction = CPTContourBorderDimensionDirectionXBackward;
            }
            if( point.x == leftEdge ) {
                boundaryPoint.direction = CPTContourBorderDimensionDirectionYBackward;
            }
            appendCGPathBoundaryPoints(&borderPoints, boundaryPoint);
        }
    }
    CGPathBoundaryPoints edgeBorderPoints[4];
    for ( NSUInteger i = 0; i < 4; i++ ) {
        initCGPathBoundaryPoints(&edgeBorderPoints[i], 4);
    }
    BOOL unique[4];
    CGFloat edge[4] = { bottomEdge, rightEdge, topEdge, leftEdge };
    void (*sortFunctions[4])(CGPathBoundaryPoints *a) = { &sortCGPathBoundaryPointsByBottomEdge, &sortCGPathBoundaryPointsByRightEdge, &sortCGPathBoundaryPointsByTopEdge, &sortCGPathBoundaryPointsByLeftEdge };
    for ( NSUInteger i = 0; i < 4; i++ ) {
        filterCGPathBoundaryPoints(&borderPoints, callbackPlotEdge, &edgeBorderPoints[i], (CPTContourBorderDimensionDirection)i, edge[i]);
        if( (unique[i] = edgeBorderPoints[i].used > 1 /*&& edgeBorderPoints[i].used % 2 == 1*/) ) {
            sortFunctions[i](&edgeBorderPoints[i]);
        }
//        unique[i] = edgeBorderPoints[i].used > 1;
    }

    clearCGPathBoundaryPoints(&borderPoints);
    for ( NSUInteger i = 0; i < 4; i++ ) {
        if ( unique[i] ) {
            for( NSUInteger j = 0; j < edgeBorderPoints[i].used; j++ ) {
                appendCGPathBoundaryPoints(&borderPoints, edgeBorderPoints[i].array[j]);
            }
        }
        freeCGPathBoundaryPoints(&edgeBorderPoints[i]);
    }
    //sortCGPathBoundaryPointsByPosition(&borderPoints);
    CGPoint corners[4] = { CGPointMake(leftEdge, bottomEdge), CGPointMake(rightEdge, bottomEdge), CGPointMake(rightEdge, topEdge), CGPointMake(leftEdge, topEdge) };
    
    CGPathBoundaryPoints cornerPoints[4];
    for ( NSUInteger i = 0; i < 4; i++ ) {
        initCGPathBoundaryPoints(&cornerPoints[i], 2);
        filterCGPathBoundaryPointsForACorner(&borderPoints, callbackPlotCorner, &cornerPoints[i], corners[i]);
    }
    
    NSUInteger counter = 0, currentPath = 0;
    if ( borderPoints.used > 0 ) {
        CGMutablePathRef workingCGPath = CGPathCreateMutable();
#if TARGET_OS_OSX
        point = (CGPoint)bezierPoints[0].pointValue;
#else
        point = bezierPoints[0].CGPointValue;
#endif
        CGPathMoveToPoint(workingCGPath, &transform, point.x, point.y);
        NSUInteger i = 1, j = 0;
        while ( i < bezierPoints.count ) {
#if TARGET_OS_OSX
            point = (CGPoint)bezierPoints[i].pointValue;
#else
            point = bezierPoints[i].CGPointValue;
#endif
            if( i == borderPoints.array[j].position ) {
                CGPathAddLineToPoint(workingCGPath, &transform, point.x, point.y);
#if TARGET_OS_OSX
                point = (CGPoint)bezierPoints[borderPoints.array[j+1].position].pointValue;
#else
                point = bezierPoints[borderPoints.array[j+1].position].CGPointValue;
#endif
                CGPathAddLineToPoint(workingCGPath, &transform, point.x, point.y);
                *(*separatePaths + counter) = CGPathCreateMutableCopy(workingCGPath);
                counter++;
                *separatePaths = (CGMutablePathRef*)realloc(*separatePaths, sizeof(CGMutablePathRef) * (size_t)(counter + 1));
                CGPathRelease(workingCGPath);
                if (currentPath != 0 ) {
                    currentPath = 0;
                    workingCGPath = CGPathCreateMutableCopy(**separatePaths);
                }
                else {
                    currentPath = counter;
                    workingCGPath = CGPathCreateMutable();
                    CGPathMoveToPoint(workingCGPath, &transform, point.x, point.y);
                }
#if TARGET_OS_OSX
                point = (CGPoint)bezierPoints[borderPoints.array[j+2].position].pointValue;
#else
                point = bezierPoints[borderPoints.array[j+1].position].CGPointValue;
#endif
                CGPathAddLineToPoint(workingCGPath, &transform, point.x, point.y);
                i++;
            }
            else if(  i == borderPoints.array[j+1].position ) {
                CGPathAddLineToPoint(workingCGPath, &transform, point.x, point.y);
                if ( currentPath == 0 ) {
                    CGPathRelease(**separatePaths);
                    **separatePaths = CGPathCreateMutableCopy(workingCGPath);
                    currentPath = counter;
                    CGPathRelease(workingCGPath);
                    workingCGPath = CGPathCreateMutable();
                    CGPathMoveToPoint(workingCGPath, &transform, point.x, point.y);
                    i++;
                }
                else {
                    *(*separatePaths + counter) = CGPathCreateMutableCopy(workingCGPath);
                    counter++;
                    *separatePaths = (CGMutablePathRef*)realloc(*separatePaths, sizeof(CGMutablePathRef) * (size_t)(counter + 1));
                    currentPath = 0;
                    CGPathRelease(workingCGPath);
                    workingCGPath = CGPathCreateMutableCopy(**separatePaths);
                    j += 3;
                }
            }
            else {
                CGPathAddLineToPoint(workingCGPath, &transform, point.x, point.y);
                i++;
            }
            if ( j >= borderPoints.used || counter > borderPoints.used / 3 + 1 ) {
                break;
            }
        }
        CGPathRelease(**separatePaths);
        **separatePaths = CGPathCreateMutableCopy(workingCGPath);
        CGPathRelease(workingCGPath);
    }
    
    freeCGPathBoundaryPoints(&borderPoints);
    for ( NSUInteger i = 0; i < 4; i++ ) {
        freeCGPathBoundaryPoints(&cornerPoints[i]);
    }
    return counter;
}

-(void)stripCGPathOfExtraMoveTos:(CGMutablePathRef*)cgPath {
    
    CGMutablePathRef newCGPath = CGPathCreateMutable();
    NSMutableArray<NSValue*> *bezierPoints = [NSMutableArray array];
    CGPathApply(*cgPath, (__bridge void *)bezierPoints, pointsCGPathApplierFunc);
    
#if TARGET_OS_OSX
    CGPoint point = (CGPoint)bezierPoints[0].pointValue;
#else
    CGPoint point = bezierPoints[0].CGPointValue;
#endif
    
    CGPathMoveToPoint(newCGPath, NULL, point.x, point.y);
    CGPoint prevPoint = point;
    for( NSUInteger i = 1; i < bezierPoints.count; i++ ) {
#if TARGET_OS_OSX
        point = (CGPoint)bezierPoints[i].pointValue;
#else
        point = bezierPoints[i].CGPointValue;
#endif
        if ( !CGPointEqualToPoint(point, prevPoint) ) {
            CGPathAddLineToPoint(newCGPath, NULL, point.x, point.y);
        }
        prevPoint = point;
    }
    
    CGPathRelease(*cgPath);
    *cgPath = CGPathCreateMutableCopy(newCGPath);
    
    CGPathRelease(newCGPath);
}

- (NSUInteger)createCGPathOfJoinedCGPathsPlanesWithACommonEdge:(CGMutablePathRef*)outerPath innerPaths:(CGMutablePathRef**)innerPaths noInnerPaths:(NSUInteger)noInnerPaths leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge joinedCGPaths:(CGMutablePathRef**)joinedCGPaths usedIndices:(NSUInteger**)usedIndices noUsedIndices:(NSUInteger*)noUsedIndices {
    NSUInteger counter = 0;
    CGAffineTransform transform = CGAffineTransformIdentity;
    NSUInteger *innerPathsIndices = (NSUInteger*)calloc(1, sizeof(NSUInteger));
    NSUInteger countInnerPathsIndices = 0;
   
    if( [self isCGPathClockwise:*outerPath] ) {
        [self reverseCGPath:outerPath];
    }
    CGPoint lastPoint;
    for (NSUInteger i = 0; i < noInnerPaths; i++ ) {
        if ( [self isCGPathClockwise:*(*innerPaths + i)] ) {
            [self reverseCGPath:(*innerPaths + i)];
        }
        lastPoint = CGPathGetCurrentPoint(*(*innerPaths + i));
        if ( CGPathContainsPoint(*outerPath, &transform, lastPoint, YES) ) {
            innerPathsIndices[countInnerPathsIndices] = i;
            countInnerPathsIndices++;
            innerPathsIndices = (NSUInteger*)realloc(innerPathsIndices, (size_t)(countInnerPathsIndices + 1) * sizeof(NSUInteger));
        }
    }
    if( countInnerPathsIndices > 0 ) {
        for ( NSUInteger ii = 0; ii < countInnerPathsIndices; ii++ ) {
            *(*usedIndices + *noUsedIndices) = innerPathsIndices[ii];
            *noUsedIndices = *noUsedIndices + 1;
            *usedIndices = (NSUInteger*)realloc(*usedIndices, (size_t)(*noUsedIndices + 1) * sizeof(NSUInteger));
        }
        
        NSMutableArray<NSValue*> *bezierOuterPoints = [NSMutableArray array];
        CGPathApply(*outerPath, (__bridge void *)bezierOuterPoints, pointsCGPathApplierFunc);
        
        CGPathBoundaryPoints outerBoundaryPoints;
        initCGPathBoundaryPoints(&outerBoundaryPoints, 16);
        [self filterBezierPointsBoundaryPoints:bezierOuterPoints boundaryPoints:&outerBoundaryPoints leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
        
        CGPathBoundaryPoints *innerBoundariesPoints = (CGPathBoundaryPoints*)calloc((size_t)countInnerPathsIndices, sizeof(CGPathBoundaryPoints));
        NSUInteger *counterInnerBoundariesPoints = (NSUInteger*)calloc((size_t)countInnerPathsIndices, sizeof(NSUInteger));
        NSUInteger *startPositionInnerBoundariesPoints = (NSUInteger*)calloc((size_t)countInnerPathsIndices, sizeof(NSUInteger));
        NSUInteger *lastPositionInnerBoundariesPoints = (NSUInteger*)calloc((size_t)countInnerPathsIndices, sizeof(NSUInteger));
        CGPoint *comparisonPoints = (CGPoint*)calloc((size_t)countInnerPathsIndices, sizeof(CGPoint));
        
        NSMutableArray<NSValue*> *bezierInnerPoints = [NSMutableArray array];
        // need to see whether the first or last of innerPaths is next to the end of the outerPath
        // thus allowing correct order to include in overlapPath
        
        for ( NSUInteger ii = 0; ii < countInnerPathsIndices; ii++ ) {
            CGPathApply(*(*innerPaths + innerPathsIndices[ii]), (__bridge void *)bezierInnerPoints, pointsCGPathApplierFunc);
            initCGPathBoundaryPoints(&innerBoundariesPoints[ii], 16);
            [self filterBezierPointsBoundaryPoints:bezierInnerPoints boundaryPoints:&innerBoundariesPoints[ii] leftEdge:leftEdge bottomEdge:bottomEdge rightEdge:rightEdge topEdge:topEdge];
            comparisonPoints[ii] = innerBoundariesPoints[ii].array[0].point;
            counterInnerBoundariesPoints[ii] = 0;
            startPositionInnerBoundariesPoints[ii] = (NSUInteger)innerBoundariesPoints[ii].used - 1;
            lastPositionInnerBoundariesPoints[ii] = 0;
            innerBoundariesPoints[ii].array[startPositionInnerBoundariesPoints[ii]].used = 1;
            [bezierInnerPoints removeAllObjects];
        }
        
        BOOL missPoint = NO, closeOut = NO;
        CGMutablePathRef joinedCGPath;
        CGPoint point, prevPoint, comparisonPoint, nextComparisonPoint, innerPoint = CGPointZero;
        NSUInteger i = 0, j = 0, startPosition = outerBoundaryPoints.used - 1, counterCGPath = 0;
        outerBoundaryPoints.array[startPosition].used = 1;
        while( !(BOOL)outerBoundaryPoints.array[i].used ) {
            counterCGPath = 0;
            joinedCGPath = CGPathCreateMutable();
            closeOut = NO;
            point = outerBoundaryPoints.array[startPosition].point;
            while ( i < outerBoundaryPoints.used - 1 && !(BOOL)outerBoundaryPoints.array[i].used ) {
                prevPoint = point;
                point = outerBoundaryPoints.array[i].point;
                for( j = 0; j < countInnerPathsIndices; j++ ) {
                    if ( counterInnerBoundariesPoints[j] == innerBoundariesPoints[j].used - 1 ) {
                        counterInnerBoundariesPoints[j] = lastPositionInnerBoundariesPoints[j];
                        if ( counterInnerBoundariesPoints[j] == 0 ) {
                            startPositionInnerBoundariesPoints[j] = (NSUInteger)innerBoundariesPoints[j].used - 1;
                        }
                        else {
                            startPositionInnerBoundariesPoints[j] = counterInnerBoundariesPoints[j] - 1;
                        }
                        comparisonPoints[j] = innerBoundariesPoints[j].array[counterInnerBoundariesPoints[j]].point;
                    }
                    while ( counterInnerBoundariesPoints[j] < innerBoundariesPoints[j].used - 1 && !(BOOL)innerBoundariesPoints[j].array[counterInnerBoundariesPoints[j]].used ) {
                        comparisonPoint = comparisonPoints[j];
                        if( (point.y == bottomEdge && prevPoint.y == bottomEdge && comparisonPoint.y == bottomEdge &&  comparisonPoint.x >= prevPoint.x && comparisonPoint.x <= point.x) || (point.y == topEdge && prevPoint.y == topEdge && comparisonPoint.y == topEdge && comparisonPoint.x <= prevPoint.x && comparisonPoint.x >= point.x) || (point.x == leftEdge && prevPoint.x == leftEdge && comparisonPoint.x == leftEdge && comparisonPoint.y >= prevPoint.y && comparisonPoint.y <= point.y) || (point.x == rightEdge && prevPoint.x == rightEdge && comparisonPoint.x == rightEdge && comparisonPoint.y >= prevPoint.y && comparisonPoint.y <= point.y) ) {
                            if ( CGPointEqualToPoint(point, comparisonPoint) ) {
                                missPoint = YES;
                                outerBoundaryPoints.array[i].used = 1;
                            }
                            else {
                                missPoint = NO;
                                if ( counterInnerBoundariesPoints[j] + 1 < innerBoundariesPoints[j].used - 1 ) {
                                    nextComparisonPoint = innerBoundariesPoints[j].array[counterInnerBoundariesPoints[j] + 1].point;
                                    if( ((point.y == bottomEdge && prevPoint.y == bottomEdge && nextComparisonPoint.y == bottomEdge &&  nextComparisonPoint.x >= prevPoint.x && nextComparisonPoint.x <= point.x) || (point.y == topEdge && prevPoint.y == topEdge && nextComparisonPoint.y == topEdge && nextComparisonPoint.x <= prevPoint.x && nextComparisonPoint.x >= point.x) || (point.x == leftEdge && prevPoint.x == leftEdge && nextComparisonPoint.x == leftEdge && nextComparisonPoint.y >= prevPoint.y && nextComparisonPoint.y <= point.y) || (point.x == rightEdge && prevPoint.x == rightEdge && nextComparisonPoint.x == rightEdge && nextComparisonPoint.y >= prevPoint.y && nextComparisonPoint.y <= point.y)) && counterCGPath == 0 ) {
                                        closeOut = YES;
                                        prevPoint = comparisonPoint;
                                        counterInnerBoundariesPoints[j] = counterInnerBoundariesPoints[j] + 1;
                                        if ( startPositionInnerBoundariesPoints[j] == (NSUInteger)innerBoundariesPoints[j].used - 1 ) {
                                            startPositionInnerBoundariesPoints[j] = 0;
                                        }
                                        else {
                                            startPositionInnerBoundariesPoints[j] = startPositionInnerBoundariesPoints[j] + 1;
                                        }
                                        comparisonPoints[j] = innerBoundariesPoints[j].array[counterInnerBoundariesPoints[j]].point;
                                    }
                                    else if ( ((point.y == bottomEdge && comparisonPoint.y == bottomEdge && nextComparisonPoint.y == bottomEdge && point.x >= comparisonPoint.x && point.x <= nextComparisonPoint.x) || (point.y == topEdge && comparisonPoint.y == topEdge && nextComparisonPoint.y == topEdge && point.x <= comparisonPoint.x && point.x >= nextComparisonPoint.x) || (point.x == leftEdge && comparisonPoint.x == leftEdge && nextComparisonPoint.x == leftEdge && point.y >= comparisonPoint.y && point.y <= nextComparisonPoint.y) || (point.x == rightEdge && comparisonPoint.x == rightEdge && nextComparisonPoint.x == rightEdge && point.y >= comparisonPoint.y && point.y <= nextComparisonPoint.y)) && counterCGPath == 0  ) {
                                        prevPoint = nextComparisonPoint;
                                        counterInnerBoundariesPoints[j] = counterInnerBoundariesPoints[j] + 1;
                                        if ( startPositionInnerBoundariesPoints[j] == (NSUInteger)innerBoundariesPoints[j].used - 1 ) {
                                            startPositionInnerBoundariesPoints[j] = 0;
                                        }
                                        else {
                                            startPositionInnerBoundariesPoints[j] = startPositionInnerBoundariesPoints[j] + 1;
                                        }
                                        comparisonPoints[j] = innerBoundariesPoints[j].array[counterInnerBoundariesPoints[j]].point;
                                    }
                                }
                                if ( counterCGPath == 0 ) {
                                    CGPathMoveToPoint(joinedCGPath, &transform, prevPoint.x, prevPoint.y);
                                }
                                else {
                                    CGPathAddLineToPoint(joinedCGPath, &transform, prevPoint.x, prevPoint.y);
                                }
                                lastPoint = prevPoint;
                                CGPathApply(*(*innerPaths + innerPathsIndices[j]), (__bridge void *)bezierInnerPoints, pointsCGPathApplierFunc);
                                for ( NSInteger k = (NSInteger)innerBoundariesPoints[j].array[counterInnerBoundariesPoints[j]].position; k >= (NSInteger)innerBoundariesPoints[j].array[startPositionInnerBoundariesPoints[j]].position; k--) {
#if TARGET_OS_OSX
                                    innerPoint = (CGPoint)[[bezierInnerPoints objectAtIndex:(NSUInteger)k] pointValue];
#else
                                    innerPoint = [[bezierInnerPoints objectAtIndex:(NSUInteger)k] CGPointValue];
#endif
                                    CGPathAddLineToPoint(joinedCGPath, &transform, innerPoint.x, innerPoint.y);
                                    counterCGPath++;
                                }
                                if ( closeOut ) {
                                    if ( !CGPathIsEmpty(joinedCGPath) ) {
                                        [self addCGPath:joinedCGPath cgPaths:joinedCGPaths counter:&counter];
                                    }
                                    CGPathRelease(joinedCGPath);
                                    joinedCGPath = CGPathCreateMutable();
                                    innerBoundariesPoints[j].array[startPositionInnerBoundariesPoints[j]].used = 1;
                                    counterCGPath = 0;
                                    closeOut = NO;
                                }
                                else {
                                    CGPoint pt = outerBoundaryPoints.array[i == 0 ? outerBoundaryPoints.used - 1 : i - 1].point, prevPt;
                                    for( NSUInteger k = i; k < (NSUInteger)outerBoundaryPoints.used; k++ ) {
                                        prevPt = pt;
                                        pt = outerBoundaryPoints.array[k].point;
                                        if( (pt.y == bottomEdge && prevPt.y == bottomEdge && innerPoint.y == bottomEdge && innerPoint.x >= prevPt.x && innerPoint.x <= pt.x) || (pt.y == topEdge && prevPt.y == topEdge && innerPoint.y == topEdge && innerPoint.x <= prevPt.x && innerPoint.x >= pt.x) || (pt.x == leftEdge && prevPt.x == leftEdge && innerPoint.x == leftEdge && innerPoint.y <= prevPt.y && innerPoint.y >= pt.y) || (pt.x == rightEdge && prevPt.x == rightEdge && innerPoint.x == rightEdge && innerPoint.y >= prevPt.y && innerPoint.y <= pt.y) ) {
                                            startPosition = k;
                                            i = k + 1;
                                            prevPoint = outerBoundaryPoints.array[startPosition].point;
                                            point = outerBoundaryPoints.array[i].point;
                                            break;
                                        }
                                    }
                                }
                            }
                            innerBoundariesPoints[j].array[counterInnerBoundariesPoints[j]].used = 1;
                            lastPositionInnerBoundariesPoints[j] = counterInnerBoundariesPoints[j] + 1;
                        }
                        counterInnerBoundariesPoints[j] = counterInnerBoundariesPoints[j] + 1;
                        if ( startPositionInnerBoundariesPoints[j] == (NSUInteger)innerBoundariesPoints[j].used - 1 ) {
                            startPositionInnerBoundariesPoints[j] = 0;
                        }
                        else {
                            startPositionInnerBoundariesPoints[j] = startPositionInnerBoundariesPoints[j] + 1;
                        }
                        comparisonPoints[j] = innerBoundariesPoints[j].array[counterInnerBoundariesPoints[j]].point;
                        if ( counterInnerBoundariesPoints[j] > innerBoundariesPoints[j].used - 1 ) {
                            [bezierInnerPoints removeAllObjects];
                            break;
                        }
                    }
                }
                if ( !missPoint ) {
                    outerBoundaryPoints.array[startPosition].used = 1;
                    outerBoundaryPoints.array[i].used = 1;
                    NSUInteger start;
                    if ( counterCGPath == 0 ) {
                        CGPathMoveToPoint(joinedCGPath, &transform, prevPoint.x, prevPoint.y);
                        start = outerBoundaryPoints.array[startPosition].position + 1;
                    }
                    else {
                        start = outerBoundaryPoints.array[startPosition].position;
                    }
                    for( NSUInteger k = start; k <= outerBoundaryPoints.array[i].position; k++ ) {
#if TARGET_OS_OSX
                        point = (CGPoint)[[bezierOuterPoints objectAtIndex:k] pointValue];
#else
                        point = [[bezierOuterPoints objectAtIndex:k] CGPointValue];
#endif
                        CGPathAddLineToPoint(joinedCGPath, &transform, point.x, point.y);
                        counterCGPath++;
                    }
                }
                startPosition = i;
                i++;
            }
            if ( missPoint ) {
                CGPathAddLineToPoint(joinedCGPath, &transform, lastPoint.x, lastPoint.y); ;
            }
            else {
#if TARGET_OS_OSX
                point = (CGPoint)[[bezierOuterPoints objectAtIndex:outerBoundaryPoints.array[i].position] pointValue];
#else
                point = [[bezierOuterPoints objectAtIndex:outerBoundaryPoints.array[i].position] CGPointValue];
#endif
                CGPathAddLineToPoint(joinedCGPath, &transform, point.x, point.y);
            }
            if ( !CGPathIsEmpty(joinedCGPath) ) {
                [self addCGPath:joinedCGPath cgPaths:joinedCGPaths counter:&counter];
            }
            CGPathRelease(joinedCGPath);
            i = 0; // now find first outerBoundaryPoints that hasn't been used
            while ( YES ) {
                if ( !(BOOL)outerBoundaryPoints.array[i].used ) {
                    startPosition = i - 1;
                    break;
                }
                i++;
                if ( i > outerBoundaryPoints.used - 1 ) {
                    break;
                }
            }
            if ( i > outerBoundaryPoints.used - 1 ) {
                break;
            }
        }
        [bezierOuterPoints removeAllObjects];
        bezierOuterPoints = nil;
        
        for ( NSUInteger ii = 0; ii < countInnerPathsIndices; ii++ ) {
            freeCGPathBoundaryPoints(&innerBoundariesPoints[ii]);
        }
        free(innerBoundariesPoints);
        free(comparisonPoints);
        free(counterInnerBoundariesPoints);
        free(startPositionInnerBoundariesPoints);
        free(lastPositionInnerBoundariesPoints);
        freeCGPathBoundaryPoints(&outerBoundaryPoints);
    }
    free(innerPathsIndices);
    return counter;
}

- (void)addCGPath:(CGMutablePathRef)newCGPath cgPaths:(CGMutablePathRef**)cgPaths counter:(NSUInteger*)counter {
    *(*cgPaths + *counter) = CGPathCreateMutableCopy(newCGPath);
    *counter = *counter + 1;
    *cgPaths = (CGMutablePathRef*)realloc(*cgPaths, (size_t)(*counter + 1) * sizeof(CGMutablePathRef));
}

- (BOOL)createCGPathOfJoinedCGPathsPlanesWithACommonEdge1:(CGMutablePathRef)outerPath innerPaths:(CGMutablePathRef*)innerPaths noInnerPaths:(NSUInteger)noInnerPaths leftEdge:(CGFloat)leftEdge bottomEdge:(CGFloat)bottomEdge rightEdge:(CGFloat)rightEdge topEdge:(CGFloat)topEdge joinedCGPath:(CGMutablePathRef*)joinedCGPath usedIndices:(NSUInteger**)usedIndices noUsedIndices:(NSUInteger*)noUsedIndices {
    BOOL hasOverlap = NO;
    CGAffineTransform transform = CGAffineTransformIdentity;
    NSUInteger *innerPathsIndices = (NSUInteger*)calloc(1, sizeof(NSUInteger));
    NSUInteger countInnerPathsIndices = 0;
    CGPoint lastPoint;
    
    for (NSUInteger i = 0; i < noInnerPaths; i++ ) {
        
        lastPoint = CGPathGetCurrentPoint(innerPaths[i]);
        if ( CGPathContainsPoint(outerPath, &transform, lastPoint, YES) ) {
            innerPathsIndices[countInnerPathsIndices] = i;
            countInnerPathsIndices++;
            innerPathsIndices = (NSUInteger*)realloc(innerPathsIndices, (size_t)(countInnerPathsIndices + 1) * sizeof(NSUInteger));
        }
    }
    if( countInnerPathsIndices > 0 ) {
        for ( NSUInteger ii = 0; ii < countInnerPathsIndices; ii++ ) {
            *(*usedIndices + *noUsedIndices) = innerPathsIndices[ii];
            *noUsedIndices = *noUsedIndices + 1;
            *usedIndices = (NSUInteger*)realloc(*usedIndices, (size_t)(*noUsedIndices + 1) * sizeof(NSUInteger));
        }
        
        hasOverlap = YES;
        NSMutableArray<NSValue*> *bezierOuterPoints = [NSMutableArray array];
        CGPathApply(outerPath, (__bridge void *)bezierOuterPoints, pointsCGPathApplierFunc);
        
        NSUInteger *positionsOuterPath = (NSUInteger*)calloc(1, sizeof(NSUInteger));
        NSUInteger i = 0, counterPositionsOuterPath = 0;
        CGPoint point, prevPoint;
        for( NSValue *value in bezierOuterPoints) {
#if TARGET_OS_OSX
            point = (CGPoint)[value pointValue];
#else
            point = [value CGPointValue];
#endif
            if ( point.x == leftEdge || point.x == rightEdge || point.y == bottomEdge || point.y == topEdge ) {
                positionsOuterPath[counterPositionsOuterPath] = i;
                counterPositionsOuterPath++;
                positionsOuterPath = (NSUInteger*)realloc(positionsOuterPath, ((size_t)counterPositionsOuterPath + 1) * sizeof(NSUInteger));
            }
            i++;
        }
        
        NSUInteger **positionsInnerPaths = (NSUInteger**)calloc((size_t)countInnerPathsIndices, sizeof(NSUInteger*));
        NSUInteger *counterPositionsInnerPaths = (NSUInteger*)calloc((size_t)countInnerPathsIndices, sizeof(NSUInteger));
        NSMutableArray<NSValue*> *bezierInnerPoints;
        // need to see whether the first or last of innerPaths is next to the end of the outerPath
        // thus allowing correct order to include in overlapPath
        
        for ( NSUInteger ii = 0; ii < countInnerPathsIndices; ii++ ) {
            bezierInnerPoints = [NSMutableArray array];
            CGPathApply(innerPaths[innerPathsIndices[ii]], (__bridge void *)bezierInnerPoints, pointsCGPathApplierFunc);
            positionsInnerPaths[ii] = (NSUInteger*)calloc(1, sizeof(NSUInteger));
            NSUInteger j = 0;
            counterPositionsInnerPaths[ii] = 0;
            for( NSValue *value in bezierInnerPoints) {
#if TARGET_OS_OSX
                point = (CGPoint)[value pointValue];
#else
                point = [value CGPointValue];
#endif
                if ( point.x == leftEdge || point.x == rightEdge || point.y == bottomEdge || point.y == topEdge ) {
                    positionsInnerPaths[ii][counterPositionsInnerPaths[ii]] = j;
                    counterPositionsInnerPaths[ii] = counterPositionsInnerPaths[ii] + 1;
                    positionsInnerPaths[ii] = (NSUInteger*)realloc(positionsInnerPaths[ii], ((size_t)counterPositionsInnerPaths[ii] + 1) * sizeof(NSUInteger));
                }
                j++;
            }
            [bezierInnerPoints removeAllObjects];
            bezierInnerPoints = nil;
        }
        NSUInteger index;
        BOOL reverseOrder = NO;
        if( countInnerPathsIndices > 0 ) {
            CGPoint innerStartPoint, innerEndPoint;
            bezierInnerPoints = [NSMutableArray array];
            CGPathApply(innerPaths[innerPathsIndices[0]], (__bridge void *)bezierInnerPoints, pointsCGPathApplierFunc);
#if TARGET_OS_OSX
            innerStartPoint = (CGPoint)[[bezierInnerPoints objectAtIndex:positionsInnerPaths[0][0]] pointValue];
#else
            innerStartPoint = [[bezierInnerPoints objectAtIndex:positionsInnerPaths[0][0]] CGPointValue];
#endif
            [bezierInnerPoints removeAllObjects];
            CGPathApply(innerPaths[innerPathsIndices[countInnerPathsIndices - 1]], (__bridge void *)bezierInnerPoints, pointsCGPathApplierFunc);
#if TARGET_OS_OSX
            innerEndPoint = (CGPoint)[[bezierInnerPoints objectAtIndex:positionsInnerPaths[countInnerPathsIndices-1][1]] pointValue];
#else
            innerEndPoint = [[bezierInnerPoints objectAtIndex:positionsInnerPaths[countInnerPathsIndices-1][1]] CGPointValue];
#endif
            [bezierInnerPoints removeAllObjects];
            bezierInnerPoints = nil;

#if TARGET_OS_OSX
            prevPoint = (CGPoint)[[bezierOuterPoints objectAtIndex:positionsOuterPath[1]] pointValue];
#else
            prevPoint = [[bezierOuterPoints objectAtIndex:positionsOuterPath[1]] CGPointValue];
#endif
            BOOL innerStartPointFirst = NO, innerEndPointFirst = NO;
            for( i = 2; i < counterPositionsOuterPath; i++ ) {
                index = positionsOuterPath[i];
#if TARGET_OS_OSX
                point = (CGPoint)[[bezierOuterPoints objectAtIndex:index] pointValue];
#else
                point = [[bezierOuterPoints objectAtIndex:index] CGPointValue];
#endif
                if ( (innerStartPoint.x >= prevPoint.x && innerStartPoint.x <= point.x && ((point.y == bottomEdge && prevPoint.y == bottomEdge && innerStartPoint.y == bottomEdge) || (point.y == topEdge && prevPoint.y == topEdge && innerStartPoint.y == topEdge))) || (innerStartPoint.y >= prevPoint.y && innerStartPoint.y <= point.y && ((point.x == leftEdge && prevPoint.x == leftEdge && innerStartPoint.x == leftEdge) || (point.x == rightEdge && prevPoint.x == rightEdge && innerStartPoint.x == rightEdge))) ) {
                    innerStartPointFirst = YES;
                }
                if ( (innerEndPoint.x >= prevPoint.x && innerEndPoint.x <= point.x && ((point.y == bottomEdge && prevPoint.y == bottomEdge && innerEndPoint.y == bottomEdge) || (point.y == topEdge && prevPoint.y == topEdge && innerEndPoint.y == topEdge))) || (innerEndPoint.y >= prevPoint.y && innerEndPoint.y <= point.y && ((point.x == leftEdge && prevPoint.x == leftEdge && innerEndPoint.x == leftEdge) || (point.x == rightEdge && prevPoint.x == rightEdge && innerEndPoint.x == rightEdge))) ) {
                    innerEndPointFirst = YES;
                }
                if ( innerStartPointFirst && innerEndPointFirst ) {
                    CGFloat distInnerStartPoint = sqrt(pow(innerStartPoint.x - prevPoint.x, 2.0) + pow(innerStartPoint.y - prevPoint.y, 2.0));
                    CGFloat distInnerEndPoint = sqrt(pow(innerEndPoint.x - prevPoint.x, 2.0) + pow(innerEndPoint.y - prevPoint.y, 2.0));
                    if ( distInnerEndPoint > distInnerStartPoint ) {
                        innerEndPointFirst = NO;
                    }
                    break;
                }
                else if ( innerStartPointFirst || innerEndPointFirst ) {
                    break;
                }
                prevPoint = point;
            }
            reverseOrder = innerEndPointFirst;
        }
        
        *joinedCGPath = CGPathCreateMutable();
#if TARGET_OS_OSX
        point = (CGPoint)[[bezierOuterPoints objectAtIndex:0] pointValue];
#else
        point = [[bezierOuterPoints objectAtIndex:0] CGPointValue];
#endif
        CGPathMoveToPoint(*joinedCGPath, &transform, point.x, point.y);
        NSInteger nextInnerPathIndex = reverseOrder ? (NSInteger)countInnerPathsIndices - 1 : 0;
        NSInteger innerPathCounter = reverseOrder ? (NSInteger)counterPositionsInnerPaths[nextInnerPathIndex] - 2 : 1;
        
        bezierInnerPoints = [NSMutableArray array];
        CGPathApply(innerPaths[innerPathsIndices[nextInnerPathIndex]], (__bridge void *)bezierInnerPoints, pointsCGPathApplierFunc);
        CGPoint innerPoint = CGPointZero;
#if TARGET_OS_OSX
        CGPoint comparisonPoint = (CGPoint)[[bezierInnerPoints objectAtIndex:positionsInnerPaths[nextInnerPathIndex][reverseOrder ? counterPositionsInnerPaths[nextInnerPathIndex] - 1 : 0]] pointValue];
#else
        CGPoint comparisonPoint = [[bezierInnerPoints objectAtIndex:positionsInnerPaths[nextInnerPathIndex][reverseOrder ? counterPositionsInnerPaths[nextInnerPathIndex] - 1 : 0]] CGPointValue];
#endif
        for( i = 1; i < positionsOuterPath[1]; i++ ) {
#if TARGET_OS_OSX
            point = (CGPoint)[[bezierOuterPoints objectAtIndex:i] pointValue];
#else
            point = [[bezierOuterPoints objectAtIndex:i] CGPointValue];
#endif
            CGPathAddLineToPoint(*joinedCGPath, &transform, point.x, point.y);
        }
        
        for( i = 2; i < counterPositionsOuterPath; i++ ) {
            index = positionsOuterPath[i];
            prevPoint = point;
#if TARGET_OS_OSX
            point = (CGPoint)[[bezierOuterPoints objectAtIndex:index] pointValue];
#else
            point = [[bezierOuterPoints objectAtIndex:index] CGPointValue];
#endif
            while (  reverseOrder ? nextInnerPathIndex > - 1 : nextInnerPathIndex < (NSInteger)countInnerPathsIndices ) {
                if( (point.y == bottomEdge && prevPoint.y == bottomEdge && comparisonPoint.y == bottomEdge && ((!reverseOrder && comparisonPoint.x >= prevPoint.x && comparisonPoint.x <= point.x) || (reverseOrder && comparisonPoint.x <= prevPoint.x && comparisonPoint.x >= point.x))) || (point.y == topEdge && prevPoint.y == topEdge && comparisonPoint.y == topEdge && ((!reverseOrder && comparisonPoint.x <= prevPoint.x && comparisonPoint.x >= point.x) || (reverseOrder && comparisonPoint.x >= prevPoint.x && comparisonPoint.x <= point.x))) || (point.x == leftEdge && prevPoint.x == leftEdge && comparisonPoint.x == leftEdge && ((!reverseOrder && comparisonPoint.y >= prevPoint.y && comparisonPoint.y <= point.y) || (reverseOrder && comparisonPoint.y <= prevPoint.y && comparisonPoint.y >= point.y))) || (point.x == rightEdge && prevPoint.x == rightEdge && comparisonPoint.x == rightEdge && ((!reverseOrder && comparisonPoint.y >= prevPoint.y && comparisonPoint.y <= point.y) || (reverseOrder && comparisonPoint.y <= prevPoint.y && comparisonPoint.y >= point.y))) ) {
                    if ( reverseOrder ) {
                        for ( NSInteger j = (NSInteger)positionsInnerPaths[nextInnerPathIndex][innerPathCounter/*counterPositionsInnerPaths[nextInnerPathIndex] - 1*/] /*- 1*/; j > -1; j-- ) {
#if TARGET_OS_OSX
                            innerPoint = (CGPoint)[[bezierInnerPoints objectAtIndex:(NSUInteger)j] pointValue];
#else
                            innerPoint = [[bezierInnerPoints objectAtIndex:(NSUInteger)j] CGPointValue];
#endif
                            CGPathAddLineToPoint(*joinedCGPath, &transform, innerPoint.x, innerPoint.y);
                        }
                    }
                    else {
                        for ( NSUInteger j = 0; j <= positionsInnerPaths[nextInnerPathIndex][innerPathCounter/*counterPositionsInnerPaths[nextInnerPathIndex] - 1*/]; j++ ) {
#if TARGET_OS_OSX
                            innerPoint = (CGPoint)[[bezierInnerPoints objectAtIndex:(NSUInteger)j] pointValue];
#else
                            innerPoint = [[bezierInnerPoints objectAtIndex:(NSUInteger)j] CGPointValue];
#endif
                            CGPathAddLineToPoint(*joinedCGPath, &transform, innerPoint.x, innerPoint.y);
                        }
                    }
                    prevPoint = innerPoint;
                    if ( reverseOrder ) {
                        innerPathCounter--;
                        if ( innerPathCounter < 0 ) {
                            nextInnerPathIndex--;
                            innerPathCounter = (NSInteger)counterPositionsInnerPaths[nextInnerPathIndex] - 1;
                        }
                    }
                    else {
                        innerPathCounter++;
                        if ( innerPathCounter > (NSInteger)counterPositionsInnerPaths[nextInnerPathIndex] - 1 ) {
                            nextInnerPathIndex++;
                            innerPathCounter = 1;
                        }
                    }
                    
                    if ( (reverseOrder && nextInnerPathIndex > -1) || (!reverseOrder && nextInnerPathIndex < (NSInteger)countInnerPathsIndices) ) {
                        if ( (reverseOrder && innerPathCounter == (NSInteger)counterPositionsInnerPaths[nextInnerPathIndex] - 1) || (!reverseOrder && innerPathCounter == 1) ) {
                            [bezierInnerPoints removeAllObjects];
                            CGPathApply(innerPaths[innerPathsIndices[nextInnerPathIndex]], (__bridge void *)bezierInnerPoints, pointsCGPathApplierFunc);
                        }
//                        comparisonPoint = [[bezierInnerPoints objectAtIndex:positionsInnerPaths[nextInnerPathIndex][reverseOrder ? counterPositionsInnerPaths[nextInnerPathIndex] - 1 : 0]] CGPointValue];
#if TARGET_OS_OSX
                        comparisonPoint = (CGPoint)[[bezierInnerPoints objectAtIndex:positionsInnerPaths[nextInnerPathIndex][innerPathCounter]] pointValue];
#else
                        comparisonPoint = [[bezierInnerPoints objectAtIndex:positionsInnerPaths[nextInnerPathIndex][innerPathCounter]] CGPointValue];
#endif
                    }
//                    else {
//                        CGPathAddLineToPoint(*joinedCGPath, &transform, point.x, point.y);
//                        break;
//                    }
                }
                else {
                    for( NSUInteger j = positionsOuterPath[i-1]; j <= positionsOuterPath[i]; j++ ) {
#if TARGET_OS_OSX
                        point = (CGPoint)[[bezierOuterPoints objectAtIndex:j] pointValue];
#else
                        point = [[bezierOuterPoints objectAtIndex:j] CGPointValue];
#endif
                        CGPathAddLineToPoint(*joinedCGPath, &transform, point.x, point.y);
                    }
                    break;
                }
            }
            if ( reverseOrder ? nextInnerPathIndex < 0 : nextInnerPathIndex == (NSInteger)countInnerPathsIndices ) {
                for( NSUInteger j = positionsOuterPath[i-1]; j < positionsOuterPath[i]; j++ ) {
#if TARGET_OS_OSX
                        point = (CGPoint)[[bezierOuterPoints objectAtIndex:j] pointValue];
#else
                        point = [[bezierOuterPoints objectAtIndex:j] CGPointValue];
#endif
                    CGPathAddLineToPoint(*joinedCGPath, &transform, point.x, point.y);
                }
            }
        }
#if TARGET_OS_OSX
        point = (CGPoint)[[bezierOuterPoints objectAtIndex:0] pointValue];
#else
        point = [[bezierOuterPoints objectAtIndex:0] CGPointValue];
#endif
        CGPathAddLineToPoint(*joinedCGPath, &transform, point.x, point.y);
        [bezierOuterPoints removeAllObjects];
        bezierOuterPoints = nil;
        for( i = 0; i < countInnerPathsIndices; i++ ) {
            free(positionsInnerPaths[i]);
        }
        free(positionsInnerPaths);
        free(counterPositionsInnerPaths);
        free(positionsOuterPath);
    }
    free(innerPathsIndices);
    return hasOverlap;
}

- (BOOL)checkCGPathHasCGPoint:(CGPathRef)path point:(CGPoint)point {
    BOOL hasPoint = NO;
    
    NSMutableArray<NSValue*> *bezierPoints = [NSMutableArray array];
    CGPathApply(path, (__bridge void *)bezierPoints, pointsCGPathApplierFunc);
    
    CGPoint pathPoint;
    for( NSUInteger i = 0; i < bezierPoints.count; i++ ) {
#if TARGET_OS_OSX
        pathPoint = (CGPoint)bezierPoints[i].pointValue;
#else
        pathPoint = bezierPoints[i].CGPointValue;
#endif
        if ( CGPointEqualToPoint(pathPoint, point) ) {
            hasPoint = YES;
            break;
        }
    }
    return hasPoint;
}

/// @endcond

#pragma mark -
#pragma mark Rotational direction from one node to another

-(CPTContourBetweenNodeRotation)rotationBetweenVector:(CGVector)a toAnother:(CGVector)b {
    // now get the cross product
    CGFloat cross = a.dx * b.dy - a.dy * b.dx;
    CPTContourBetweenNodeRotation rotation = CPTContourBetweenNodeRotationNone;
    if(cross > 0) {
        rotation = CPTContourBetweenNodeRotationClockwise;
    }
    else if (cross < 0) {
        rotation = CPTContourBetweenNodeRotationAnticlockwise;
    }
    return rotation;
}

#pragma mark -
#pragma mark Animation

/// @cond

//+(BOOL)needsDisplayForKey:(nonnull NSString *)aKey
//{
//    static NSSet<NSString *> *keys   = nil;
//    static dispatch_once_t onceToken = 0;
//
//    dispatch_once(&onceToken, ^{
//        keys = [NSSet setWithArray:@[@"arrowSize",
//                                     @"arrowType"]];
//    });
//
//    if ( [keys containsObject:aKey] ) {
//        return YES;
//    }
//    else {
//        return [super needsDisplayForKey:aKey];
//    }
//}

/// @endcond

#pragma mark -
#pragma mark Fields

/// @cond

-(NSUInteger)numberOfFields {
    return 3;
}

-(nonnull CPTNumberArray *)fieldIdentifiers {
    return @[@(CPTContourPlotFieldX),
             @(CPTContourPlotFieldY),
             @(CPTContourPlotFieldFunctionValue)];
}

-(nonnull CPTNumberArray *)fieldIdentifiersForCoordinate:(CPTCoordinate)coord {
    CPTNumberArray *result = nil;

    switch ( coord ) {
        case CPTCoordinateX:
            result = @[@(CPTContourPlotFieldX)];
            break;

        case CPTCoordinateY:
            result = @[@(CPTContourPlotFieldY)];
            break;
            
        case CPTCoordinateZ:
            result = @[@(CPTContourPlotFieldFunctionValue)];
            break;

        default:
            [NSException raise:CPTException format:@"Invalid coordinate passed to fieldIdentifiersForCoordinate:"];
            break;
    }
    return result;
}

-(CPTCoordinate)coordinateForFieldIdentifier:(NSUInteger)field {
    CPTCoordinate coordinate = CPTCoordinateNone;

    switch ( field ) {
        case CPTContourPlotFieldX:
            coordinate = CPTCoordinateX;
            break;

        case CPTContourPlotFieldY:
            coordinate = CPTCoordinateY;
            break;
        
        case CPTContourPlotFieldFunctionValue:
            coordinate = CPTCoordinateZ;
            break;

        default:
            break;
    }

    return coordinate;
}

/// @endcond

#pragma mark -
#pragma mark Legend Draw Swatch

-(void)drawSwatchForLegend:(nonnull CPTLegend *)legend atIndex:(NSUInteger)idx inRect:(CGRect)rect inContext:(nonnull CGContextRef)context {
    if ( self.fillIsoCurves && self.isoCurvesIndices ) {
        
        id<CPTLegendDelegate> theDelegate = (id<CPTLegendDelegate>)legend.delegate;
        
        NSUInteger index = [[legend getLegendEntries] indexOfObjectPassingTest:^BOOL(CPTLegendEntry * _Nonnull obj, NSUInteger __unused  _idx, BOOL * _Nonnull __unused  stop) {
            return obj.indexCustomised == idx;
        }];
        if ( index == NSNotFound ) {
            index = 0;
        }
        
        CPTLegendEntry *legendEntry = [[legend getLegendEntries] objectAtIndex:index];
        if ( legendEntry.indexCustomised != NSNotFound ) {
            CPTFill *theSwatchFill = nil;
            if ( self.isoCurvesFillings.count > 1 ) {
                CPTContourFill *filling = [self.isoCurvesFillings objectAtIndex:index];
                theSwatchFill = filling.fill;
                if ( !theSwatchFill ) {
                    theSwatchFill = legend.swatchFill;
                }

                CPTLineStyle *theSwatchLineStyle = nil;

                if ( [theDelegate respondsToSelector:@selector(legend:lineStyleForSwatchAtIndex:forPlot:)] ) {
                    theSwatchLineStyle = [theDelegate legend:legend lineStyleForSwatchAtIndex:legendEntry.indexCustomised forPlot:self];
                }
                if ( !theSwatchLineStyle ) {
                    theSwatchLineStyle = legend.swatchBorderLineStyle;
                }

                if ( theSwatchFill || theSwatchLineStyle ) {
                    CGFloat radius = legend.swatchCornerRadius;

                    if ( theSwatchFill ) {
                        CGContextBeginPath(context);
                        CPTAddRoundedRectPath(context, CPTAlignIntegralRectToUserSpace(context, rect), radius);
                        [theSwatchFill fillPathInContext:context];
                    }

                    if ( theSwatchLineStyle ) {
                        [theSwatchLineStyle setLineStyleInContext:context];
                        CGContextBeginPath(context);
                        CPTAddRoundedRectPath(context, CPTAlignBorderedRectToUserSpace(context, rect, theSwatchLineStyle), radius);
                        [theSwatchLineStyle strokePathInContext:context];
                    }
                }
            }
            else if ( legendEntry.indexCustomised != NSNotFound && legendEntry.indexCustomised >= [[self.isoCurvesIndices firstObject] unsignedIntegerValue] && legendEntry.indexCustomised <= [[self.isoCurvesIndices lastObject] unsignedIntegerValue] ) {
    
                if ( [theDelegate respondsToSelector:@selector(legend:fillForSwatchAtIndex:forPlot:)] ) {
                    theSwatchFill = [theDelegate legend:legend fillForSwatchAtIndex:legendEntry.indexCustomised forPlot:self];
                }
                if ( !theSwatchFill ) {
                    id nilObject                    = [CPTPlot nilData];
                    CGFloat r1, g1, b1, a1;
                    if ( legendEntry.indexCustomised == [[self.isoCurvesIndices firstObject] unsignedIntegerValue] ) {
                        if ( [self.isoCurvesFills firstObject] == nilObject ) {
                            CPTLineStyle *lineStyle = [self.isoCurvesLineStyles firstObject];
                            CPTColor *colour = [lineStyle lineColor];
#if TARGET_OS_OSX
                            [[colour nsColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#else
                            [[colour uiColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#endif
                            colour = [colour colorWithAlphaComponent:a1 / 2];
                            theSwatchFill = [CPTFill fillWithColor:colour];
                        }
                        else {
                            theSwatchFill = [self.isoCurvesFills firstObject];
                        }
                    }
                    else if ( legendEntry.indexCustomised == [[self.isoCurvesIndices lastObject] unsignedIntegerValue] ) {
                        if ( [self.isoCurvesFills firstObject] == nilObject ) {
                            CPTLineStyle *lineStyle = [self.isoCurvesLineStyles lastObject];
                            CPTColor *colour = [lineStyle lineColor];
#if TARGET_OS_OSX
                            [[colour nsColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#else
                            [[colour uiColor] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
#endif
                            colour = [colour colorWithAlphaComponent:a1 / 2];
                            theSwatchFill = [CPTFill fillWithColor:colour];
                        }
                        else {
                            theSwatchFill = [self.isoCurvesFills objectAtIndex:self.isoCurvesFills.count - 1];
                        }
                    }
                    else {
                        if ( [self.isoCurvesFills firstObject] == nilObject ) {
                            CPTLineStyle *lineStyle1 = [self.isoCurvesLineStyles objectAtIndex: legendEntry.indexCustomised - 1];
                            CPTLineStyle *lineStyle2 = [self.isoCurvesLineStyles objectAtIndex: legendEntry.indexCustomised];
#if TARGET_OS_OSX
                            NSColor *colour1 = [[lineStyle1 lineColor] nsColor];
                            NSColor *colour2 = [[lineStyle2 lineColor] nsColor];
#else
                            UIColor *colour1 = [[lineStyle1 lineColor] uiColor];
                            UIColor *colour2 = [[lineStyle2 lineColor] uiColor];
#endif
                            CGFloat r2, g2, b2, a2;
                            [colour1 getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
                            [colour2 getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
        //                    CGFloat alpha2 = MIN( 1.0, MAX( 0.0, a2 ) );
        //                    CGFloat beta = 1.0 - alpha2;
        //                    CGFloat red     = r1 * beta + r2 * alpha2;
        //                    CGFloat green   = g1 * beta + g2 * alpha2;
        //                    CGFloat blue    = b1 * beta + b2 * alpha2;
        //                    CGFloat alpha   = a1 * beta + a2 * alpha2;
                            CGFloat red     = (r2 + r1) / 2;
                            CGFloat green   = (g2 + g1) / 2;
                            CGFloat blue    = (b2 + b1) / 2;
                            CGFloat alpha   = (a2 + a1) / 4;
                            CPTColor *colour = [CPTColor colorWithComponentRed:red green:green blue:blue alpha:alpha];
                            theSwatchFill = [CPTFill fillWithColor:colour];
                        }
                        else {
                            theSwatchFill = [self.isoCurvesFills objectAtIndex:legendEntry.indexCustomised];
                        }
                    }
                }
                if ( !theSwatchFill ) {
                    theSwatchFill = legend.swatchFill;
                }

                CPTLineStyle *theSwatchLineStyle = nil;

                if ( [theDelegate respondsToSelector:@selector(legend:lineStyleForSwatchAtIndex:forPlot:)] ) {
                    theSwatchLineStyle = [theDelegate legend:legend lineStyleForSwatchAtIndex:legendEntry.indexCustomised forPlot:self];
                }
                if ( !theSwatchLineStyle ) {
                    theSwatchLineStyle = legend.swatchBorderLineStyle;
                }

                if ( theSwatchFill || theSwatchLineStyle ) {
                    CGFloat radius = legend.swatchCornerRadius;

                    if ( theSwatchFill ) {
                        CGContextBeginPath(context);
                        CPTAddRoundedRectPath(context, CPTAlignIntegralRectToUserSpace(context, rect), radius);
                        [theSwatchFill fillPathInContext:context];
                    }

                    if ( theSwatchLineStyle ) {
                        [theSwatchLineStyle setLineStyleInContext:context];
                        CGContextBeginPath(context);
                        CPTAddRoundedRectPath(context, CPTAlignBorderedRectToUserSpace(context, rect, theSwatchLineStyle), radius);
                        [theSwatchLineStyle strokePathInContext:context];
                    }
                }
            }
            else {
                [super drawSwatchForLegend:legend atIndex:idx inRect:rect inContext:context];
            }
        }
        else {
            [super drawSwatchForLegend:legend atIndex:idx inRect:rect inContext:context];
        }
    }
    else {
        [super drawSwatchForLegend:legend atIndex:idx inRect:rect inContext:context];
    }

    if ( !self.fillIsoCurves && self.drawLegendSwatchDecoration /*&& self.isoCurvesIndices.count > 0 && idx < self.isoCurvesIndices.count*/ ) {
//        NSUInteger index = [[self.isoCurvesIndices objectAtIndex:idx] unsignedIntegerValue];
        CPTLineStyle *theContourLineStyle = self.isoCurveLineStyle;
        if ( /*index*/idx < self.isoCurvesLineStyles.count && [self.isoCurvesLineStyles objectAtIndex:/*index*/idx] != [CPTPlot nilData] ) {
            theContourLineStyle = [self isoCurveLineStyleForIndex:/*index*/idx];
        }

        if ( theContourLineStyle ) {
            [theContourLineStyle setLineStyleInContext:context];

            CGPoint alignedStartPoint = CPTAlignPointToUserSpace(context, CGPointMake((CGFloat)CGRectGetMinX(rect), (CGFloat)CGRectGetMidY(rect) ) );
            CGPoint alignedEndPoint   = CPTAlignPointToUserSpace(context, CGPointMake((CGFloat)CGRectGetMaxX(rect), (CGFloat)CGRectGetMidY(rect) ) );
            CGContextMoveToPoint(context, alignedStartPoint.x, alignedStartPoint.y);
            CGContextAddLineToPoint(context, alignedEndPoint.x, alignedEndPoint.y);

            [theContourLineStyle strokePathInContext:context];
        }
    }
}

#pragma mark -
#pragma mark Ovveride DataLabels method
/// @cond

-(void)updateContentAnchorForLabel:(nonnull CPTPlotSpaceAnnotation *)label
{
    if ( label && self.adjustLabelAnchors ) {
        label.contentAnchorPoint = CPTPointMake(0.75, 0.35);
    }
}

/// @endcond

#pragma mark -
#pragma mark isoCurve Labels

/**
 *  @brief Marks the receiver as needing to update all data labels before the content is next drawn.
 *  @see @link CPTPlot::relabelIndexRange: -relabelIndexRange: @endlink
 **/
-(void)setIsoCurvesNeedsRelabel {
    self.isoCurvesLabelIndexRange = NSMakeRange(0, self.isoCurvesValues.count);
    self.needsIsoCurvesRelabel    = YES;
}

/**
 *  @brief Updates the iso Curves labels in the labelIndexRange.
 **/
-(void)reLabelIsoCurves {
    if ( !self.needsIsoCurvesRelabel ) {
        return;
    }

    self.needsIsoCurvesRelabel = NO;

    id nullObject         = [NSNull null];
    Class nullClass       = [NSNull class];
    Class annotationClass = [CPTAnnotation class];

    CPTTextStyle *labelTextStyle = self.isoCurvesLabelTextStyle;
    NSFormatter *labelFormatter  = self.isoCurvesLabelFormatter;
    
    // clean out isoCurveLabels from this plot annotations actual plotted labels array & self.isoCurvesLabelAnnotations
    for ( CPTMutableAnnotationArray *annotations in self.isoCurvesLabelAnnotations ) {
        for ( CPTAnnotation *annotation in annotations ) {
            if ( [annotation isKindOfClass:annotationClass] ) {
                [self removeAnnotation:annotation];
            }
        }
        [annotations removeAllObjects];
    }
    [self.isoCurvesLabelAnnotations removeAllObjects];
    
    if ( !self.showIsoCurvesLabels || (self.isoCurvesValues != nil && self.noActualIsoCurves != self.isoCurvesValues.count) ) {
        self.isoCurvesLabelAnnotations = nil;
        return;
    }
    
    CPTDictionary *textAttributes = labelTextStyle.attributes;
    BOOL hasAttributedFormatter   = ([labelFormatter attributedStringForObjectValue:[NSDecimalNumber zero] withDefaultAttributes:textAttributes] != nil);

    NSUInteger sampleCount = self.isoCurvesValues.count;
    NSRange indexRange     = self.isoCurvesLabelIndexRange;
    NSUInteger maxIndex    = NSMaxRange(indexRange);

    if ( !self.isoCurvesLabelAnnotations ) {
        self.isoCurvesLabelAnnotations = [NSMutableArray arrayWithCapacity:sampleCount];
    }

    CPTPlotSpace *thePlotSpace            = self.plotSpace;
    CGFloat theRotation                   = self.isoCurvesLabelRotation;
    NSMutableArray *labelAnnotationsArray = self.isoCurvesLabelAnnotations;
//    NSUInteger oldLabelCount              = labelAnnotationsArray.count;
    id nilObject                          = [CPTPlot nilData];

    CPTShadow *theShadow                       = self.isoCurvesLabelShadow;
    
    self.drawnIsoCurvesLabelsPositions = [CPTMutableValueArray new];

    for ( NSUInteger i = indexRange.location; i < maxIndex; i++ ) {
        NSNumber *dataValue = [self.isoCurvesValues objectAtIndex:i];
        CPTTextLayer *newLabelLayer;
        if ( isnan([dataValue doubleValue]) ) {
            newLabelLayer = nil;
        }
        else {
            newLabelLayer = (CPTTextLayer*)[self.isoCurvesLabels objectAtIndex:i];

            if ( ( (newLabelLayer == nil) || (newLabelLayer == nilObject) ) && (labelTextStyle && labelFormatter) ) {
                if ( hasAttributedFormatter ) {
                    NSAttributedString *labelString = [labelFormatter attributedStringForObjectValue:dataValue withDefaultAttributes:textAttributes];
                    newLabelLayer = [[CPTTextLayer alloc] initWithAttributedText:labelString];
                }
                else {
                    NSString *labelString = [labelFormatter stringForObjectValue:dataValue];
                    if ( labelTextStyle.color == nil ) {
                        CPTMutableTextStyle *mutLabelTextStyle = [CPTMutableTextStyle textStyleWithStyle: labelTextStyle];
                        mutLabelTextStyle.color = [CPTColor colorWithComponentRed:(CGFloat)((float)i / (float)self.isoCurvesLabels.count) green:(CGFloat)(1.0f - (float)i / (float)self.isoCurvesLabels.count) blue:0.0 alpha:1.0];
                        newLabelLayer = [[CPTTextLayer alloc] initWithText:labelString style:mutLabelTextStyle];
                    }
                    else {
                        newLabelLayer = [[CPTTextLayer alloc] initWithText:labelString style:labelTextStyle];
                    }
                }
            }

            if ( [newLabelLayer isKindOfClass:nullClass] || (newLabelLayer == nilObject) ) {
                newLabelLayer = nil;
            }
        }

        newLabelLayer.shadow = theShadow;
        
        

//        if ( i < oldLabelCount ) {
//            for( NSUInteger j = 0; j < [[self.isoCurvesNoStrips objectAtIndex:i] unsignedIntegerValue]; j++ ) {
//                CPTPlotSpaceAnnotation *labelAnnotation = [[labelAnnotationsArray objectAtIndex:i] objectAtIndex:j];
//                if ( newLabelLayer ) {
//                    if ( [labelAnnotation isKindOfClass:nullClass] ) {
//                        labelAnnotation = [[CPTPlotSpaceAnnotation alloc] initWithPlotSpace:thePlotSpace anchorPlotPoint:nil];
//                        if ( j < [[labelAnnotationsArray objectAtIndex:i] count] ) {
//                            [[labelAnnotationsArray objectAtIndex:i] replaceObjectAtIndex:j withObject:labelAnnotation];
//                        }
//                        else {
//                            [[labelAnnotationsArray objectAtIndex:i] addObject:labelAnnotation];
//                        }
//                        [self addAnnotation:labelAnnotation];
//                    }
//                }
//                else {
//                    if ( [labelAnnotation isKindOfClass:annotationClass] ) {
//                        if ( j < [[labelAnnotationsArray objectAtIndex:i] count] ) {
//                            [[labelAnnotationsArray objectAtIndex:i] replaceObjectAtIndex:j withObject:nullObject];
//                        }
//                        else {
//                            [[labelAnnotationsArray objectAtIndex:i] addObject:nullObject];
//                        }
//                        [self removeAnnotation:labelAnnotation];
//                    }
//                }
//            }
//        }
//        else {
            CPTMutableAnnotationArray *stripAnnotations = [CPTMutableAnnotationArray arrayWithCapacity:[[self.isoCurvesNoStrips objectAtIndex:i] unsignedIntegerValue]];
            [labelAnnotationsArray addObject:stripAnnotations];
            for(NSUInteger j = 0; j < [[self.isoCurvesNoStrips objectAtIndex:i] unsignedIntegerValue]; j++) {
                if ( newLabelLayer ) {
                    CPTPlotSpaceAnnotation *labelAnnotation = [[CPTPlotSpaceAnnotation alloc] initWithPlotSpace:thePlotSpace anchorPlotPoint:nil];
                    [[labelAnnotationsArray objectAtIndex:i] addObject:labelAnnotation];
                    [self addAnnotation:labelAnnotation];
                }
                else {
                    [[labelAnnotationsArray objectAtIndex:i] addObject:nullObject];
                }
            }
//        }

        if ( newLabelLayer ) {
            for(NSUInteger j = 0; j < [[self.isoCurvesNoStrips objectAtIndex:i] unsignedIntegerValue]; j++) {
                CPTPlotSpaceAnnotation *labelAnnotation = [[labelAnnotationsArray objectAtIndex:i] objectAtIndex:j];
                CPTTextLayer* labelLayer = [[CPTTextLayer alloc] initWithLayer:newLabelLayer];
                labelLayer.bounds = newLabelLayer.bounds;
                labelAnnotation.contentLayer = labelLayer;
                
                if ( self.isoCurvesLabelsRotations != nil && [[[self.isoCurvesLabelsRotations objectAtIndex:i] objectAtIndex:j] isKindOfClass:[NSNumber class]]) {
                    labelAnnotation.rotation     = (CGFloat)[(NSNumber*)[[self.isoCurvesLabelsRotations objectAtIndex:i] objectAtIndex:j] doubleValue];
                }
                else {
                    labelAnnotation.rotation     = theRotation;
                }
                [self positionIsoCurvesLabelAnnotation:labelAnnotation forStrip:i forIndex:j];
            }
        }
    }
    
    

    // remove parent labels that are no longer needed from
//    while ( labelAnnotationsArray.count > sampleCount ) {
//        CPTMutableAnnotationArray *oldAnnotations = labelAnnotationsArray[labelAnnotationsArray.count - 1];
//        for(NSUInteger j = 0; j < oldAnnotations.count; j++) {
//            CPTAnnotation *oldAnnotation = oldAnnotations[j];
//            if ( [oldAnnotation isKindOfClass:annotationClass] ) {
//                [self removeAnnotation:oldAnnotation];
//            }
//            [oldAnnotations removeObject:oldAnnotation];
//        }
//        [labelAnnotationsArray removeLastObject];
//    }
    CPTGraph *theGraph = self.graph;
    if ( theGraph.allowTracking ) {
        [self updateIsoCurveTrackingAreas];
    }
}

-(void)updateIsoCurveTrackingAreas {
    CPTGraph *theGraph = self.graph;
    if ( theGraph.allowTracking ) {
        CPTPlotSpace *thePlotSpace            = self.plotSpace;
#if TARGET_OS_OSX
        CPTGraphHostingView *theGraphHostingView = theGraph.hostingView;
        NSView *view = (NSView*)theGraphHostingView;
        NSIndexSet *plotTrackingAreasIndices = [view.trackingAreas indexesOfObjectsPassingTest:^BOOL(NSTrackingArea *area, NSUInteger __unused idx, BOOL * __unused stop) {
            NSDictionary *dict = area.userInfo;
            return [(NSString*)[dict objectForKey:@"plotidentifier"] isEqual:(NSString*)self.identifier] && [(NSString*)[dict objectForKey:@"type"] isEqual:@"isocurvelabel"];
        }];
        if ( plotTrackingAreasIndices != nil ) {
            NSUInteger index = [plotTrackingAreasIndices lastIndex];
            while (index != NSNotFound) {
                [view removeTrackingArea:[view.trackingAreas objectAtIndex:index]];
                index = [plotTrackingAreasIndices indexLessThanIndex:index];
            }
        }
        for ( CPTMutableAnnotationArray *annotations in self.isoCurvesLabelAnnotations ) {
            for ( CPTAnnotation *annotation in annotations ) {
                if ( ![annotation isKindOfClass: [NSNull class]]) {
                    CPTPlotSpaceAnnotation *plotSpaceAnnotation = (CPTPlotSpaceAnnotation*)annotation;
                    CPTNumberArray *anchorPlotPoint = plotSpaceAnnotation.anchorPlotPoint;
                    if ( anchorPlotPoint ) {
                        CGPoint origin = [thePlotSpace plotAreaViewPointForPlotPoint:anchorPlotPoint];
                        CGRect trackingRect = CGRectMake(origin.x, origin.y, plotSpaceAnnotation.contentLayer.frame.size.width, plotSpaceAnnotation.contentLayer.frame.size.width);
                        NSString *message = [NSString stringWithFormat:@"Isocurve\nValue: %@", ((CPTTextLayer*)plotSpaceAnnotation.contentLayer).text];
                        NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:trackingRect options:NSTrackingActiveAlways|NSTrackingMouseEnteredAndExited owner:self userInfo:@{ @"message" : message, @"annotation" : @"CPTPlotSpaceAnnotation", @"plotspace": thePlotSpace, @"plotidentifier": (NSString*)self.identifier, @"type": @"isocurvelabel" }];
                        [view addTrackingArea:trackingArea];
                    }
                }
            }
        }
#else
        CPTGraphHostingView *theGraphHostingView = theGraph.hostingView;
        UIView *view = (UIView*)theGraphHostingView;
        NSIndexSet *plotTrackingAreasIndices = [theGraph.pointerRegions indexesOfObjectsPassingTest:^BOOL(UIPointerRegion *area, NSUInteger __unused idx, BOOL * __unused stop) {
            NSDictionary *dict = (NSDictionary*)area.identifier;
            return [(NSString*)[dict objectForKey:@"plotidentifier"] isEqual:(NSString*)self.identifier] && [(NSString*)[dict objectForKey:@"type"] isEqual:@"isocurvelabel"];
        }];
        NSUInteger index = [plotTrackingAreasIndices lastIndex];
        while (index != NSNotFound) {
            [theGraph.pointerRegions removeObjectAtIndex:index];
            index = [plotTrackingAreasIndices indexLessThanIndex:index];
        }
        
        for ( CPTMutableAnnotationArray *annotations in self.isoCurvesLabelAnnotations ) {
            for ( CPTAnnotation *annotation in annotations ) {
                if ( ![annotation isKindOfClass: [NSNull class]]) {
                    CPTPlotSpaceAnnotation *plotSpaceAnnotation = (CPTPlotSpaceAnnotation*)annotation;
                    CPTNumberArray *anchorPlotPoint = plotSpaceAnnotation.anchorPlotPoint;
                    if ( anchorPlotPoint ) {
                        CGPoint origin = [thePlotSpace plotAreaViewPointForPlotPoint:anchorPlotPoint];
                        origin = [self convertPoint:origin toLayer:view.layer];
                        CGRect trackingRect = CGRectMake(origin.x, origin.y, plotSpaceAnnotation.contentLayer.frame.size.width, plotSpaceAnnotation.contentLayer.frame.size.width);
                        NSString *message = [NSString stringWithFormat:@"Isocurve\nValue: %@", ((CPTTextLayer*)plotSpaceAnnotation.contentLayer).text];
                        UIPointerRegion *pointerRegion =  [UIPointerRegion regionWithRect:trackingRect identifier:@{ @"message" : message, @"annotation" : @"CPTPlotSpaceAnnotation", @"plotspace": thePlotSpace, @"plotidentifier": (NSString*)self.identifier, @"type": @"isocurvelabel" }];
                        [theGraph.pointerRegions addObject:pointerRegion];
                    }
                }
            }
        }
#endif
    }
}

/** @brief Marks the receiver as needing to update a range of isCurves labels before the content is next drawn.
 *  @param indexRange The index range needing update.
 *  @see setNeedsRelabel()
 **/
-(void)relabelIsoCurvesIndexRange:(NSRange)indexRange {
    self.isoCurvesLabelIndexRange = indexRange;
    self.needsIsoCurvesRelabel = YES;
}

/// @cond

-(void)updateContentAnchorForIsoCurvesLabel:(nonnull CPTPlotSpaceAnnotation *)label {
    if ( label /*&& self.adjustIsoCurvesLabelAnchors*/ ) {
        CGPoint displacement = label.displacement;
        if ( CGPointEqualToPoint(displacement, CGPointZero) ) {
            displacement.y = (CGFloat)1.0; // put the label above the data point if zero displacement
        }
        CGFloat angle      = (CGFloat)M_PI + atan2(displacement.y, displacement.x) - label.rotation;
        CGFloat newAnchorX = cos(angle);
        CGFloat newAnchorY = sin(angle);

        if ( ABS(newAnchorX) <= ABS(newAnchorY) ) {
            newAnchorX /= ABS(newAnchorY);
            newAnchorY  = signbit(newAnchorY) ? (CGFloat)-1.0 : (CGFloat)1.0;
        }
        else {
            newAnchorY /= ABS(newAnchorX);
            newAnchorX  = signbit(newAnchorX) ? (CGFloat)-1.0 : (CGFloat)1.0;
        }

        label.contentAnchorPoint = CGPointMake( (newAnchorX + (CGFloat)1.0 ) / (CGFloat)2.0, (newAnchorY + (CGFloat)1.0 ) / (CGFloat)2.0 );
    }
}

/// @endcond

/// @cond


-(void)positionLabelAnnotation:(nonnull CPTPlotSpaceAnnotation *)label forIndex:(NSUInteger)idx {
    NSNumber *xValue = [self cachedNumberForField:CPTContourPlotFieldX recordIndex:idx];
    NSNumber *yValue = [self cachedNumberForField:CPTContourPlotFieldY recordIndex:idx];
    
    BOOL positiveDirection = YES;
    CPTPlotRange *yRange   = [self.plotSpace plotRangeForCoordinate:CPTCoordinateY];

    if ( CPTDecimalLessThan(yRange.lengthDecimal, CPTDecimalFromInteger(0) ) ) {
        positiveDirection = !positiveDirection;
    }

    label.contentLayer.hidden = self.hidden || isnan([xValue doubleValue]) || isnan([yValue doubleValue]);
    label.anchorPlotPoint     = @[xValue, yValue];

    if ( positiveDirection ) {
        label.displacement = CGPointMake(0.0, (CGFloat)self.labelOffset);
    }
    else {
        label.displacement = CGPointMake(0.0, (CGFloat)-self.labelOffset);
    }
}

-(void)positionIsoCurvesLabelAnnotation:(nonnull CPTPlotSpaceAnnotation *)label forStrip:(NSUInteger)strip forIndex:(NSUInteger)idx {
    id nullObject         = [NSNull null];
    if( self.isoCurvesLabelsPositions != nil && [[self.isoCurvesLabelsPositions objectAtIndex:strip] objectAtIndex:idx] != nullObject ) {
        NSValue *positionValue = [[self.isoCurvesLabelsPositions objectAtIndex:strip] objectAtIndex:idx];
#if TARGET_OS_OSX
        NSPoint position = [positionValue pointValue];
#else
        CGPoint position = [positionValue CGPointValue];
#endif
        
        if ( [self.drawnIsoCurvesLabelsPositions containsObject:positionValue] ) {
            label.contentLayer.hidden = YES;
        }
        else {
            [self.drawnIsoCurvesLabelsPositions addObject:positionValue];
            
            label.contentLayer.hidden = self.hidden || isnan(position.x) || isnan( position.y);
            
            label.anchorPlotPoint     = @[[NSNumber numberWithDouble: position.x], [NSNumber numberWithDouble: position.y]];
            
            label.displacement = CGPointZero;
            label.contentAnchorPoint = self.isoCurvesLabelContentAnchorPoint;
            
    //        CATransform3D transform = CATransform3DMakeTranslation(label.contentLayer.bounds.size.width, label.contentLayer.bounds.size.height, 0);
    ////        CATransform3D transform = CATransform3DMakeRotation(label.rotation, 0.0, 0.0, 1.0);
    //        transform = CATransform3DRotate(transform, label.rotation, 0.0, 0.0, 1.0);
    ////        transform = CATransform3DScale(transform, 1.0, 1.0, 1.0);
    //        label.contentLayer.transform = transform;
        }
    }
}


/// @endcond

#pragma mark -
#pragma mark Responder Chain and User Interaction

/// @name User Interaction
/// @{

/**
 *  @brief Informs the receiver that the user has
 *  @if MacOnly pressed the mouse button. @endif
 *  @if iOSOnly started touching the screen. @endif
 *
 *
 *  If this plot has a delegate that responds to the
 *  @link CPTContourPlotDelegate:: contourPlot:contourTouchDownAtRecordIndex: - contourPlot:contourTouchDownAtRecordIndex: @endlink or
 *  @link CPTContourPlotDelegate:: contourPlot:contourTouchDownAtRecordIndex:withEvent: - contourPlot:contourTouchDownAtRecordIndex:withEvent: @endlink
 *  methods, the @par{interactionPoint} is compared with each bar in index order.
 *  The delegate method will be called and this method returns @YES for the first
 *  index where the @par{interactionPoint} is inside a bar.
 *  This method returns @NO if the @par{interactionPoint} is outside all of the bars.
 *
 *  @param event The OS event.
 *  @param interactionPoint The coordinates of the interaction.
 *  @return Whether the event was handled or not.
 **/
-(BOOL)pointingDeviceDownEvent:(nonnull CPTNativeEvent *)event atPoint:(CGPoint)interactionPoint {
    CPTGraph *theGraph       = self.graph;
    CPTPlotArea *thePlotArea = self.plotArea;

    if ( !theGraph || !thePlotArea || self.hidden ) {
        return NO;
    }

    id<CPTContourPlotDelegate> theDelegate = (id<CPTContourPlotDelegate>)self.delegate;
    
    BOOL symbolTouchUpHandled              = NO;

    if ( [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolTouchDownAtRecordIndex:)] ||
         [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolTouchDownAtRecordIndex:withEvent:)] ||
         [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolWasSelectedAtRecordIndex:)] ||
         [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolWasSelectedAtRecordIndex:withEvent:)] ) {
        // Inform delegate if a point was hit
        CGPoint plotAreaPoint = [theGraph convertPoint:interactionPoint toLayer:thePlotArea];
        NSUInteger idx        = [self indexOfVisiblePointClosestToPlotAreaPoint:plotAreaPoint];

        if ( idx != NSNotFound ) {
            CGPoint center        = [self plotAreaPointOfVisiblePointAtIndex:idx];
            CPTPlotSymbol *symbol = [self plotSymbolForRecordIndex:idx];

            CGRect symbolRect = CGRectZero;
            if ( [symbol isKindOfClass:[CPTPlotSymbol class]] ) {
                symbolRect.size = symbol.size;
            }
            else {
                symbolRect.size = CGSizeZero;
            }
            CGFloat margin = self.plotSymbolMarginForHitDetection * (CGFloat)2.0;
            symbolRect.size.width  += margin;
            symbolRect.size.height += margin;
            symbolRect.origin       = CGPointMake((CGFloat)(center.x - (CGFloat)0.5 * CGRectGetWidth(symbolRect)), (CGFloat)(center.y - (CGFloat)0.5 * CGRectGetHeight(symbolRect)));

            if ( CGRectContainsPoint(symbolRect, plotAreaPoint)) {
                self.pointingDeviceDownIndex = idx;

                if ( [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolTouchDownAtRecordIndex:)] ) {
                    symbolTouchUpHandled = YES;
                    [theDelegate contourPlot:self plotSymbolTouchDownAtRecordIndex:idx];
                }
                if ( [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolTouchDownAtRecordIndex:withEvent:)] ) {
                    symbolTouchUpHandled = YES;
                    [theDelegate contourPlot:self plotSymbolTouchDownAtRecordIndex:idx withEvent:event];
                }
            }
        }
    }
    
    if ( [theDelegate respondsToSelector:@selector( contourPlot:contourTouchDownAtRecordIndex:)] ||
         [theDelegate respondsToSelector:@selector( contourPlot:contourTouchDownAtRecordIndex:withEvent:)] ||
         [theDelegate respondsToSelector:@selector( contourPlot:contourWasSelectedAtRecordIndex:)] ||
         [theDelegate respondsToSelector:@selector( contourPlot:contourWasSelectedAtRecordIndex:withEvent:)] ) {
        // Inform delegate if a point was hit
        CGPoint plotAreaPoint = [theGraph convertPoint:interactionPoint toLayer:thePlotArea];
        NSUInteger idx        = [self dataIndexFromInteractionPoint:plotAreaPoint];
        self.pointingDeviceDownIndex = idx;

        if ( idx != NSNotFound ) {
            BOOL handled = NO;

            if ( [theDelegate respondsToSelector:@selector( contourPlot:contourTouchDownAtRecordIndex:)] ) {
                handled = YES;
                [theDelegate  contourPlot:self contourTouchDownAtRecordIndex:idx];
            }

            if ( [theDelegate respondsToSelector:@selector( contourPlot:contourTouchDownAtRecordIndex:withEvent:)] ) {
                handled = YES;
                [theDelegate  contourPlot:self contourTouchDownAtRecordIndex:idx withEvent:event];
            }

            if ( handled ) {
                return YES;
            }
        }
    }
    
    if ( symbolTouchUpHandled ) {
        return YES;
    }

    return [super pointingDeviceDownEvent:event atPoint:interactionPoint];
}

/**
 *  @brief Informs the receiver that the user has
 *  @if MacOnly released the mouse button. @endif
 *  @if iOSOnly ended touching the screen. @endif
 *
 *
 *  If this plot has a delegate that responds to the
 *  @link CPTContourPlotDelegate::contourPlot: contourTouchUpAtRecordIndex: -contourPlot:contourTouchUpAtRecordIndex: @endlink and/or
 *  @link CPTContourPlotDelegate::contourPlot: contourTouchUpAtRecordIndex:withEvent: -contourPlot:contourTouchUpAtRecordIndex:withEvent: @endlink
 *  methods, the @par{interactionPoint} is compared with each contour base point in index order.
 *  The delegate method will be called and this method returns @YES for the first
 *  index where the @par{interactionPoint} is inside a bar.
 *  This method returns @NO if the @par{interactionPoint} is outside all of the bars.
 *
 *  If the bar being released is the same as the one that was pressed (see
 *  @link CPTContourPlot::pointingDeviceDownEvent:atPoint: -pointingDeviceDownEvent:atPoint: @endlink), if the delegate responds to the
 *  @link CPTContourPlotDelegate:: contourPlot:contourWasSelectedAtRecordIndex: -contourPlot:contourWasSelectedAtRecordIndex: @endlink and/or
 *  @link CPTContourPlotDelegate:: contourPlot:contourWasSelectedAtRecordIndex:withEvent: -contourPlot:contourWasSelectedAtRecordIndex:withEvent: @endlink
 *  methods, these will be called.
 *
 *  @param event The OS event.
 *  @param interactionPoint The coordinates of the interaction.
 *  @return Whether the event was handled or not.
 **/
-(BOOL)pointingDeviceUpEvent:(nonnull CPTNativeEvent *)event atPoint:(CGPoint)interactionPoint {
    NSUInteger selectedDownIndex = self.pointingDeviceDownIndex;

    self.pointingDeviceDownIndex = NSNotFound;

    CPTGraph *theGraph       = self.graph;
    CPTPlotArea *thePlotArea = self.plotArea;

    if ( !theGraph || !thePlotArea || self.hidden ) {
        return NO;
    }
    

    id<CPTContourPlotDelegate> theDelegate = (id<CPTContourPlotDelegate>)self.delegate;
    
    BOOL symbolSelectHandled               = NO;

    if ( [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolTouchUpAtRecordIndex:)] ||
         [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolTouchUpAtRecordIndex:withEvent:)] ||
         [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolWasSelectedAtRecordIndex:)] ||
         [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolWasSelectedAtRecordIndex:withEvent:)] ) {
        // Inform delegate if a point was hit
        CGPoint plotAreaPoint = [theGraph convertPoint:interactionPoint toLayer:thePlotArea];
        NSUInteger idx        = [self indexOfVisiblePointClosestToPlotAreaPoint:plotAreaPoint];

        if ( idx != NSNotFound ) {
            CGPoint center        = [self plotAreaPointOfVisiblePointAtIndex:idx];
            CPTPlotSymbol *symbol = [self plotSymbolForRecordIndex:idx];

            CGRect symbolRect = CGRectZero;
            if ( [symbol isKindOfClass:[CPTPlotSymbol class]] ) {
                symbolRect.size = symbol.size;
            }
            else {
                symbolRect.size = CGSizeZero;
            }
            CGFloat margin = self.plotSymbolMarginForHitDetection * (CGFloat)2.0;
            symbolRect.size.width  += margin;
            symbolRect.size.height += margin;
            symbolRect.origin       = CGPointMake((CGFloat)(center.x - (CGFloat)0.5 * CGRectGetWidth(symbolRect)), (CGFloat)(center.y - (CGFloat)0.5 * CGRectGetHeight(symbolRect)));

            if ( CGRectContainsPoint(symbolRect, plotAreaPoint)) {
                self.pointingDeviceDownIndex = idx;

                if ( [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolTouchUpAtRecordIndex:)] ) {
                    symbolSelectHandled = YES;
                    [theDelegate contourPlot:self plotSymbolTouchUpAtRecordIndex:idx];
                }
                if ( [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolTouchUpAtRecordIndex:withEvent:)] ) {
                    symbolSelectHandled = YES;
                    [theDelegate contourPlot:self plotSymbolTouchUpAtRecordIndex:idx withEvent:event];
                }

                if ( idx == selectedDownIndex ) {
                    if ( [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolWasSelectedAtRecordIndex:)] ) {
                        symbolSelectHandled = YES;
                        [theDelegate contourPlot:self plotSymbolWasSelectedAtRecordIndex:idx];
                    }

                    if ( [theDelegate respondsToSelector:@selector(contourPlot:plotSymbolWasSelectedAtRecordIndex:withEvent:)] ) {
                        symbolSelectHandled = YES;
                        [theDelegate contourPlot:self plotSymbolWasSelectedAtRecordIndex:idx withEvent:event];
                    }
                }
            }
        }
    }

    if ( [theDelegate respondsToSelector:@selector(contourPlot:contourTouchUpAtRecordIndex:)] ||
         [theDelegate respondsToSelector:@selector(contourPlot:contourTouchUpAtRecordIndex:withEvent:)] ||
         [theDelegate respondsToSelector:@selector(contourPlot:contourWasSelectedAtRecordIndex:)] ||
         [theDelegate respondsToSelector:@selector(contourPlot:contourWasSelectedAtRecordIndex:withEvent:)] ) {
        // Inform delegate if a point was hit
        CGPoint plotAreaPoint = [theGraph convertPoint:interactionPoint toLayer:thePlotArea];
        NSUInteger idx        = [self dataIndexFromInteractionPoint:plotAreaPoint];

        if ( idx != NSNotFound ) {
            BOOL handled = NO;

            if ( [theDelegate respondsToSelector:@selector(contourPlot: contourTouchUpAtRecordIndex:)] ) {
                handled = YES;
                [theDelegate contourPlot:self contourTouchUpAtRecordIndex:idx];
            }

            if ( [theDelegate respondsToSelector:@selector(contourPlot: contourTouchUpAtRecordIndex:withEvent:)] ) {
                handled = YES;
                [theDelegate contourPlot:self contourTouchUpAtRecordIndex:idx withEvent:event];
            }

            if ( idx == selectedDownIndex ) {
                if ( [theDelegate respondsToSelector:@selector(contourPlot:contourWasSelectedAtRecordIndex:)] ) {
                    handled = YES;
                    [theDelegate contourPlot:self contourWasSelectedAtRecordIndex:idx];
                }

                if ( [theDelegate respondsToSelector:@selector(contourPlot:contourWasSelectedAtRecordIndex:withEvent:)] ) {
                    handled = YES;
                    [theDelegate contourPlot:self contourWasSelectedAtRecordIndex:idx withEvent:event];
                }
            }

            if ( handled ) {
                return YES;
            }
        }
    }
    
    if ( symbolSelectHandled ) {
        return YES;
    }

    return [super pointingDeviceUpEvent:event atPoint:interactionPoint];
}

/// @}


#pragma mark -
#pragma mark Accessors

/// @cond

-(void)setIsoCurveLineStyle:(nullable CPTLineStyle *)newLineStyle {
    if ( isoCurveLineStyle != newLineStyle ) {
        isoCurveLineStyle = [newLineStyle copy];
        [self setNeedsDisplay];
        [[NSNotificationCenter defaultCenter] postNotificationName:CPTLegendNeedsRedrawForPlotNotification object:self];
    }
}

-(void)setXValues:(nullable CPTNumberArray *)newValues {
    [self cacheNumbers:newValues forField:CPTContourPlotFieldX];
}

-(nullable CPTNumberArray *)xValues {
    return [[self cachedNumbersForField:CPTContourPlotFieldX] sampleArray];
}

-(void)setYValues:(nullable CPTNumberArray *)newValues {
    [self cacheNumbers:newValues forField:CPTContourPlotFieldY];
}

-(nullable CPTNumberArray *)yValues {
    return [[self cachedNumbersForField:CPTContourPlotFieldY] sampleArray];
}

-(nullable CPTMutableNumericData *)functionValues {
    return [self cachedNumbersForField:CPTContourPlotFieldFunctionValue];
}

-(void)setFunctionValues:(nullable CPTMutableNumericData *)newValues {
    [self cacheNumbers:newValues forField:CPTContourPlotFieldFunctionValue];
}

-(void)setPlotSymbol:(nullable CPTPlotSymbol *)aSymbol
{
    if ( aSymbol != plotSymbol ) {
        plotSymbol = [aSymbol copy];
        [self setNeedsDisplay];
        [[NSNotificationCenter defaultCenter] postNotificationName:CPTLegendNeedsRedrawForPlotNotification object:self];
    }
}

-(nullable CPTLineStyleArray *)getIsoCurveLineStyles {
    return self.isoCurvesLineStyles;
}

-(nullable CPTLineStyleArray *)isoCurveLineStyles {
    return self.isoCurvesLineStyles;
}

-(nonnull CPTLineStyle *)isoCurveLineStyleForIndex:(NSUInteger)idx {
    CPTLineStyle *theLineStyle = [self.isoCurvesLineStyles objectAtIndex:idx];
    if ( (theLineStyle == nil) || (theLineStyle == [CPTPlot nilData]) ) {
        theLineStyle = self.isoCurveLineStyle;
    }
    return theLineStyle;
}

-(void)setLineStyles:(nullable CPTLineStyleArray *)newLineStyles {
    id nilObject                    = [CPTPlot nilData];
    for(NSUInteger i = 0; i < /*self.isoCurvesValues*/self.isoCurvesIndices.count; i++) {
        if( i >= newLineStyles.count ) {
            [self.isoCurvesLineStyles replaceObjectAtIndex:i withObject:nilObject];
        }
        else {
            [self.isoCurvesLineStyles replaceObjectAtIndex:i withObject:[CPTMutableLineStyle lineStyleWithStyle: newLineStyles[i]]];
        }
    }
    [self setNeedsDisplay];
}

-(nullable CPTNumberArray *)getIsoCurveValues {
    return self.isoCurvesValues;
}

-(nullable CPTNumberArray *)getIsoCurveIndices {
    return self.isoCurvesIndices;
}

-(nullable CPTMutableFillArray *)getIsoCurveFills {
    return self.isoCurvesFills;
}

-(nullable NSMutableArray<CPTContourFill*> *)getIsoCurveFillings {
    return self.isoCurvesFillings;
}

-(NSUInteger)getNoDataPointsUsedForIsoCurves {
    return 0;
}

-(void)setNeedsIsoCurvesUpdate:(BOOL)newNeedsIsoCurvesUpdate {
    if ( newNeedsIsoCurvesUpdate != needsIsoCurvesUpdate ) {
        needsIsoCurvesUpdate = newNeedsIsoCurvesUpdate;
        if ( needsIsoCurvesUpdate ) {
            [self reloadData];
            [self setNeedsLayout];
        }
    }
}

-(void)setNoIsoCurves:(NSUInteger)newNoIsoCurves {
    if ( newNoIsoCurves != noIsoCurves ) {
        noIsoCurves = newNoIsoCurves;
        [self setNeedsIsoCurvesUpdate: YES];
    }
}

-(void)setNeedsIsoCurvesRelabel:(BOOL)newNeedsRelabel {
    if ( newNeedsRelabel != needsIsoCurvesRelabel ) {
        needsIsoCurvesRelabel = newNeedsRelabel;
        if ( needsIsoCurvesRelabel ) {
            self.isoCurvesLabelIndexRange = NSMakeRange(0, self.isoCurvesValues.count);
            [self reLabelIsoCurves];
            [self setNeedsLayout];
        }
    }
}

-(void)setShowIsoCurvesLabels:(BOOL)newShowLabels {
    if ( newShowLabels != showIsoCurvesLabels ) {
        showIsoCurvesLabels = newShowLabels;
        [self setNeedsIsoCurvesRelabel:newShowLabels];
    }
}

// Set the dimension of the primary grid
-(void) setFirstGridColumns:(NSUInteger)cols Rows:(NSUInteger)rows {
    self.noColumnsFirst = cols;
    self.noRowsFirst = rows;
    self.needsIsoCurvesUpdate = YES;
}

// Set the dimension of the base grid
-(void) setSecondaryGridColumns:(NSUInteger)cols Rows:(NSUInteger)rows {
    self.noColumnsSecondary = cols;
    self.noRowsSecondary = rows;
    self.needsIsoCurvesUpdate = YES;
}

// let the Renderer know state of play
-(void)setInitialRendition:(BOOL)initialRendition {
    self.firstRendition = initialRendition;
}

// Set dataBlockSource
-(void) updateDataSourceBlock:(CPTContourDataSourceBlock)newDataSourceBlock {
    self.dataSourceBlock = newDataSourceBlock;
    self.needsIsoCurvesUpdate = YES;
}

/// @endcond

- (void) trimDownArray:(NSMutableArray*)items {
    NSMutableIndexSet *indexes = (NSMutableIndexSet*)[items indexesOfObjectsWithOptions:NSEnumerationConcurrent passingTest:^(id obj, NSUInteger __unused idx, BOOL __unused *stop) {
           NSString *item = (NSString *)obj;
           if([item isEqualToString:@""])
               return NO;
           else
               return YES;
       }];
    if([indexes count] > 0 && [indexes count] != [items count]) {
        NSMutableArray *itemsCopy = [[NSMutableArray alloc] initWithCapacity:[indexes count]];
        NSUInteger idx = [indexes firstIndex];
        while(idx != NSNotFound) {
            [itemsCopy addObject: items[idx]];
            idx = [indexes indexGreaterThanIndex:idx];
        }
        [items removeAllObjects];
        [items addObjectsFromArray:itemsCopy];
    }
}


@end

//                    CGPoint midPoint = CGPointMake(-0.0, -0.0);
//                    double plotPlot[2];
//                    double functionValue = -0.0;
//                    double incrX, incrY;
//                    while( i < drawnViewPointsCount - 1 ) {
//                        if( !(drawnViewPoints[i].x - drawnViewPoints[i + 1].x == 0.0 || drawnViewPoints[i].y - drawnViewPoints[i + 1].y == 0.0) ) {
//                            double xEnd, yEnd;
//                            incrX = (double)(drawnViewPoints[i].x - drawnViewPoints[i + 1].x) / 10.0 ;
//                            incrY = (double)(drawnViewPoints[i].y - drawnViewPoints[i + 1].y) / 10.0 ;
//                            if( drawnViewPoints[i].x > drawnViewPoints[i + 1].x ) {
//                                x = drawnViewPoints[i + 1].x + incrX;
//                                xEnd = drawnViewPoints[i].x;
//                            }
//                            else {
//                                x = drawnViewPoints[i].x + incrX;
//                                xEnd = drawnViewPoints[i + 1].x;
//                            }
//                            if( drawnViewPoints[i].y > drawnViewPoints[i + 1].y ) {
//                                y = drawnViewPoints[i + 1].y + incrY;
//                                yEnd = drawnViewPoints[i].y;
//                            }
//                            else {
//                                y = drawnViewPoints[i].y + incrY;
//                                yEnd = drawnViewPoints[i + 1].y;
//                            }
//                            j = 0;
//                            while ( incrX > 0 ? x < xEnd : x > xEnd ) {
//                                while ( incrY > 0 ? y < yEnd : y > yEnd ) {
//                                    midPoint = CGPointMake(x, y);
//                                    [(CPTXYPlotSpace*)self.plotSpace doublePrecisionPlotPoint:plotPlot numberOfCoordinates:2 forPlotAreaViewPoint:midPoint];
//                                    functionValue = self.dataSourceBlock(plotPlot[0], plotPlot[1]);
//                                    if ( isnan(functionValue) ) {
//                                        break;
//                                    }
//                                    y += incrY;
//                                }
//                                if ( isnan(functionValue) ) {
//                                    insertCGPointsAtIndex(drawnViewPoints, midPoint, i + 1, &drawnViewPointsCount, &drawnViewPointsSize);
//                                    j++;
//                                }
//                                if ( j == 10 ) {
//                                    break;
//                                }
//                                x += incrX;
//                            }
//                            i+= j;
//                        }
//                        i++;
//                    }
