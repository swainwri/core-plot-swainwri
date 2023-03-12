//
//  NSBezierPath+CGPath.h
//  CorePlot
//
//  Created by Steve Wainwright on 16/02/2023.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/** @category NSBezierPath(CGPath)
 *  @brief CoreGraphics extensions to NSBezierPath.
 **/
@interface NSBezierPath(CGPath)

- (nullable CGPathRef)CGPath;

@end

NS_ASSUME_NONNULL_END
