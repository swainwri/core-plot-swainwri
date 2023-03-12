//
//  DelaunayPoint.m
//  DelaunayTest
//
//  Created by Mike Rotondo on 7/17/11.
//  Copyright 2011 Stanford. All rights reserved.
//

#import "DelaunayPoint.h"
#import "DelaunayEdge.h"
#import "DelaunayTriangle.h"

@interface DelaunayPoint ()

@property (nonatomic, strong) NSMutableSet *edges;

@end

@implementation DelaunayPoint

@synthesize x, y, contribution;
@synthesize idNumber;
@synthesize edges = _edges;
@synthesize value;
@synthesize color;

+ (DelaunayPoint *)pointAtX:(CGFloat)newX andY:(CGFloat)newY
{
    NSInteger newID = arc4random();
    DelaunayPoint *point = [DelaunayPoint pointAtX:newX andY:newY withID:[NSNumber numberWithInteger:newID]];
    return point;
}

+ (DelaunayPoint *)pointAtX:(CGFloat)newX andY:(CGFloat)newY withID:(NSNumber *)idNumber
{
    DelaunayPoint *point = [[self alloc] init];
    point.x = newX;
    point.y = newY;
    point.idNumber = idNumber;
    point.contribution = 0.0;
//    point.color = [UIColor colorWithRed:(CGFloat)rand() / RAND_MAX
//                                  green:(CGFloat)rand() / RAND_MAX
//                                   blue:(CGFloat)rand() / RAND_MAX
//                                  alpha:1.0];
    return point;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        self.edges = [NSMutableSet set];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"(%.0f, %.0f)", self.x, self.y];
}

- (BOOL)isEqual:(id)object
{
    assert([object isKindOfClass:[self class]]);
    DelaunayPoint *otherPoint = (DelaunayPoint *)object;
    return [self.idNumber integerValue] == [otherPoint.idNumber integerValue];
}
- (NSUInteger)hash
{
    return [self.idNumber unsignedIntegerValue];
}

- (id)copyWithZone:(NSZone *)zone
{
    DelaunayPoint *copy = [DelaunayPoint pointAtX:self.x andY:self.y withID:self.idNumber];
    copy.contribution = self.contribution;
    copy.value = self.value;
    return copy;
}

- (nonnull NSArray *)counterClockwiseEdges
{
    return [[self.edges allObjects] sortedArrayUsingComparator:^(id obj1, id obj2) {
        DelaunayEdge *e1 = obj1;
        DelaunayEdge *e2 = obj2;
        
        DelaunayPoint *p1 = [e1 otherPoint:self];
        DelaunayPoint *p2 = [e2 otherPoint:self];
        
        CGFloat angle1 = atan2(p1.y - self.y, p1.x - self.x);
        CGFloat angle2 = atan2(p2.y - self.y, p2.x - self.x);
        if ( angle1 > angle2 )
            return NSOrderedAscending;
        else if ( angle1 < angle2 )
            return NSOrderedDescending;
        else
            return NSOrderedSame;
    }];
}

@end
