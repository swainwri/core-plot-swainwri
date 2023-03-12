//
// main.m
// CorePlotGallery
//

#import <Cocoa/Cocoa.h>

#import "AxisDemo.h"
#import "CandlestickPlot.h"
#import "ColoredBarChart.h"
#import "CompositePlot.h"
#import "ContourFunctionPlot.h"
#import "ContourRawDataPlot.h"
#import "ControlChart.h"
#import "CurvedInterpolationDemo.h"
#import "CurvedScatterPlot.h"
#import "DatePlot.h"
#import "DonutChart.h"
#import "FunctionPlot.h"
#import "GradientScatterPlot.h"
#import "ImageDemo.h"
#import "LabelingPolicyDemo.h"
#import "LineCapDemo.h"
#import "OHLCPlot.h"
#import "PlotSpaceDemo.h"
#import "PolarPlot.h"
#import "RangePlot.h"
#import "RealTimePlot.h"
#import "SimplePieChart.h"
#import "SteppedScatterPlot.h"
#import "VectorFieldContinuousPlot.h"
#import "VectorFieldPlot.h"
#import "VerticalBarChart.h"

#import <CorePlot/CorePlot.h>

int main(int argc, const char *argv[])
{
    (void)[AxisDemo class];
    (void)[CandlestickPlot class];
    (void)[ColoredBarChart class];
    (void)[CompositePlot class];
    (void)[ContourFunctionPlot class];
    (void)[ContourRawDataPlot class];
    (void)[ControlChart class];
    (void)[CurvedInterpolationDemo class];
    (void)[CurvedScatterPlot class];
    (void)[DatePlot class];
    (void)[DonutChart class];
    (void)[FunctionPlot class];
    (void)[GradientScatterPlot class];
    (void)[ImageDemo class];
    (void)[LabelingPolicyDemo class];
    (void)[LineCapDemo class];
    (void)[PlotSpaceDemo class];
    (void)[PolarPlot class];
    (void)[RangePlot class];
    (void)[RealTimePlot class];
    (void)[SimplePieChart class];
    (void)[SteppedScatterPlot class];
    (void)[VectorFieldContinuousPlot class];
    (void)[VectorFieldPlot class];
    (void)[VerticalBarChart class];
    
    (void)[[CPTTheme themeNamed: kCPTDarkGradientTheme_Polar] class];
    (void)[[CPTTheme themeNamed: kCPTDarkGradientTheme] class];
    
//    (void)[_CPTDarkGradientTheme_Polar class];
//    (void)[_CPTDarkGradientTheme class];
//    (void)[_CPTPlainBlackTheme_Polar class];
//    (void)[_CPTPlainBlackTheme class];
//    (void)[_CPTPlainWhiteTheme_Polar class];
//    (void)[_CPTPlainWhiteTheme class];
//    (void)[_CPTSlateTheme_Polar class];
//    (void)[_CPTSlateTheme class];
//    (void)[_CPTStocksTheme_Polar class];
//    (void)[_CPTStocksTheme class];
    
    return NSApplicationMain(argc, argv);
}
