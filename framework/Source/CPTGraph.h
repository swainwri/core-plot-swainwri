// Abstract class
#import "CPTBorderedLayer.h"
#import "CPTDefinitions.h"
#import "CPTPlot.h"
#import "CPTPlotSpace.h"

/// @file

@class CPTAxisSet;
@class CPTGraphHostingView;
@class CPTLegend;
@class CPTPlotAreaFrame;
@class CPTTheme;
@class CPTTextStyle;
@class CPTLayerAnnotation;
@class CPTAnnotation;

/**
 *  @brief Graph notification type.
 **/
typedef NSString *CPTGraphNotification cpt_swift_struct;

/**
 *  @brief The <code>userInfo</code> dictionary keys used by CPTGraph plot space notifications.
 **/
typedef NSString *CPTGraphPlotSpaceKey cpt_swift_struct;

/// @name Graph
/// @{

/** @brief Notification sent by various objects to tell the graph it should redraw itself.
 *  @ingroup notification
 **/
extern CPTGraphNotification __nonnull const CPTGraphNeedsRedrawNotification NS_SWIFT_NAME(needsRedraw);

/** @brief Notification sent by a graph after adding a new plot space.
 *  @ingroup notification
 *
 *  The notification <code>userInfo</code> dictionary will include the new plot space under the
 *  #CPTGraphPlotSpaceNotificationKey key.
 **/
extern CPTGraphNotification __nonnull const CPTGraphDidAddPlotSpaceNotification NS_SWIFT_NAME(didAddPlotSpace);

/** @brief Notification sent by a graph after removing a plot space.
 *  @ingroup notification
 *
 *  The notification <code>userInfo</code> dictionary will include the removed plot space under the
 *  #CPTGraphPlotSpaceNotificationKey key.
 **/
extern CPTGraphNotification __nonnull const CPTGraphDidRemovePlotSpaceNotification NS_SWIFT_NAME(didRemovePlotSpace);

/** @brief The <code>userInfo</code> dictionary key used by the #CPTGraphDidAddPlotSpaceNotification
 *  and #CPTGraphDidRemovePlotSpaceNotification notifications for the plot space.
 *  @ingroup notification
 **/
extern CPTGraphPlotSpaceKey __nonnull const CPTGraphPlotSpaceNotificationKey;

/// @}

/**
 *  @brief Enumeration of graph layers.
 **/
typedef NS_ENUM (NSInteger, CPTGraphLayerType) {
    CPTGraphLayerTypeMinorGridLines, ///< Minor grid lines.
    CPTGraphLayerTypeMajorGridLines, ///< Major grid lines.
    CPTGraphLayerTypeAxisLines,      ///< Axis lines.
    CPTGraphLayerTypePlots,          ///< Plots.
    CPTGraphLayerTypeAxisLabels,     ///< Axis labels.
    CPTGraphLayerTypeAxisTitles      ///< Axis titles.
};

#pragma mark -

/**
 *  @brief A graph hover source protocol .
 **/
@protocol CPTGraphHoverDelegate<CPTLayerDelegate>

@optional

#if TARGET_OS_OSX
/// @name Customised Hover Annotations
/// @{

/** @brief @optional Gets an Annotation label for a given tracking areat.
 *  This method will not be called if
 *  @link CPTGraphHoverSource::hoverLabelForGraph:trackingArera -hoverLabelForGraph:r@endlink
 *  is also implemented in the delegate.
 *  @param  graph The graph.
 *  @param  trackingArea The trackingArea.
 *  @return      The annotation label for the point with the given index.
 *  If you return @nil, the default data label will be used. If you return an instance of NSNull,
 *  no label will be shown for the index in question.
 **/
-(nullable CPTLayer *)hoverLabelForGraph:(nonnull CPTGraph *)graph trackingArea:(nonnull NSTrackingArea*)trackingArea;

/// @}

#else

/// @name Customised Hover Annotations
/// @{

/** @brief @optional Gets an Annotation label for a given tracking areat.
 *  This method will not be called if
 *  @link CPTGraphHoverSource::hoverLabelForGraph:pointerRegion -hoverLabelForGraph:r@endlink
 *  is also implemented in the delegate.
 *  @param  graph The graph.
 *  @param  pointerRegion The trackingArea.
 *  @return      The annotation label for the point with the given index.
 *  If you return @nil, the default data label will be used. If you return an instance of NSNull,
 *  no label will be shown for the index in question.
 **/
-(nullable CPTLayer *)hoverLabelForGraph:(nonnull CPTGraph *)graph pointerRegion:(nonnull UIPointerRegion*)pointerRegion;

#endif

@end

#pragma mark -

#if TARGET_OS_OSX
@interface CPTGraph : CPTBorderedLayer
#else
@interface CPTGraph : CPTBorderedLayer<UIPointerInteractionDelegate>
#endif

/// @name Graph Hover Delegate
/// @{
@property (nonatomic, readwrite, cpt_weak_property, nullable) id<CPTGraphHoverDelegate> hoverDelegate;
/// @}

/// @name Hosting View
/// @{
@property (nonatomic, readwrite, cpt_weak_property, nullable) CPTGraphHostingView *hostingView;
/// @}

/// @name Title
/// @{
@property (nonatomic, readwrite, copy, nullable) NSString *title;
@property (nonatomic, readwrite, copy, nullable) NSAttributedString *attributedTitle;
@property (nonatomic, readwrite, copy, nullable) CPTTextStyle *titleTextStyle;
@property (nonatomic, readwrite, assign) CGPoint titleDisplacement;
@property (nonatomic, readwrite, assign) CPTRectAnchor titlePlotAreaFrameAnchor;
/// @}

/// @name Layers
/// @{
@property (nonatomic, readwrite, strong, nullable) CPTAxisSet *axisSet;
@property (nonatomic, readwrite, strong, nullable) CPTPlotAreaFrame *plotAreaFrame;
@property (nonatomic, readonly, nullable) CPTPlotSpace *defaultPlotSpace;
@property (nonatomic, readwrite, strong, nullable) CPTNumberArray *topDownLayerOrder;
/// @}

/// @name Legend
/// @{
@property (nonatomic, readwrite, strong, nullable) CPTLegend *legend;
@property (nonatomic, readwrite, assign) CPTRectAnchor legendAnchor;
@property (nonatomic, readwrite, assign) CGPoint legendDisplacement;
/// @}

/// @name Tracking
/// @{
@property (nonatomic, readwrite, assign) BOOL allowTracking; // SWainwright 07/03/2023
#if TARGET_OS_IOS
@property (nonatomic, readwrite, strong, nullable) NSMutableArray<UIPointerRegion*> *pointerRegions; // SWainwright 09/03/2023
#endif
/// @}


/// @name Data Source
/// @{
-(void)reloadData;
-(void)reloadDataIfNeeded;
/// @}

/// @name Retrieving Plots
/// @{
-(nonnull CPTPlotArray *)allPlots;
-(nullable CPTPlot *)plotAtIndex:(NSUInteger)idx;
-(nullable CPTPlot *)plotWithIdentifier:(nullable id<NSCopying>)identifier;
/// @}

/// @name Adding and Removing Plots
/// @{
-(void)addPlot:(nonnull CPTPlot *)plot;
-(void)addPlot:(nonnull CPTPlot *)plot toPlotSpace:(nullable CPTPlotSpace *)space;
-(void)removePlot:(nullable CPTPlot *)plot;
-(void)removePlotWithIdentifier:(nullable id<NSCopying>)identifier;
-(void)insertPlot:(nonnull CPTPlot *)plot atIndex:(NSUInteger)idx;
-(void)insertPlot:(nonnull CPTPlot *)plot atIndex:(NSUInteger)idx intoPlotSpace:(nullable CPTPlotSpace *)space;
/// @}

/// @name Retrieving Plot Spaces
/// @{
-(nonnull CPTPlotSpaceArray *)allPlotSpaces;
-(nullable CPTPlotSpace *)plotSpaceAtIndex:(NSUInteger)idx;
-(nullable CPTPlotSpace *)plotSpaceWithIdentifier:(nullable id<NSCopying>)identifier;
/// @}

/// @name Adding and Removing Plot Spaces
/// @{
-(void)addPlotSpace:(nonnull CPTPlotSpace *)space;
-(void)removePlotSpace:(nullable CPTPlotSpace *)plotSpace;
/// @}

/// @name Themes
/// @{
-(void)applyTheme:(nullable CPTTheme *)theme;
/// @}

// added S.Wainwright
/// @name Retrieving Title Annotation
/// @{
-(nullable CPTLayerAnnotation *)getTitleLayerAnnotation;
/// @}

/// @name Retrieving Legend Annotation
/// @{
-(nullable CPTLayerAnnotation *)getLegendLayerAnnotation;
/// @}

/// @name Retrieving/Setting Hover Annotation
/// @{
-(nullable CPTAnnotation *)getHoverAnnotation;
-(void)setHoverAnnotation:(nullable CPTAnnotation *)newAnnotation;
/// @}

@end

#pragma mark -

/** @category CPTGraph(AbstractFactoryMethods)
 *  @brief CPTGraph abstract methods—must be overridden by subclasses
 **/
@interface CPTGraph(AbstractFactoryMethods)

/// @name Factory Methods
/// @{
-(nullable CPTPlotSpace *)newPlotSpace;
-(nullable CPTAxisSet *)newAxisSet;
/// @}

@end
