//
//  DelaunayEdge.m
//  DelaunayTest
//
//  Created by Mike Rotondo on 7/20/11.
//  Copyright 2011 Stanford. All rights reserved.
//

#import "DelaunayEdge.h"
#import "DelaunayTriangle.h"
#import "DelaunayPoint.h"

@interface DelaunayEdge ()

@property (nonatomic) CGFloat cachedLength;
- (CGFloat) determinant:(CGFloat[3][3])matrix;

@end

@implementation DelaunayEdge

@synthesize triangles;
@synthesize points;
@synthesize cachedLength;

+ (DelaunayEdge *)edgeWithPoints:(NSArray *)points
{
    DelaunayEdge *edge = [[self alloc] init];
    
    edge.points = points;

    for (DelaunayPoint *point in points)
    {
        [point.edges addObject:edge];
    }
    
    edge.triangles = [NSMutableSet setWithCapacity:2];
    
    return edge;
}


- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[self class]])
    {
        DelaunayEdge *otherEdge = object;
        return ([self.points[0] isEqual:otherEdge.points[0]] &&
                [self.points[1] isEqual:otherEdge.points[1]]);
    }
    return NO;
}
- (NSUInteger)hash
{
    return [(DelaunayPoint*)[self.points objectAtIndex:0] hash] ^ [(DelaunayPoint*)[self.points objectAtIndex:1] hash];

}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ -> %@", self.points[0], self.points[1]];
}

- (DelaunayTriangle *)neighborOf:(DelaunayTriangle *)triangle
{
//    if (![self.triangles containsObject:triangle])
//    {
//        NSLog(@"ASKED FOR THE NEIGHBOR OF A TRIANGLE THROUGH AN EDGE THAT DOESN'T BORDER THAT TRIANGLE!");
//        return nil;
//    }
    
    // There should only ever be 2 triangles in self.triangles
    for (DelaunayTriangle *edgeTriangle in self.triangles)
    {
        if (edgeTriangle != triangle)
            return edgeTriangle;
    }
    return nil;
}

- (DelaunayPoint *)otherPoint:(DelaunayPoint *)point
{
    if ( [[self.points objectAtIndex:0] isEqual: point] )
        return [self.points objectAtIndex:1];
    else if ( [[self.points objectAtIndex:1] isEqual: point] )
        return [self.points objectAtIndex:0];
    else
    {
        NSLog(@"ASKED FOR THE OTHER POINT WITH A POINT THAT IS NOT IN THIS EDGE");
        return nil;
    }
}

- (BOOL)pointOnLeft:(DelaunayPoint*)point withStartPoint:(DelaunayPoint *)startPoint
{
    if (![self.points containsObject:startPoint])
    {
        NSLog(@"ASKED IF POINT ON LEFT WITH A START POINT THAT IS NOT IN THIS EDGE");
        return NO;
    }
    
    DelaunayPoint *p0 = [self.points objectAtIndex:0];
    DelaunayPoint *p1 = [self.points objectAtIndex:1];
    
    CGFloat check[3][3] = {
        {p0.x, p0.y, 1},
        {p1.x, p1.y, 1},
        {point.x, point.y, 1}
    };
    
    CGFloat det = [self determinant:check];
    
    if (startPoint == p0)
        return det <= 0;
    else
        return det >= 0;
}

- (DelaunayTriangle *)sharedTriangleWithEdge:(DelaunayEdge *)otherEdge
{
    NSMutableSet *sharedTriangles = [self.triangles mutableCopy];
    
    [sharedTriangles intersectSet:otherEdge.triangles];
    
    if ([sharedTriangles count] == 0)
    {
        NSLog(@"ASKED FOR THE SHARED TRIANGLE WITH AN EDGE THAT DOESN'T SHARE ANY TRIANGLES WITH THIS EDGE");
        return nil;
    }
    if ([sharedTriangles count] > 1)
    {
        NSLog(@"SOMEHOW THIS EDGE SHARES MORE THAN ONE TRIANGLE WITH THE OTHER EDGE?!");
        return nil;
    }
    return [sharedTriangles anyObject];
}

- (CGFloat) determinant:(CGFloat[3][3])matrix
{
    CGFloat a = matrix[0][0];
    CGFloat b = matrix[0][1];
    CGFloat c = matrix[0][2];
    CGFloat d = matrix[1][0];
    CGFloat e = matrix[1][1];
    CGFloat f = matrix[1][2];
    CGFloat g = matrix[2][0];
    CGFloat h = matrix[2][1];
    CGFloat i = matrix[2][2];
    
    return (a * e * i -
            a * f * h -
            b * d * i +
            b * f * g +
            c * d * h -
            c * e * g);
}

- (CGFloat)length {
    if (self.cachedLength != 0) {
        return self.cachedLength;
    }
    
    DelaunayPoint *p1 = [self.points objectAtIndex:0];
    DelaunayPoint *p2 = [self.points objectAtIndex:1];
    self.cachedLength = sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
    return self.cachedLength;
}

@end
