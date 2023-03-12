#import <TargetConditionals.h>

#if TARGET_OS_SIMULATOR || TARGET_OS_IPHONE || TARGET_OS_MACCATALYST
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#import "CPTAnimation.h"
#import "CPTAnimationOperation.h"
#import "CPTAnimationPeriod.h"
#import "CPTAnnotation.h"
#import "CPTAnnotationHostLayer.h"
#import "CPTAxis.h"
#import "CPTAxisLabel.h"
#import "CPTAxisSet.h"
#import "CPTAxisTitle.h"
#import "CPTBarPlot.h"
#import "CPTBorderedLayer.h"
#import "CPTCalendarFormatter.h"
#import "CPTColor.h"
#import "CPTColorSpace.h"
#import "CPTConstraints.h"
#import "CPTDefinitions.h"
#import "CPTExceptions.h"
#import "CPTFill.h"
#import "CPTFunctionDataSource.h"
#import "CPTGradient.h"
#import "CPTGraph.h"
#import "CPTGraphHostingView.h"
#import "CPTImage.h"
#import "CPTLayer.h"
#import "CPTLayerAnnotation.h"
#import "CPTLegend.h"
#import "CPTLegendEntry.h"
#import "CPTLimitBand.h"
#import "CPTLineCap.h"
#import "CPTLineStyle.h"
#import "CPTMutableLineStyle.h"
#import "CPTMutableNumericData+TypeConversion.h"
#import "CPTMutableNumericData.h"
#import "CPTMutablePlotRange.h"
#import "CPTMutableShadow.h"
#import "CPTMutableTextStyle.h"
#import "CPTNumericData+TypeConversion.h"
#import "CPTNumericData.h"
#import "CPTNumericDataType.h"
#import "CPTPathExtensions.h"
#import "CPTPieChart.h"
#import "CPTPlatformSpecificCategories.h"
#import "CPTPlatformSpecificDefines.h"
#import "CPTPlatformSpecificFunctions.h"
#import "CPTPlot.h"
#import "CPTPlotArea.h"
#import "CPTPlotAreaFrame.h"
#import "CPTPlotRange.h"
#import "CPTPlotSpace.h"
#import "CPTPlotSpaceAnnotation.h"
#import "CPTPlotSymbol.h"
#import "CPTRangePlot.h"
#import "CPTResponder.h"
#import "CPTScatterPlot.h"
#import "CPTShadow.h"
#import "CPTTextLayer.h"
#import "CPTTextStyle.h"
#import "CPTTheme.h"
#import "CPTTimeFormatter.h"
#import "CPTTradingRangePlot.h"
#import "CPTUtilities.h"
#import "CPTXYAxis.h"
#import "CPTXYAxisSet.h"
#import "CPTXYGraph.h"
#import "CPTXYPlotSpace.h"
// added S.Wainwright
#import "CPTPolarAxis.h"
#import "CPTPolarAxisSet.h"
#import "CPTPolarGraph.h"
#import "CPTPolarPlotSpace.h"
#import "CPTPolarPlot.h"
#import "CPTPolarPlotSpaceAnnotation.h"
#import "CPTVectorFieldPlot.h"
#import "CPTContourPlot.h"
#import "CPTFieldFunctionDataSource.h"
#import "CPTHull.h"
#import "CorePlot/CGPathIntersections/CGPathPlusIntersections.h"
#import "CPTThemes.h"
