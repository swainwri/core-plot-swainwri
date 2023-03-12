#import "CPTPlatformSpecificFunctions.h"

#if TARGET_OS_OSX

#pragma mark macOS
#pragma mark -

#pragma mark Graphics Context

// linked list to store saved contexts
static NSMutableArray<NSGraphicsContext *> *pushedContexts = nil;
static dispatch_once_t contextOnceToken                    = 0;

static dispatch_queue_t contextQueue  = NULL;
static dispatch_once_t queueOnceToken = 0;

/** @brief Pushes the current AppKit graphics context onto a stack and replaces it with the given Core Graphics context.
 *  @param newContext The graphics context.
 **/
void CPTPushCGContext(__nonnull CGContextRef newContext)
{
    dispatch_once(&contextOnceToken, ^{
        pushedContexts = [[NSMutableArray alloc] init];
    });
    dispatch_once(&queueOnceToken, ^{
        contextQueue = dispatch_queue_create("CorePlot.contextQueue", NULL);
    });

    dispatch_sync(contextQueue, ^{
        NSGraphicsContext *currentContext = [NSGraphicsContext currentContext];

        if ( currentContext ) {
            [pushedContexts addObject:currentContext];
        }
        else {
            [pushedContexts addObject:(NSGraphicsContext *)[NSNull null]];
        }

        if ( newContext ) {
            [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:newContext flipped:NO]];
        }
    });
}

/**
 *  @brief Pops the top context off the stack and restores it to the AppKit graphics context.
 **/
void CPTPopCGContext(void)
{
    dispatch_once(&contextOnceToken, ^{
        pushedContexts = [[NSMutableArray alloc] init];
    });
    dispatch_once(&queueOnceToken, ^{
        contextQueue = dispatch_queue_create("CorePlot.contextQueue", NULL);
    });

    dispatch_sync(contextQueue, ^{
        if ( pushedContexts.count > 0 ) {
            NSGraphicsContext *lastContext = pushedContexts.lastObject;

            if ( [lastContext isKindOfClass:[NSGraphicsContext class]] ) {
                [NSGraphicsContext setCurrentContext:lastContext];
            }
            else {
                [NSGraphicsContext setCurrentContext:nil];
            }

            [pushedContexts removeLastObject];
        }
    });
}

#pragma mark -
#pragma mark Colors

/** @brief Creates a @ref CGColorRef from an NSColor.
 *
 *  The caller must release the returned @ref CGColorRef. Pattern colors are not supported.
 *
 *  @param nsColor The NSColor.
 *  @return The @ref CGColorRef.
 **/
__nonnull CGColorRef CPTCreateCGColorFromNSColor(NSColor *__nonnull nsColor)
{
    NSColor *rgbColor = [nsColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    CGFloat r, g, b, a;

    [rgbColor getRed:&r green:&g blue:&b alpha:&a];
    return CGColorCreateGenericRGB(r, g, b, a);
}

/** @brief Creates a CPTRGBAColor from an NSColor.
 *
 *  Pattern colors are not supported.
 *
 *  @param nsColor The NSColor.
 *  @return The CPTRGBAColor.
 **/
CPTRGBAColor CPTRGBAColorFromNSColor(NSColor *__nonnull nsColor)
{
    CGFloat red, green, blue, alpha;

    //[[nsColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&red green:&green blue:&blue alpha:&alpha];
    [[nsColor colorUsingType:NSColorTypeComponentBased] getRed:&red green:&green blue:&blue alpha:&alpha];
//    [[NSColor colorUsingColorSpace:]]

    CPTRGBAColor rgbColor;

    rgbColor.red   = red;
    rgbColor.green = green;
    rgbColor.blue  = blue;
    rgbColor.alpha = alpha;

    return rgbColor;
}

#pragma mark -
#pragma mark Debugging

CPTNativeImage *__nonnull CPTQuickLookImage(CGRect rect, __nonnull CPTQuickLookImageBlock renderBlock)
{
    NSBitmapImageRep *layerImage = [[NSBitmapImageRep alloc]
                                    initWithBitmapDataPlanes:NULL
                                                  pixelsWide:(NSInteger)rect.size.width
                                                  pixelsHigh:(NSInteger)rect.size.height
                                               bitsPerSample:8
                                             samplesPerPixel:4
                                                    hasAlpha:YES
                                                    isPlanar:NO
                                              colorSpaceName:NSCalibratedRGBColorSpace
                                                 bytesPerRow:(NSInteger)rect.size.width * 4
                                                bitsPerPixel:32];

    NSGraphicsContext *bitmapContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:layerImage];

    CGContextRef context = (CGContextRef)bitmapContext.CGContext;

    CGContextClearRect(context, rect);

    renderBlock(context, 1.0, rect);

    CGContextFlush(context);

    NSImage *image = [[NSImage alloc] initWithSize:NSSizeFromCGSize(rect.size)];

    [image addRepresentation:layerImage];

    return image;
}

#else

#pragma mark - iOS, tvOS, Mac Catalyst

#import "CPTExceptions.h"

#pragma mark -
#pragma mark Context management

void CPTPushCGContext(__nonnull CGContextRef newContext)
{
    UIGraphicsPushContext(newContext);
}

void CPTPopCGContext(void)
{
    UIGraphicsPopContext();
}

#pragma mark -
#pragma mark Debugging

CPTNativeImage *__nonnull CPTQuickLookImage(CGRect rect, __nonnull CPTQuickLookImageBlock renderBlock)
{
    UIGraphicsBeginImageContextWithOptions(rect.size, YES, 1.0);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextTranslateCTM(context, 0, rect.size.height);
    CGContextScaleCTM(context, 1.0, -1.0);

    CGContextSetRGBFillColor(context, CPTFloat(0xf6 / 255.0), CPTFloat(0xf5 / 255.0), CPTFloat(0xf6 / 255.0), 1.0);
    CGContextFillRect(context, rect);

    renderBlock(context, 1.0, rect);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return image;
}

#endif
