//
//  CPTContour.m
//  CorePlot
//
//  Created by Steve Wainwright on 22/11/2021.
//

#import "_CPTContour.h"

#define NEGINF ((-1.0) / 0.0)
#define POSINF ((1.0) / 0.0)

double TestFunction(double x, double y);


double TestFunction(double x, double y) {
//    return 0.5*(cos(x+3.14/4)+sin(y+3.14/4));
    return sin(x) * sin(y);
};

int compareNSUInteger(const void * a, const void * b) {
    const NSUInteger *aO = (const NSUInteger*)a;
    const NSUInteger *bO = (const NSUInteger*)b;
    
    if ( *aO < *bO )
        return -1;
    else if ( *aO > *bO )
        return 1;
    else
        return 0;
}


void initContourPlanes(ContourPlanes *a, size_t initialSize) {
    a->array = (double*)calloc(initialSize, sizeof(double));
    a->used = 0;
    a->size = initialSize;
}

void appendContourPlanes(ContourPlanes *a, double element) {
    // a->used is the number of used entries, because a->array[a->used++] updates a->used only *after* the array has been accessed.
    // Therefore a->used can go up to a->size
    if (a->used == a->size) {
        a->size *= 2;
        a->array = (double*)realloc(a->array, a->size * sizeof(double));
    }
    a->array[a->used++] = element;
}

void insertContourPlanesAtIndex(ContourPlanes *a, double element, size_t index) {
    if (a->used == a->size) {
        a->size *= 2;
        a->array = (double*)realloc(a->array, a->size * sizeof(double));
    }
    
    if ( index < a->used ) {
        for( NSInteger i = (NSInteger)a->used - 1; i >= (NSInteger)index; i-- ) {
            a->array[i + 1] =  a->array[i];
        }
        a->array[index] = element;
        a->used++;
    }
    else {
        appendContourPlanes(a, element);
    }
}

void clearContourPlanes(ContourPlanes *a) {
    a->used = 0;
}

void freeContourPlanes(ContourPlanes *a) {
    free(a->array);
    a->array = NULL;
    a->used = a->size = 0;
}

void initDiscontinuities(Discontinuities *a, size_t initialSize) {
    a->array = (NSUInteger*)calloc(initialSize, sizeof(NSUInteger));
    a->used = 0;
    a->size = initialSize;
}

void appendDiscontinuities(Discontinuities *a, NSUInteger element) {
    // a->used is the number of used entries, because a->array[a->used++] updates a->used only *after* the array has been accessed.
    // Therefore a->used can go up to a->size
    if (a->used == a->size) {
        a->size *= 2;
        a->array = (NSUInteger*)realloc(a->array, a->size * sizeof(NSUInteger));
    }
    a->array[a->used++] = element;
}

BOOL containsDiscontinuities(Discontinuities *a,  NSUInteger element) {
    qsort(a->array, a->used, sizeof(NSUInteger), compareNSUInteger);
    NSUInteger *item = (NSUInteger*)bsearch(&element, a->array, a->used, sizeof(NSUInteger), compareNSUInteger);
    if( item != NULL ) {
        return YES;
    }
    else {
        return NO;
    }
}

void clearDiscontinuities(Discontinuities *a) {
    a->used = 0;
}

void freeDiscontinuities(Discontinuities *a) {
    free(a->array);
    a->array = NULL;
    a->used = a->size = 0;
}


// A structure used internally by CPTContour
typedef struct  {
    double value;
    short leftLength;
    short rightLength;
    short topLength;
    short bottomLength;
} FunctionDatum;


@interface CPTContour() 
    
    
// Inaccessibles variables
@property (nonatomic, readwrite) NSUInteger noColumnsFirst;             // primary    grid, number of columns
@property (nonatomic, readwrite) NSUInteger noRowsFirst;                // primary    grid, number of rows
@property (nonatomic, readwrite) NSUInteger noColumnsSecondary;         // secondary grid, number of columns
@property (nonatomic, readwrite) NSUInteger noRowsSecondary;            // secondary grid, number of rows
@property (nonatomic, readwrite) double* limits;                        // left, right, bottom, top
    
//    double (*fieldFunction)(double x, double y); // pointer to F(x,y) function
    
//@property (nonatomic, readonly, nullable) CPTDataSourceFunction dataSourceFunction;
@property (nonatomic, readwrite) CPTContourDataSourceBlock fieldBlock; // block to F(x,y) function
@property (nonatomic, readwrite) NSUInteger noPlanes;     // no of isocurves to breakdown

    // Work functions and variables
@property (nonatomic, readwrite) double deltaX;
@property (nonatomic, readwrite) double deltaY;

    
@property (nonatomic, readwrite) FunctionDatum **functionData; // pointer to mesh parts

-(FunctionDatum)functionDataForColumn:(NSUInteger)i Row:(NSUInteger)j;
-(double) fieldForX:(NSUInteger)x Y:(NSUInteger) y;     /* evaluate funct if we must,    */
-(void) contour1ForX1:(NSUInteger)x1 X2:(NSUInteger)x2 Y1:(NSUInteger)y1 Y2:(NSUInteger)y2;
-(void) pass2ForX1:(NSUInteger)x1 X2:(NSUInteger)x2 Y1:(NSUInteger)y1 Y2:(NSUInteger)y2; /* draws the contour lines */

@end
                                    
                                    
@implementation CPTContour

static ContourPlanes contourPlanes;
static Discontinuities discontinuities;
static NSUInteger maxColumnsByRows;

@synthesize noColumnsFirst, noRowsFirst, noColumnsSecondary, noRowsSecondary, noPlanes;
@synthesize limits;
@synthesize fieldBlock;
@synthesize deltaX, deltaY;
@synthesize functionData;
@synthesize containsFunctionNans, containsFunctionInfinities, containsFunctionNegativeInfinities;

//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////


-(nonnull instancetype)init {
    if ( (self = [super init]) ) {
        
        noColumnsFirst = noRowsFirst = 64;
        noColumnsSecondary = noRowsSecondary = 1024;

        deltaX = deltaY = 0;
//        fieldFunction = NULL;
        fieldBlock = NULL;
        limits[0] = -1.0;
        limits[1] = 1.0;
        limits[2] = -1.0;
        limits[3] = 1.0;
        functionData = NULL;
        noPlanes = 11;

        // temporary stuff
//        fieldFunction = TestFunction;
        initContourPlanes(&contourPlanes, (size_t)self.noPlanes+2);
        initDiscontinuities(&discontinuities, 8);
        
        for (NSUInteger i = 0; i < self.noPlanes; i++) {
            appendContourPlanes(&contourPlanes, ((double)i - self.noPlanes / 2.0) * 0.1);
        }
        maxColumnsByRows = (noColumnsSecondary + 1) * (noRowsSecondary + 1);
    }
    return self;
}

-(nonnull instancetype)initWithNoIsoCurve:(NSUInteger)newNoIsoCurves IsoCurveValues:(double*)newContourPlanes Limits:(double*)newLimits {
    
    NSAssert(newLimits[0] < newLimits[1], @"X: lower limit must be less than upper limit ");
    NSAssert(newLimits[2] < newLimits[3], @"Y: lower limit must be less than upper limit ");
    
    if ( (self = [super init]) ) {
        self.noColumnsFirst = self.noRowsFirst = 64;
        self.noColumnsSecondary = self.noRowsSecondary = 1024;
        self.deltaX = self.deltaY = 0;
        self.limits = (double*)calloc(4, sizeof(double));
        self.limits[0] = newLimits[0];
        self.limits[1] = newLimits[1];
        self.limits[2] = newLimits[2];
        self.limits[3] = newLimits[3];
        self.functionData = NULL;

        self.noPlanes = newNoIsoCurves;
        initContourPlanes(&contourPlanes, (size_t)self.noPlanes);
        initDiscontinuities(&discontinuities, 8);
        
        for (NSUInteger i = 0; i < self.noPlanes; i++) {
            appendContourPlanes(&contourPlanes, newContourPlanes[i]);
        }
        maxColumnsByRows = (noColumnsSecondary + 1) * (noRowsSecondary + 1);
    }
    return self;
}

-(void)dealloc {
    [self cleanMemory];
    
    free(self.limits);
    
    freeContourPlanes(&contourPlanes);
    freeDiscontinuities(&discontinuities);
}

-(void) initialiseMemory {
    if (self.functionData == NULL) {
        self.functionData = (FunctionDatum**)calloc((size_t)(self.noColumnsSecondary + 1), sizeof(FunctionDatum*));
        for(NSUInteger i = 0; i < self.noColumnsSecondary + 1; i++ ) {
            self.functionData[i] = NULL;
        }
    }
}

-(void) cleanMemory {
    if (self.functionData != NULL) {
        for(NSUInteger i = 0; i < self.noColumnsSecondary + 1; i++ ) {
            free(self.functionData[i]);
        }
        free(self.functionData);
        self.functionData = NULL;
    }
}


-(FunctionDatum)functionDataForColumn:(NSUInteger)i Row:(NSUInteger)j {
    return self.functionData[i][j];
}

#pragma mark -
#pragma mark Accessors & Setters

-(NSUInteger) getNoIsoCurves {
    return (NSUInteger)contourPlanes.used;
}

-(ContourPlanes*) getContourPlanes {
    return &contourPlanes;
}

-(Discontinuities*) getDiscontinuities {
    return &discontinuities;
}

-(double*)getIsoCurves {
    return contourPlanes.array;
}

-(double)getIsoCurveAt:(NSUInteger)i {
    NSAssert(i != NSNotFound && i < (NSUInteger)contourPlanes.used, @"Plane asked for is not between assigned");
    return contourPlanes.array[i];
}

// For an indexed point i on the sec. grid, returns x(i)
-(double) getXAt:(NSUInteger)i {
    return self.limits[0] + i % (self.noColumnsSecondary + 1) * (self.limits[1] - self.limits[0]) / (double)self.noColumnsSecondary;
}
                                    
// For an indexed point i on the fir. grid, returns y(i)
-(double) getYAt:(NSUInteger)i {
    NSAssert(i >= 0, @"Index must be >= 0");
    return self.limits[2] + i / (self.noColumnsSecondary + 1) * (self.limits[3] - self.limits[2]) / (double)self.noRowsSecondary;
}

-(NSUInteger) getIndexAtX:(double)x Y:(double)y {
    NSUInteger index = NSNotFound;
    if ( x >= self.limits[0] && x <= self.limits[1] && y >= self.limits[2] && y <= self.limits[3] ) {
        NSUInteger row = (NSUInteger)((y - self.limits[2]) / (self.limits[3] - self.limits[2]) * (double)(self.noRowsSecondary * (self.noColumnsSecondary + 1)));
        NSUInteger col = (NSUInteger)((x - self.limits[0]) / (self.limits[1] - self.limits[0]) * (double)self.noColumnsSecondary);
        index = row + col;
    }
    return index;
}

-(double) getFieldValueForX:(double)x Y:(double)y {
    if ( self.fieldBlock != NULL ) {
        return self.fieldBlock(x, y);
    }
    else {
        return -0.0;
    }
}

-(NSUInteger) getNoColumnsFirstGrid {
    return self.noColumnsFirst;
}

-(NSUInteger) getNoRowsFirstGrid {
    return self.noRowsFirst;
}

-(NSUInteger) getNoColumnsSecondaryGrid {
    return self.noColumnsSecondary;
}

-(NSUInteger) getNoRowsSecondaryGrid {
    return self.noRowsSecondary;
}

-(double*) getLimits {
    return self.limits;
}

-(double) getDX {
    return self.deltaX;
}

-(double) getDY {
    return self.deltaY;
}

// sets the number of isocurves to look at
-(void) setNoIsoCurves:(NSUInteger)newNoPlanes {
    [self cleanMemory];
    
    self.noPlanes = newNoPlanes;
    freeContourPlanes(&contourPlanes);
    initContourPlanes(&contourPlanes, (size_t)newNoPlanes);
}

// Set the dimension of the primary grid
-(void) setFirstGridDimensionColumns:(NSUInteger)iCol Rows:(NSUInteger)iRow {
    self.noColumnsFirst = MAX(iCol,2);
    self.noRowsFirst = MAX(iRow,2);
}

// Set the dimension of the base grid
-(void) setSecondaryGridDimensionColumns:(NSUInteger)iCol Rows:(NSUInteger)iRow {
    [self cleanMemory];
    
    self.noColumnsSecondary = MAX(iCol, 2);
    self.noRowsSecondary = MAX(iRow, 2);
}


-(void) setDX:(double)newDeltaX {
    self.deltaX = newDeltaX;
}

-(void) setDY:(double)newDeltaY {
    self.deltaY = newDeltaY;
}

//// Sets the region [left, right, bottom,top] to generate contour
//-(void) setLimits:(double*)newLimits {
//    NSAssert(newLimits[0] < newLimits[1], @"X: lower limit must be less than upper limit ");
//    NSAssert(newLimits[2] < newLimits[3], @"Y: lower limit must be less than upper limit ");
//    
//    for (int i = 0; i < 4; i++) {
//        self.limits[i] = newLimits[i];
//    }
//}

// Sets the isocurve values
-(void)setIsoCurves:(ContourPlanes*)newContourPlanes {
    
    // cleaning memory
    [self cleanMemory];
    
    clearContourPlanes(&contourPlanes);
    for(NSUInteger i = 0; i < newContourPlanes->used; i++) {
        appendContourPlanes(&contourPlanes, newContourPlanes->array[i]);
    }
}

-(void) setIsoCurveValues:(double*)newContourPlanes noIsoCurves:(size_t)newNoIsoCurves {
    // cleaning memory
    [self cleanMemory];
    
    clearContourPlanes(&contourPlanes);
    self.noPlanes = newNoIsoCurves;
    
    for (NSUInteger i = 0; i < self.noPlanes; i++) {
        appendContourPlanes(&contourPlanes, newContourPlanes[i]);
    }
}

-(void) setXYLimits:(double*)newLimits {
    NSAssert(newLimits[0] < newLimits[1], @"X: lower limit must be less than upper limit ");
    NSAssert(newLimits[2] < newLimits[3], @"Y: lower limit must be less than upper limit ");
    
    self.limits[0] = newLimits[0];
    self.limits[1] = newLimits[1];
    self.limits[2] = newLimits[2];
    self.limits[3] = newLimits[3];
}
//// Sets the pointer to the F(x,y) function
//-(void) setFieldFunction:(double (*fieldFunction))function {
//    self.fieldFunction = function
//}

//// Sets the block to the F(x,y) function
//-(void) setFieldBlock:(CPTContourDataSourceBlock)block {
//    self.fieldBlock = block;
//}

#pragma mark -
#pragma mark GENERATE CONTOURS

static BOOL once = NO;

-(BOOL) generate {
    NSUInteger i, j;
    NSUInteger x3, x4, y3, y4, x, y, oldx3, xlow;
    NSUInteger cols = self.noColumnsSecondary + 1;
    NSUInteger rows = self.noRowsSecondary + 1;
    
    maxColumnsByRows = cols * rows;
    
    // Initialize memroy if needed
    [self initialiseMemory];

    self.deltaX = (self.limits[1] - self.limits[0]) / (double)(self.noColumnsSecondary);
    self.deltaY = (self.limits[3] - self.limits[2]) / (double)(self.noRowsSecondary);

    xlow = 0;
    oldx3 = 0;
    x3 = (cols - 1) / self.noRowsFirst;
    x4 = (2 * (cols - 1)) / self.noRowsFirst;
    for (x = oldx3; x <= x4; x++) {      // allocate new columns needed
        if (x >= cols) {
            break;
        }
        if ( self.functionData[x] == NULL) {
            self.functionData[x] = (FunctionDatum*)calloc((size_t)rows, sizeof(FunctionDatum));
        }
        for (y = 0; y < rows; y++) {
            self.functionData[x][y].topLength = -1;
        }
    }

    y4 = 0;
    for (j = 0; j < self.noColumnsFirst; j++) {
        y3 = y4;
        y4 = ((j + 1) * (rows - 1)) / self.noColumnsFirst;
        [self contour1ForX1:oldx3 X2:x3 Y1:y3 Y2:y4];
    }

    for (i = 1; i < self.noRowsFirst; i++) {
        y4 = 0;
        for (j = 0; j < self.noColumnsFirst; j++) {
            y3 = y4;
            y4 = ((j + 1) * (rows - 1)) / self.noColumnsFirst;
            [self contour1ForX1:x3 X2:x4 Y1:y3 Y2:y4];
        }

        y4 = 0;
        for (j = 0; j < self.noColumnsFirst; j++) {
            y3 = y4;
            y4 = ((j + 1) * (rows - 1)) / self.noColumnsFirst;
            [self pass2ForX1:oldx3 X2:x3 Y1:y3 Y2:y4];
        }

        if (i < (self.noRowsFirst - 1)) {     /* re-use columns no longer needed */
            oldx3 = x3;
            x3 = x4;
            x4 = ((i + 2) * (cols - 1)) / self.noRowsFirst;
            for (x = x3 + 1; x <= x4; x++) {
                if (xlow < oldx3) {
                    if (self.functionData[x]) {
                        free(self.functionData[x]);
                    }
                    self.functionData[x] = self.functionData[xlow];
                    self.functionData[xlow++] = NULL;
                }
                else {
                    if (self.functionData[x] == NULL) {
                        self.functionData[x] = (FunctionDatum*)calloc((size_t)rows, sizeof(FunctionDatum));
                    }
                }
                for (y = 0; y < rows; y++) {
                    self.functionData[x][y].topLength = -1;
                }
            }
        }
    }

    y4 = 0;
    for (j = 0; j < self.noColumnsFirst; j++) {
        y3 = y4;
        y4 = ((j + 1) * (rows - 1)) / self.noColumnsFirst;
        [self pass2ForX1:x3 X2:x4 Y1:y3 Y2:y4];
    }
    
    if ( discontinuities.used > 0 ) {
        self.containsFunctionNans = YES;
        
        if ( !once ) {
            once = YES;
            [self cleanMemory];
            clearDiscontinuities(&discontinuities);
            appendContourPlanes(&contourPlanes, contourPlanes.array[contourPlanes.used - 1] * 10.0);
            insertContourPlanesAtIndex(&contourPlanes, contourPlanes.array[0] * (contourPlanes.array[0] < 0 ? 10.0 : -10), 0);
            self.noPlanes += 2;
            [self generate];
        }
    }
    
    return YES;
}

-(void) contour1ForX1:(NSUInteger)x1 X2:(NSUInteger)x2 Y1:(NSUInteger)y1 Y2:(NSUInteger)y2 {
    NSUInteger x3, y3, i, j, index;
    if ((x1 == x2) || (y1 == y2))    /* if not a real cell, punt */
        return;
    double f11 = [self fieldForX:x1 Y:y1];
    double f12 = [self fieldForX:x1 Y:y2];
    double f21 = [self fieldForX:x2 Y:y1];
    double f22 = [self fieldForX:x2 Y:y2];

    if ( isnan(f11) || f11 == POSINF || f11 == NEGINF ) {
        index = y1 * (self.noRowsSecondary + 1) + x1;
        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
            appendDiscontinuities(&discontinuities, index);
        }
        if ( isnan(f11) || f11 == NEGINF ) {
            f11 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
        }
        else if ( f11 == POSINF ) {
            f11 = [self getIsoCurves][self.noPlanes-1] * 10.0;
        }
    }
    if ( isnan(f12) || f12 == POSINF || f12 == NEGINF ) {
        index = y2 * (self.noRowsSecondary + 1) + x1;
        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
            appendDiscontinuities(&discontinuities, index);
        }
        if ( isnan(f12) || f12 == NEGINF ) {
            f12 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
        }
        else if ( f12 == POSINF ) {
            f12 = [self getIsoCurves][self.noPlanes-1] * 10.0;
        }
    }
    if ( isnan(f21) || f21 == POSINF || f21 == NEGINF ) {
        index = y1 * (self.noRowsSecondary + 1) + x2;
        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
            appendDiscontinuities(&discontinuities, index);
        }
        if ( isnan(f21) || isnan(f12) || f21 == NEGINF ) {
            f21 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
        }
        else if ( f21 == POSINF ) {
            f21 = [self getIsoCurves][self.noPlanes-1] * 10.0;
        }
    }
    if ( isnan(f22) || f22 == POSINF || f22 == NEGINF ) {
        index = y2 * (self.noRowsSecondary + 1) + x2;
        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
            appendDiscontinuities(&discontinuities, index);
        }
        if ( isnan(f22) || f22 == NEGINF ) {
            f22 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
        }
        else if ( f22 == POSINF ) {
            f22 = [self getIsoCurves][self.noPlanes-1] * 10.0;
        }
    }
    
    if ((x2 > x1 + 1) || (y2 > y1 + 1)) {    /* is cell divisible? */
        x3 = (x1 + x2) / 2;
        y3 = (y1 + y2) / 2;
        double f33 = [self fieldForX:x3 Y:y3];
        if( isnan(f33) || f33 == POSINF || f33 == NEGINF ) {
            index = y3 * (self.noRowsSecondary + 1) + x3;
            if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
                appendDiscontinuities(&discontinuities, index);
            }
            if ( isnan(f33) || f33 == NEGINF ) {
                f33 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
            }
            else if ( f33 == POSINF ) {
                f33 = [self getIsoCurves][self.noPlanes-1] * 10.0;
            }
        }
        i = j = 0;
        if (f33 < f11) i++; else if (f33 > f11) j++;
        if (f33 < f12) i++; else if (f33 > f12) j++;
        if (f33 < f21) i++; else if (f33 > f21) j++;
        if (f33 < f22) i++; else if (f33 > f22) j++;
        if ((i > 2) || (j > 2)) {// should we divide cell?
            /* subdivide cell */
            [self contour1ForX1:x1 X2:x3 Y1:y1 Y2:y3];
            [self contour1ForX1:x3 X2:x2 Y1:y1 Y2:y3];
            [self contour1ForX1:x1 X2:x3 Y1:y3 Y2:y2];
            [self contour1ForX1:x3 X2:x2 Y1:y3 Y2:y2];
            return;
        }
    }
    /* install cell in array */
    self.functionData[x1][y2].bottomLength = self.functionData[x1][y1].topLength = (short)(x2 - x1);
    self.functionData[x2][y1].leftLength = self.functionData[x1][y1].rightLength = (short)(y2 - y1);
}

-(void) pass2ForX1:(NSUInteger)x1 X2:(NSUInteger)x2 Y1:(NSUInteger)y1 Y2:(NSUInteger)y2 {
    
    NSUInteger left = 0, right = 0, top = 0, bot = 0, old, iNew, i, j, x3, y3;
    double yy0 = 0.0, yy1 = 0.0, xx0 = 0.0, xx1 = 0.0, xx3, yy3;
    double v, f33, fold, fnew, f;
    double xoff = self.limits[0];
    double yoff = self.limits[2];
    NSUInteger index;
    
    if ((x1 == x2) || (y1 == y2)) {    // if not a real cell, punt
        return;
    }
    double f11 = [self functionDataForColumn:x1 Row:y1].value;
    double f12 = [self functionDataForColumn:x1 Row:y2].value;
    double f21 = [self functionDataForColumn:x2 Row:y1].value;
    double f22 = [self functionDataForColumn:x2 Row:y2].value;
    
    if ( isnan(f11) || f11 == POSINF || f11 == NEGINF ) {
        index = y1 * (self.noRowsSecondary + 1) + x1;
        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
            appendDiscontinuities(&discontinuities, index);
        }
        if ( isnan(f11) || f11 == NEGINF ) {
            f11 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
        }
        else if ( f11 == POSINF ) {
            f11 = [self getIsoCurves][self.noPlanes-1] * 10.0;
        }
    }
    if ( isnan(f12) || f12 == POSINF || f12 == NEGINF ) {
        index = y2 * (self.noRowsSecondary + 1) + x1;
        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
            appendDiscontinuities(&discontinuities, index);
        }
        if ( isnan(f12) || f12 == NEGINF ) {
            f12 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
        }
        else if ( f12 == POSINF ) {
            f12 = [self getIsoCurves][self.noPlanes-1] * 10.0;
        }
    }
    if ( isnan(f21) || f21 == POSINF || f21 == NEGINF ) {
        index = y1 * (self.noRowsSecondary + 1) + x2;
        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
            appendDiscontinuities(&discontinuities, index);
        }
        if ( isnan(f21) || f21 == NEGINF ) {
            f21 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
        }
        else if ( f21 == POSINF ) {
            f21 = [self getIsoCurves][self.noPlanes-1] * 10.0;
        }
    }
    if ( isnan(f22) || f22 == POSINF || f22 == NEGINF ) {
        index = y2 * (self.noRowsSecondary + 1) + x2;
        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
            appendDiscontinuities(&discontinuities, index);
        }
        if ( isnan(f22) || f22 == NEGINF ) {
            f22 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
        }
        else if ( f22 == POSINF ) {
            f22 = [self getIsoCurves][self.noPlanes-1] * 10.0;
        }
    }
    
    if ((x2 > x1 + 1) || (y2 > y1 + 1)) {   // is cell divisible?
        x3 = (x1 + x2) / 2;
        y3 = (y1 + y2) / 2;
        f33 = [self functionDataForColumn:x3 Row:y3].value;
        if ( isnan(f33) || isinf(f33) || f33 == NEGINF ) {
            index = y3 * (self.noRowsSecondary + 1) + x3;
            if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
                appendDiscontinuities(&discontinuities, index);
            }
            if ( isnan(f33) || f33 == NEGINF ) {
                f33 = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
            }
            else if ( f33 == POSINF ) {
                f33 = [self getIsoCurves][self.noPlanes-1] * 10.0;
            }
        }
        i = j = 0;
        if (f33 < f11) i++; else if (f33 > f11) j++;
        if (f33 < f12) i++; else if (f33 > f12) j++;
        if (f33 < f21) i++; else if (f33 > f21) j++;
        if (f33 < f22) i++; else if (f33 > f22) j++;
        if ((i > 2) || (j > 2)) {   // should we divide cell?
            // subdivide cell
            [self pass2ForX1:x1 X2:x3 Y1:y1 Y2:y3];
            [self pass2ForX1:x3 X2:x2 Y1:y1 Y2:y3];
            [self pass2ForX1:x1 X2:x3 Y1:y3 Y2:y2];
            [self pass2ForX1:x3 X2:x2 Y1:y3 Y2:y2];
            return;
        }
    }

    for (i = 0; i < (NSUInteger)contourPlanes.used; i++) {
        v = contourPlanes.array[i];
        j = 0;
        if (f21 > v) j++;
        if (f11 > v) j |= 2;
        if (f22 > v) j |= 4;
        if (f12 > v) j |= 010;  // octal
        
        if ((f11 > v) ^ (f12 > v)) {
            if ( self.functionData[x1][y1].leftLength != 0 &&
                self.functionData[x1][y1].leftLength < self.functionData[x1][y1].rightLength ) {
                old = y1;
                fold = f11;
                while (1) {
                    iNew = old + (NSUInteger)self.functionData[x1][old].leftLength;
                    fnew = self.functionData[x1][iNew].value;
                    if ( isnan(fnew) || fnew == POSINF || fnew == NEGINF ) {
                        index = iNew * (self.noRowsSecondary + 1) + x1;
                        if ( index < maxColumnsByRows &&  !containsDiscontinuities(&discontinuities, index) ) {
                            appendDiscontinuities(&discontinuities, index);
                        }
                        if ( isnan(fnew) || fnew == NEGINF ) {
                            fnew = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
                        }
                        else if ( fnew == POSINF ) {
                            fnew = [self getIsoCurves][self.noPlanes-1] * 10.0;
                        }
                    }
                    if ((fnew > v) ^ (fold > v) ) {
                        break;
                    }
                    old = iNew;
                    fold = fnew;
                }
                yy0 = ((old - y1) + (iNew - old) * (v - fold) / (fnew - fold)) / (y2 - y1);
            }
            else {
                yy0 = (v - f11) / (f12 - f11);
            }
            left = (NSUInteger)(y1 + (y2 - y1) * yy0 + 0.5);
        }
        if ((f21 > v) ^ (f22 > v)) {
            if ( self.functionData[x2][y1].rightLength != 0 &&
                self.functionData[x2][y1].rightLength < self.functionData[x2][y1].leftLength ) {
                old = y1;
                fold = f21;
                while (1) {
                    iNew = old + (NSUInteger)self.functionData[x2][old].rightLength;
                    fnew = self.functionData[x2][iNew].value;
                    if ( isnan(fnew) || fnew == POSINF || fnew == NEGINF ) {
                        index = iNew * (self.noRowsSecondary + 1) + x2;
                        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
                            appendDiscontinuities(&discontinuities, index);
                        }
                        if ( isnan(fnew) || fnew == NEGINF ) {
                            fnew = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
                        }
                        else if ( fnew == POSINF ) {
                            fnew = [self getIsoCurves][self.noPlanes-1] * 10.0;
                        }
                    }
                    if ((fnew > v) ^ (fold > v) ) {
                        break;
                    }
                    old = iNew;
                    fold = fnew;
                }
                yy1 = ((old - y1) + (iNew - old) * (v - fold) / (fnew - fold)) / (y2 - y1);
            }
            else {
                yy1 = (v - f21) / (f22 - f21);
            }
            right = (NSUInteger)(y1 + (y2 - y1) * yy1 + 0.5);
        }
        if ((f21 > v) ^ (f11 > v)) {
            if ( self.functionData[x1][y1].bottomLength != 0 &&
                self.functionData[x1][y1].bottomLength < self.functionData[x1][y1].topLength ) {
                old = x1;
                fold = f11;
                while (1) {
                    iNew = old + (NSUInteger)self.functionData[old][y1].bottomLength;
                    fnew = self.functionData[iNew][y1].value;
                    if ( isnan(fnew) || fnew == POSINF || fnew == NEGINF ) {
                        index = y1 * (self.noRowsSecondary + 1) + iNew;
                        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
                            appendDiscontinuities(&discontinuities, index);
                        }
                        if ( isnan(fnew) || fnew == NEGINF ) {
                            fnew = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
                        }
                        else if ( fnew == POSINF ) {
                            fnew = [self getIsoCurves][self.noPlanes-1] * 10.0;
                        }
                    }
                    if ((fnew > v) ^ (fold > v) ) {
                        break;
                    }
                    old = iNew;
                    fold = fnew;
                }
                xx0 = ((old - x1) + (iNew - old) * (v - fold) / (fnew - fold)) / (x2 - x1);
            }
            else {
                xx0 = (v - f11) / (f21 - f11);
            }
            bot = (NSUInteger)(x1 + (x2 - x1) * xx0 + 0.5);
        }
        if ((f22 > v) ^ (f12 > v)) {
            if ( self.functionData[x1][y2].topLength != 0 &&
                self.functionData[x1][y2].topLength < self.functionData[x1][y2].bottomLength ) {
                old = x1;
                fold = f12;
                while (1) {
                    iNew = old + (NSUInteger)self.functionData[old][y2].topLength;
                    fnew = self.functionData[iNew][y2].value;
                    if ( isnan(fnew) || fnew == POSINF || fnew == NEGINF ) {
                        index = y2 * (self.noRowsSecondary + 1) + iNew;
                        if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
                            appendDiscontinuities(&discontinuities, index);
                        }
                        if ( isnan(fnew) || fnew == NEGINF ) {
                            fnew = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
                        }
                        else if ( fnew == POSINF ) {
                            fnew = [self getIsoCurves][self.noPlanes-1] * 10.0;
                        }
                    }
                    if ((fnew > v) ^ (fold > v) ) {
                        break;
                    }
                    old = iNew;
                    fold = fnew;
                }
                xx1 = ((old - x1) + (iNew - old) * (v - fold) / (fnew - fold)) / (x2 - x1);
            }
            else {
                xx1 = (v - f12) / (f22 - f12);
            }
            top = (NSUInteger)(x1 + (x2 - x1) * xx1 + 0.5);
        }

        if( !(isnan(xx0) || isnan(yy0) || isnan(xx1) || isnan(yy1)) ) {
            switch (j) {
                case 7:
                case 010:
                    [self exportLineForIsoCurve:i FromX1:x1 FromY1:left ToX2:top ToY2:y2];
                    break;
                case 5:
                case 012:
                    [self exportLineForIsoCurve:i FromX1:bot FromY1:y1 ToX2:top ToY2:y2];
                    break;
                case 2:
                case 015:
                    [self exportLineForIsoCurve:i FromX1:x1 FromY1:left ToX2:bot ToY2:y1];
                    break;
                case 4:
                case 013:
                    [self exportLineForIsoCurve:i FromX1:top FromY1:y2 ToX2:x2 ToY2:right];
                    break;
                case 3:
                case 014:
                    [self exportLineForIsoCurve:i FromX1:x1 FromY1:left ToX2:x2 ToY2:right];
                    break;
                case 1:
                case 016:
                    [self exportLineForIsoCurve:i FromX1:bot FromY1:y1 ToX2:x2 ToY2:right];
                    break;
                case 0:
                case 017:
                    break;
                case 6:
                case 011:
                    yy3 = (xx0 * (yy1 - yy0) + yy0) / (1.0 - (xx1 - xx0) * (yy1 - yy0));
                    xx3 = yy3 * (xx1 - xx0) + xx0;
                    xx3 = x1 + xx3 * (x2 - x1);
                    yy3 = y1 + yy3 * (y2 - y1);
    //                x3 = (NSUInteger)xx3;
    //                y3 = (NSUInteger)yy3;
                    xx3 = xoff + xx3 * self.deltaX;
                    yy3 = yoff + yy3 * self.deltaY;
                    /*if (fieldFunction != NULL) {
                        f = (*fieldFunction)(xx3, yy3);
                    }
                    else*/
                    if (self.fieldBlock != NULL) {
                        f = self.fieldBlock(xx3, yy3);
                        if ( isnan(f) || f == POSINF || f == NEGINF ) {
                            index = [self getIndexAtX:xx3 Y:yy3];
                            if ( index < maxColumnsByRows && !containsDiscontinuities(&discontinuities, index) ) {
                                appendDiscontinuities(&discontinuities, index);
                            }
                            if ( isnan(f) || f == NEGINF ) {
                                f = [self getIsoCurves][0] * ([self getIsoCurves][0] < 0 ? 10.0 : -10);
                            }
                            else if ( f == POSINF ) {
                                f = [self getIsoCurves][self.noPlanes - 1] * 10.0;
                            }
                        }
                    }
                    else {
                        f = 0.0;
                    }
                    if (f == v) {
                        [self exportLineForIsoCurve:i FromX1:bot FromY1:y1 ToX2:top ToY2:y2];
                        [self exportLineForIsoCurve:i FromX1:x1 FromY1:left ToX2:x2 ToY2:right];
                    }
                    else {
                        if (((f > v) && (f22 > v)) || ((f < v) && (f22 < v))) {
                            [self exportLineForIsoCurve:i FromX1:x1 FromY1:left ToX2:top ToY2:y2];
                            [self exportLineForIsoCurve:i FromX1:bot FromY1:y1 ToX2:x2 ToY2:right];
                        }
                        else {
                            [self exportLineForIsoCurve:i FromX1:x1 FromY1:left ToX2:bot ToY2:y1];
                            [self exportLineForIsoCurve:i FromX1:top FromY1:y2 ToX2:x2 ToY2:right];
                        }
                    }
            }
        }
        
        
    }
}

-(double) fieldForX:(NSUInteger)x Y:(NSUInteger)y {   /* evaluate funct if we must,    */
    double x1, y1;
    
    if (self.functionData[x][y].topLength != -1)  /* is it already in the array */
        return self.functionData[x][y].value;

    /* not in the array, create new array element */
    x1 = self.limits[0] + self.deltaX * (double)x;
    y1 = self.limits[2] + self.deltaY * (double)y;
    self.functionData[x][y].topLength = 0;
    self.functionData[x][y].bottomLength = 0;
    self.functionData[x][y].rightLength = 0;
    self.functionData[x][y].leftLength = 0;
    /*if (self.fieldFunction != NULL) {
        return (self.functionData[x][y].value = (*m_pFieldFcn)(x1, y1));
    }
    else*/ if (self.fieldBlock != NULL) {
        return (self.functionData[x][y].value = self.fieldBlock(x1, y1));
    }
    else {
        return 0.0;
    }
}

-(void) exportLineForIsoCurve:(NSUInteger)iPlane FromX1:(NSUInteger)x1 FromY1:(NSUInteger)y1 ToX2:(NSUInteger)x2 ToY2:(NSUInteger)y2 {// plots a line from (x1,y1) to (x2,y2)
}

@end
