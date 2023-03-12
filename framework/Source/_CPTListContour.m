//
//  CPTListContour.m
//  CorePlot
//
//  Created by Steve Wainwright on 22/11/2021.
//

#import "_CPTListContour.h"

void removeClosedAtIndex(BOOL *a, size_t n, size_t index);

void removeClosedAtIndex(BOOL *a, size_t n, size_t index) {
    if ( index < n ) {
        for( size_t i = index+1; i < n; i++ ) {
            a[i-1] =  a[i];
        }
    }
}

void swapLineStripElements(NSUInteger* a, NSUInteger* b);
int compareLineStripByPosition(const void *a, const void *b);

// Function to swap two memory contents
void swapLineStripElements(NSUInteger* a, NSUInteger* b){
    NSUInteger temp = *a;
    *a = *b;
    *b = temp;
}

int compareLineStripByPosition(const void *a, const void *b) {
    const NSUInteger *aO = (const NSUInteger*)a;
    const NSUInteger *bO = (const NSUInteger*)b;
    
    if (aO > bO) {
        return 1;
    }
    else if (aO < bO) {
        return -1;
    }
    else {
        return 0;
    }
}


void initLineStrip(LineStrip *a, size_t initialSize) {
    a->array = (NSUInteger*)malloc(initialSize * sizeof(NSUInteger));
    a->used = 0;
    a->size = initialSize;
}

void appendLineStrip(LineStrip *a, NSUInteger element) {
    // a->used is the number of used entries, because a->array[a->used++] updates a->used only *after* the array has been accessed.
    // Therefore a->used can go up to a->size
    if (a->used == a->size) {
        a->size *= 2;
        void *tmp = realloc(a->array, a->size * sizeof(NSUInteger));
        if ( tmp ) {
            a->array = (NSUInteger*)tmp;
        }
        else {
            return;
        }
    }
    a->array[a->used++] = element;
}

void insertLineStripAtIndex(LineStrip *a, NSUInteger element, size_t index) {
    if (a->used == a->size) {
        a->size *= 2;
        void *tmp = realloc(a->array, a->size * sizeof(NSUInteger));
        if ( tmp ) {
            a->array = (NSUInteger*)tmp;
        }
        else {
            return;
        }
    }
    size_t n = a->used;
    a->array[a->used++] = element;
    if ( index < a->used ) {
        // shift elements forward
        for( size_t i = n; i > index; i-- ) {
            a->array[i] =  a->array[i - 1];
        }
        a->array[index] = element;
    }
}

void removeLineStripAtIndex(LineStrip *a, size_t index) {
    size_t n = a->used;
    
    if ( index < n ) {
        for( size_t i = index+1; i < n; i++ ) {
            a->array[i-1] =  a->array[i];
        }
        a->used--;
    }
}

void copyLineStrip(LineStrip *a, LineStrip *b) {
    if ( b->size == 0 ) {
        initLineStrip(b, a->used);
    }
    for( size_t i = 0; i < a->used; i++ ) {
        appendLineStrip(b, a->array[i]);
    }
}

void assignLineStripInRange(LineStrip *a, LineStrip *b, size_t start, size_t end) {
    if(end > b->used - 1) {
        end = b->used - 1;
    }
    if(start < b->used - 1 && end <= b->used - 1 && start < end) {
        for( size_t i = start; i < end; i++ ) {
            appendLineStrip(a, b->array[i]);
        }
    }
}

NSUInteger searchForLineStripIndexForElement(LineStrip *a, NSUInteger element, NSUInteger startPos) {
    NSUInteger foundPos = NSNotFound;
    if ( startPos == NSNotFound ) {
        startPos = 0;
    }
    for(size_t i = (size_t)startPos; i < a->used; i++) {
        if(element == a->array[i]) {
            foundPos = (NSUInteger)i;
            break;
        }
    }
    return foundPos;
}

NSUInteger searchForLineStripIndexForElementWithTolerance(LineStrip *a, NSUInteger element, NSUInteger tolerance, NSUInteger columnMutliplier) {
    NSUInteger foundPos = NSNotFound;
    NSUInteger startPos = 0;
    // try it without a tolerance first
    if ( (foundPos = searchForLineStripIndexForElement(a, element, startPos)) == NSNotFound ) {
        NSUInteger x = 0, y = 0, layer = 1, leg = 0, iteration = 0;
        while ( iteration < tolerance * tolerance ) {
            if((foundPos = searchForLineStripIndexForElement(a, element + x + y * columnMutliplier, startPos)) != NSNotFound && (NSUInteger)labs((NSInteger)element - (NSInteger)a->array[foundPos]) < tolerance) {
                break;
            }
            else if ( foundPos == NSNotFound ) {
                startPos = 0;
            }
            iteration++;
            if ( leg == 0 ) {
                x++;
                if ( x == layer ) {
                    leg++;
                }
            }
            else if ( leg == 1 ) {
                y++;
                if ( y == layer) {
                    leg++;
                }
            }
            else if ( leg == 2 ) {
                x--;
                if ( -x == layer ) {
                    leg++;
                }
            }
            else if ( leg == 3 ) {
                y--;
                if ( -y == layer ) {
                    leg = 0;
                    layer++;
                }
            }
        }
    }

    return foundPos;
}

// Function to reverse the array through pointers
void reverseLineStrip(LineStrip *a) {
    // pointer1 pointing at the beginning of the array
    NSUInteger *pointer1 = a->array;
    // pointer2 pointing at end of the array
    NSUInteger *pointer2 = a->array + a->used - 1;
    while (pointer1 < pointer2) {
        swapLineStripElements(pointer1, pointer2);
        pointer1++;
        pointer2--;
    }
}

void sortLineStrip(LineStrip *a) {
    qsort(a->array, a->used, sizeof(LineStrip), compareLineStripByPosition);
}

NSUInteger distinctElementsInLineStrip(LineStrip *a, LineStrip *b) {
    
    if ( b->size == 0 ) {
        initLineStrip(b, a->used);
    }
    for( NSUInteger i = 0; i < a->used; i++ ) {
        appendLineStrip(b, a->array[i]);
    }
    LineStrip c;
    initLineStrip(&c, a->size);
    // First sort the array so that all occurrences become consecutive
    qsort(b->array, b->used, sizeof(NSUInteger), compareNSUInteger);
    NSUInteger n = b->used;
    // Traverse the sorted array
    for (NSUInteger i = 0; i < n; i++) {
        // Move the index ahead while there are duplicates
        while (i < n - 1 && b->array[i] == b->array[i + 1]) {
            i++;
        }
        appendLineStrip(&c, b->array[i]);
    }
    clearLineStrip(b);
    for( NSUInteger i = 0; i < c.used; i++ ) {
        appendLineStrip(b, c.array[i]);
    }
    freeLineStrip(&c);
    return b->used;
}

NSInteger checkLineStripToAnotherForSameDifferentOrder(LineStrip *a, LineStrip *b) {
    NSInteger same = -1;
    size_t count = 0;
    if( a->used == b->used ) {
        while ( TRUE ) {
            same = (memcmp(a->array, b->array, a->used * sizeof(NSUInteger)) == 0) ? 0 : 1;
            if ( same == 0 ) {
                break;
            }
            size_t n = b->used;
            NSUInteger temp = b->array[0];
            for( size_t j = 1; j < n; j++ ) {
                b->array[j-1] =  b->array[j];
            }
            b->array[n-1] = temp;
            count++;
            if ( count == n  ) {
                break;
            }
        }
    }
    return same;
}

void clearLineStrip(LineStrip *a) {
    a->used = 0;
}

void freeLineStrip(LineStrip *a) {
    free(a->array);
    a->array = NULL;
    a->used = a->size = 0;
}

void initLineStripList(LineStripList *a, size_t initialSize) {
    a->array = (LineStrip*)malloc(initialSize * sizeof(LineStrip));
    a->used = 0;
    a->size = initialSize;
}

void appendLineStripList(LineStripList *a, LineStrip element) {
    // a->used is the number of used entries, because a->array[a->used++] updates a->used only *after* the array has been accessed.
    // Therefore a->used can go up to a->size
    if (a->used == a->size) {
        a->size *= 2;
        void *tmp = realloc(a->array, a->size * sizeof(LineStrip));
        if ( tmp ) {
            a->array = (LineStrip*)tmp;
        }
        else {
            return;
        }
    }
    a->array[a->used++] = element;
}

void insertLineStripListAtIndex(LineStripList *a, LineStrip element, size_t index) {
    if (a->used == a->size) {
        a->size *= 2;
        void *tmp = realloc(a->array, a->size * sizeof(LineStrip));
        if ( tmp ) {
            a->array = (LineStrip*)tmp;
        }
        else {
            return;
        }
    }
    size_t n = a->used;
    a->array[a->used++] = element;
    if ( index < a->used ) {
        // shift elements forward
        for( size_t i = n; i > index; i-- ) {
            a->array[i] =  a->array[i - 1];
        }
        a->array[index] = element;
    }
}

void removeLineStripListAtIndex(LineStripList *a, size_t index) {
    size_t n = a->used;

    if ( index < n ) {
        for( size_t i = index+1; i < n; i++ ) {
            a->array[i-1] = a->array[i];
        }
        a->used--;
    }
}

NSUInteger findLineStripListIndexForLineStrip(LineStripList *a, LineStrip *b) {
    NSUInteger foundPos = NSNotFound;
    for(NSUInteger i = 0; i < (NSUInteger)a->used; i++) {
        if(b == &a->array[i]) {
            foundPos = i;
            break;
        }
    }
    return foundPos;
}

void sortLineStripList(LineStripList *a) {
    qsort(a->array, a->used, sizeof(LineStripList), compareLineStripListByPosition);
}

void clearLineStripList(LineStripList *a) {
    a->used = 0;
}

void freeLineStripList(LineStripList *a) {
    free(a->array);
    a->array = NULL;
    a->used = a->size = 0;
}

int compareLineStripListByPosition(const void *a, const void *b) {
    const LineStrip *aO = (const LineStrip*)a;
    const LineStrip *bO = (const LineStrip*)b;
    
    if (aO->array[0] > bO->array[0]) {
        return 1;
    }
    else if (aO->array[0] < bO->array[0]) {
        return -1;
    }
    else {
        return 0;
    }
}

void initIsoCurvesList(IsoCurvesList *a, size_t initialSize) {
    a->array = (LineStripList*)calloc(initialSize, sizeof(LineStripList));
    a->used = 0;
    a->size = initialSize;
}

void appendIsoCurvesList(IsoCurvesList *a, LineStripList element) {
    // a->used is the number of used entries, because a->array[a->used++] updates a->used only *after* the array has been accessed.
    // Therefore a->used can go up to a->size
    if (a->used == a->size) {
        a->size *= 2;
        a->array = (LineStripList*)realloc(a->array, a->size * sizeof(LineStripList));
    }
    a->array[a->used++] = element;
}


void clearIsoCurvesList(IsoCurvesList *a) {
    a->used = 0;
}

void freeIsoCurvesList(IsoCurvesList *a) {
    free(a->array);
    a->array = NULL;
    a->used = a->size = 0;
}

@interface CPTListContour()


@end

@implementation CPTListContour

// array of line strips
static IsoCurvesList stripLists;
static double overrideWeldDistMultiplier;

@synthesize overrideWeldDistance; // for flexiblity may want to override the Weld Distance for compacting contours

//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

-(nonnull instancetype)initWithNoIsoCurve:(NSUInteger)newNoIsoCurves IsoCurveValues:(double*)newContourPlanes Limits:(double*)newLimits {
    
    NSAssert(newLimits[0] < newLimits[1], @"X: lower limit must be less than upper limit ");
    NSAssert(newLimits[2] < newLimits[3], @"Y: lower limit must be less than upper limit ");
    
    self = [super initWithNoIsoCurve:newNoIsoCurves IsoCurveValues:newContourPlanes Limits:newLimits];
    self.overrideWeldDistance = NO;
    overrideWeldDistMultiplier = 1.0;
        
    return self;
}

-(void)dealloc {
    [self cleanMemory];
}

-(ContourPlanes* _Nullable) getContourPlanes {
    return [super getContourPlanes];
}

-(IsoCurvesList*) getIsoCurvesLists {
    return &stripLists;
}

-(void)generateAndCompactStrips {
    // generate line strips
    if( [self generate] ) {
        // compact strips
        [self compactStrips];
    }
}

-(void) initialiseMemory {
    if ( stripLists.size > 0 ) {
        [self cleanMemory];
    }
    [super initialiseMemory];
    NSUInteger noIsoCurves = [self getNoIsoCurves];
    initIsoCurvesList(&stripLists, (size_t)noIsoCurves);
    for(NSUInteger i = 0; i < noIsoCurves; i++) {
        LineStripList list;
        initLineStripList(&list, 4);
        appendIsoCurvesList(&stripLists, list);
    }
}

-(void) cleanMemory {
    
    [super cleanMemory];
    
    LineStrip* pStrip;
    LineStripList *pStripList;
    
    if ( stripLists.size > 0 ) {
        // reseting lists
        NSAssert(stripLists.size == (size_t)[self getNoIsoCurves], @"stripLists not same size as asked for");
        for (NSUInteger i = 0; i < stripLists.size; i++) {
            pStripList = &stripLists.array[i];
            NSAssert(pStripList != NULL, @"LineStripList is NULL");
            for(NSUInteger j = 0; j < pStripList->used; j++) {
                pStrip = &pStripList->array[j];
                NSAssert(pStrip != NULL, @"LineStrip is NULL");
                freeLineStrip(pStrip);
            }
            freeLineStripList(pStripList);
        }
        freeIsoCurvesList(&stripLists);
    }
}


-(LineStripList*) getStripListForIsoCurve:(NSUInteger)iPlane {
    return &stripLists.array[iPlane];
}

-(void) setStripListAtPlane:(NSUInteger)iPlane StripList:(LineStripList*)pLineStripList {
    NSAssert(iPlane < [self getNoIsoCurves] && iPlane != NSNotFound, @"iPlane not in range");
    
    LineStrip* pStrip;
    LineStripList* actualStripList = [self getStripListForIsoCurve:iPlane];
    for(NSUInteger pos = 0; pos < (NSUInteger)pLineStripList->used; pos++) {
        pStrip = &pLineStripList->array[pos];
        if(pStrip->used > 0) {
            appendLineStripList(actualStripList, *pStrip);
        }
    }
}

-(void) exportLineForIsoCurve:(NSUInteger)iPlane FromX1:(NSUInteger)x1 FromY1:(NSUInteger)y1 ToX2:(NSUInteger)x2 ToY2:(NSUInteger)y2 {
    NSAssert(iPlane != NSNotFound && iPlane < [self getNoIsoCurves], @"Plane index is not valid 0 to no. Planes");
    
    // check that the two points are not at the beginning or end of the some line strip
    NSUInteger i1 = y1 * ([self getNoColumnsSecondaryGrid] + 1) + x1;
    NSUInteger i2 = y2 * ([self getNoColumnsSecondaryGrid] + 1) + x2;
    
    if ( (NSInteger)i1 < 0 || (NSInteger)i2 < 0 ) {
        self.overrideWeldDistance = YES;
//        return;
    }
    
    LineStripList* pStripList = &stripLists.array[iPlane];
    if ( pStripList->size == 0 ) {
        initLineStripList(pStripList, 8);
        LineStrip strip;
        initLineStrip(&strip, 2);
        appendLineStrip(&strip, i1);
        appendLineStrip(&strip, i2);
        appendLineStripList(pStripList, strip);
    }
    else {
        BOOL added = NO;
        for (NSUInteger pos = 0; pos < pStripList->used && !added; pos++) {
            LineStrip* pStrip = &pStripList->array[pos];
            NSAssert(pStrip->array != NULL, @"LineStrip is NULL");
            if (i1 == pStrip->array[0]) {
                insertLineStripAtIndex(pStrip, i2, 0);
                added = YES;
                break;
            }
            else if (i1 == pStrip->array[pStrip->used-1]) {
                appendLineStrip(pStrip, i2);
                added = YES;
                break;
            }
            else if (i2 == pStrip->array[0]) {
                insertLineStripAtIndex(pStrip, i1, 0);
                added = YES;
                break;
            }
            else if (i2 == pStrip->array[pStrip->used-1]) {
                appendLineStrip(pStrip, i1);
                added = YES;
                break;
            }
        }
        if ( !added ) {
            // segment was not part of any line strip, creating new one
            LineStrip strip;
            initLineStrip(&strip, 8);
            appendLineStrip(&strip, i1);
            appendLineStrip(&strip, i2);
            insertLineStripListAtIndex(pStripList, strip, 0);
        }
    }
}

-(BOOL) forceMerge:(LineStrip*) pStrip1 With:(LineStrip*) pStrip2 {
    
    if (pStrip2->used == 0) {
        return false;
    }
    
    double x[4], y[4], weldDist;
    BOOL edge[4];
    NSUInteger index = pStrip1->array[0];
    x[0] = [self getXAt:index];
    y[0] = [self getYAt:index];
    edge[0] = [self isNodeOnBoundary:index];
    index = pStrip1->array[pStrip1->used - 1];
    x[1] = [self getXAt:index];
    y[1] = [self getYAt:index];
    edge[1] = [self isNodeOnBoundary:index];
//    double gradient01 = (y[1] - y[0]) / (x[1] - x[0]);
    
    index = pStrip2->array[0];
    x[2] = [self getXAt:index];
    y[2] = [self getYAt:index];
    edge[2] = [self isNodeOnBoundary:index];
    index = pStrip2->array[pStrip2->used - 1];
    x[3] = [self getXAt:index];
    y[3] = [self getYAt:index];
    edge[3] = [self isNodeOnBoundary:index];
//    double gradient23 = (y[3] - y[2]) / (x[3] - x[2]);
    
//    BOOL centreLine = (isinf(gradient01) || gradient01 == 0.0) && (isinf(gradient23) || gradient23 == 0.0) && self.containsFunctionNans;
    
    weldDist = overrideWeldDistMultiplier * (pow([self getDX], 2.0) + pow([self getDY], 2.0));
    if ( self.overrideWeldDistance ) {
        weldDist *= overrideWeldDistMultiplier;
    }
    double diff12 = (x[1] - x[2]) * (x[1] - x[2]) + (y[1] - y[2]) * (y[1] - y[2]);
    if ( (diff12 < weldDist || (diff12 < weldDist * overrideWeldDistMultiplier && self.containsFunctionNans)) && !edge[1] && !edge[2]) {
        for(NSInteger i = 0; i < (NSInteger)pStrip2->used; i++) {
            index = pStrip2->array[i];
            NSAssert(index >= 0, @"index has to be >= 0");
            appendLineStrip(pStrip1, index);
        }
        clearLineStrip(pStrip2);
        return true;
    }
    double diff30 = (x[3] - x[0]) * (x[3] - x[0]) + (y[3] - y[0]) * (y[3] - y[0]);
    if ( (diff30 < weldDist || (diff30 < weldDist * overrideWeldDistMultiplier && self.containsFunctionNans)) && !edge[3] && !edge[0]) {
        for(NSInteger i = (NSInteger)pStrip2->used-1; i > -1; i--) {
            index = pStrip2->array[i];
            NSAssert(index >= 0, @"index has to be >= 0");
            insertLineStripAtIndex(pStrip1, index, 0);
        }
        clearLineStrip(pStrip2);
        return true;
    }
    double diff13 = (x[1] - x[3]) * (x[1] - x[3]) + (y[1] - y[3]) * (y[1] - y[3]);
    if ( (diff13 < weldDist || (diff13 < weldDist * overrideWeldDistMultiplier && self.containsFunctionNans)) && !edge[1] && !edge[3]) {
        for(NSInteger i = (NSInteger)pStrip2->used-1; i > -1; i--) {
            index = pStrip2->array[i];
            NSAssert(index >= 0, @"index has to be >= 0");
            appendLineStrip(pStrip1, index);
        }
        clearLineStrip(pStrip2);
        return true;
    }
    double diff02 = (x[0] - x[2]) * (x[0] - x[2]) + (y[0] - y[2]) * (y[0] - y[2]);
    if ( (diff02 < weldDist || (diff02 < weldDist * overrideWeldDistMultiplier && self.containsFunctionNans)) && !edge[0] && !edge[2]) {
        for(NSInteger i = 0; i < (NSInteger)pStrip2->used; i++) {
            index = pStrip2->array[i];
            NSAssert(index >= 0, @"index has to be >= 0");
            insertLineStripAtIndex(pStrip1, index, 0);
        }
        clearLineStrip(pStrip2);
        return true;
    }

    return false;
}

-(BOOL) mergeStrips:(LineStrip*) pStrip1 With:(LineStrip*) pStrip2 {
    if (pStrip2->used == 0) {
        return false;
    }
    
    NSUInteger index;
    // debugging stuff
    if (pStrip2->array[0] == pStrip1->array[0]) {
        // not using first element
        // adding the rest to strip1
        for(NSUInteger pos = 1; pos < (NSUInteger)pStrip2->used; pos++) {
            index = pStrip2->array[pos];
            NSAssert(index >= 0 && index != NSNotFound, @"index not valid");
            insertLineStripAtIndex(pStrip1, index, 0);
        }
        clearLineStrip(pStrip2);
        return true;
    }
    
    if (pStrip2->array[0] == pStrip1->array[pStrip1->used-1]) {
        // adding the rest to strip1
        for(NSUInteger pos = 1; pos < (NSUInteger)pStrip2->used; pos++) {
            index = pStrip2->array[pos];
            NSAssert(index >= 0 && index != NSNotFound, @"index not valid");
            appendLineStrip(pStrip1, index);
        }
        clearLineStrip(pStrip2);
        return true;
    }
    
    if (pStrip2->array[pStrip2->used-1] == pStrip1->array[0]) {
        for(NSInteger pos = (NSInteger)pStrip2->used - 2; pos > -1; pos--) {
            index = pStrip2->array[(NSUInteger)pos];
            NSAssert(index >= 0, @"index not valid");
            insertLineStripAtIndex(pStrip1, index, 0);
        }
        clearLineStrip(pStrip2);
        return true;
    }
    
    if (pStrip2->array[pStrip2->used-1] == pStrip1->array[pStrip1->used-1]) {
        for(NSInteger pos = (NSInteger)pStrip2->used - 2; pos > -1; pos--) {
            index = pStrip2->array[(NSUInteger)pos];
            NSAssert(index >= 0, @"index not valid");
            appendLineStrip(pStrip1, index);
        }
        clearLineStrip(pStrip2);
        return true;
    }
    
    return false;
}

// Basic algorithm to concatanate line strip. Not optimized at all !
-(void) compactStrips {
    NSAssert(stripLists.used == [self getNoIsoCurves], @"No of Planes(isocurves) not the same a striplist used");
    if ( stripLists.used > 0 ) {
        LineStrip* pStrip = NULL;
        LineStrip* pStripBase = NULL;
        LineStripList* pStripList = NULL;
        
        BOOL again;
        LineStripList newList;
        initLineStripList(&newList, 4);
        LineStrip distinctStrip1, distinctStrip2;
        initLineStrip(&distinctStrip1, 8);
        initLineStrip(&distinctStrip2, 8);
        NSUInteger noDistinct1, noDistinct2;
        
        const NSUInteger diffSecondaryToPrimaryColumns = [self getNoColumnsSecondaryGrid] / [self getNoColumnsFirstGrid];
        const NSUInteger diffSecondaryToPrimaryRows = [self getNoRowsSecondaryGrid] / [self getNoRowsFirstGrid];
        overrideWeldDistMultiplier = sqrt(pow(diffSecondaryToPrimaryColumns, 2) + pow(diffSecondaryToPrimaryRows, 2));
        const double weldDist = overrideWeldDistMultiplier * (pow(MAX([self getDX], [self getDY]), 2.0));
    //    NSLog(@"wellDist: %f\n", weldDist);
    //    NSLog(@"deltaX: %f\n", [self getDX]);
    //    NSLog(@"deltaY: %f\n", [self getDY]);
        
        for (NSUInteger i = 0; i < stripLists.used; i++) {
            pStripList = &stripLists.array[i];
            again = YES;
            while(again) {
                // REPEAT COMPACT PROCESS UNTIL LAST PROCESS MAKES NO CHANGE
                again = NO;
                // building compacted list
                NSAssert(newList.used == 0, @"newList is empty");
                for (NSUInteger pos = 0; pos < (NSUInteger)pStripList->used; pos++) {
                    pStrip = &pStripList->array[pos];
//#if DEBUG
//                  for ( NSUInteger k = 0; k < pStrip->used; k++ ) {
//                      printf("%ld\n", pStrip->array[k]);
//                  }
//                  printf("\n");
//#endif
                    for (NSUInteger pos2 = 0; pos2 < (NSUInteger)newList.used; pos2++) {
                        pStripBase = &newList.array[pos2];
                        if([self mergeStrips:pStripBase With:pStrip]) {
                            again = YES;
                        }
                        if(pStrip->used == 0) {
                            break;
                        }
                    }
                    if(pStrip->used == 0) {
//                        pStripList->array[pos].array = NULL;
//                        pStripList->array[pos].size = pStripList->array[pos].used = 0;
                        removeLineStripListAtIndex(pStripList, pos);
                        pos--;
                    }
                    else {
                        insertLineStripListAtIndex(&newList, *pStrip, 0);
                    }
                }
                
                // deleting old list
                clearLineStripList(pStripList);
                
                // Copying all
                for(NSUInteger pos2 = 0; pos2 < (NSUInteger)newList.used; pos2++) {
                    pStrip = &newList.array[pos2];
                    NSUInteger pos1 = 0, pos3;
                    while(pos1 < (NSUInteger)pStrip->used) {
                        pos3 = pos1;
                        pos3++;
                        if( pos3 > (NSUInteger)pStrip->used-1 ) {
                            break;
                        }
                        if(pStrip->array[pos1] == pStrip->array[pos3]) {
                            removeLineStripAtIndex(pStrip, pos3);
                        }
                        else {
                            pos1++;
                        }
                    }
                    if(pStrip->used != 1) {
                        insertLineStripListAtIndex(pStripList, *pStrip, 0);
                    }
                    else {
//                        pStripList->array[pos2].array = NULL;
//                        pStripList->array[pos2].size = pStripList->array[pos2].used = 0;
                        removeLineStripListAtIndex(pStripList, pos2);
                    }
                }
                // emptying temp list
                clearLineStripList(&newList);
            } // OF WHILE(AGAIN) (LAST COMPACT PROCESS MADE NO CHANGES)
            
            if (pStripList->used == 0) {
                continue;
            }
            ///////////////////////////////////////////////////////////////////////
            // compact more
            NSUInteger index, count = 0;
            NSUInteger Nstrip = (NSUInteger)pStripList->used;
            BOOL *closed = (BOOL*)calloc(pStripList->used, sizeof(BOOL));
            double x,y;
            
            // First let's find the open and closed lists in m_vStripLists
            for(NSUInteger j = 0; j < pStripList->used; j++) {
                pStrip = &pStripList->array[j];
                // is it open ?
                if (pStrip->array[0] != pStrip->array[pStrip->used-1]) {
                    index = pStrip->array[0];
                    x = [self getXAt:index];
                    y = [self getYAt:index];
                    index = pStrip->array[pStrip->used-1];
                    x -= [self getXAt:index];
                    y -= [self getYAt:index];
                    
                    if ( x * x + y * y < weldDist && pStrip->used > 2 ) { // is it "almost closed" ?
                        closed[j] = YES;
                    }
                    else {
                        closed[j] = NO;
                        count++; // updating not closed counter...
                    }
                }
                else {
                    closed[j] = YES;
                }
            }
            // added S.Wainwright 10/11/2022
            // now find if tiny closed strips are close enough to form an open strip
            if ( /*count > 0 &&*/ pStripList->used > 2 && pStripList->used - count > pStripList->used * 8 / 10 ) {
                LineStrip* pStripNext = NULL;
                LineStrip newLineStrip;
                NSInteger lastPoint = 0, newLastPoint = 0, nextLastPoint = 0;
                initLineStrip(&newLineStrip, pStripList->used == 0 ? 8 : pStripList->used);
                for( NSInteger j = 0; j < (NSInteger)pStripList->used - 1; j++ ) {
                    pStrip = &pStripList->array[j];
                    lastPoint = (NSInteger)(pStrip->used - 1);
                    if (!closed[j] && pStrip->used > 2) {
                        newLastPoint = (NSInteger)(newLineStrip.used - 1);
                        lastPoint = (NSInteger)(pStrip->used - 1);
                        if ( pStrip->array[0] == newLineStrip.array[newLastPoint] || pStrip->array[lastPoint] == newLineStrip.array[newLastPoint] ) {
                            noDistinct1 = distinctElementsInLineStrip(pStrip, &distinctStrip1);
                            if ( distinctStrip1.array[0] == newLineStrip.array[newLineStrip.used-1] ) {
                                for (NSUInteger k = 1; k < noDistinct1; k++) {
                                    appendLineStrip(&newLineStrip, distinctStrip1.array[k]);
                                }
                            }
                            else {
                                for (NSInteger k = (NSInteger)noDistinct1 - 2; k > -1; k--) {
                                    appendLineStrip(&newLineStrip, distinctStrip1.array[k]);
                                }
                            }
                            removeClosedAtIndex(closed, pStripList->used, (NSUInteger)j);
                            removeLineStripListAtIndex(pStripList, (NSUInteger)j);
                            j--;
                        }
                        else  {
                            if ( newLineStrip.used > 1 ) {
                                LineStrip addLineStrip;
                                initLineStrip(&addLineStrip, newLineStrip.used);
                                copyLineStrip(&newLineStrip, &addLineStrip);
                                appendLineStripList(pStripList, addLineStrip);
                                closed[pStripList->used - 1] = NO;
                                removeClosedAtIndex(closed, pStripList->used, (NSUInteger)j);
                                removeLineStripListAtIndex(pStripList, (NSUInteger)j);
                            }
                            clearLineStrip(&newLineStrip);
                        }
                    }
                    else {
                        pStripNext = &pStripList->array[j + 1];
                        nextLastPoint = (NSInteger)(pStripNext->used - 1);
                        if (pStrip->array[0] == pStrip->array[lastPoint] && pStripNext->array[0] == pStripNext->array[nextLastPoint]) {
                            noDistinct1 = distinctElementsInLineStrip(pStrip, &distinctStrip1);
                            if ( noDistinct1 > 0 && newLineStrip.array[newLastPoint] != distinctStrip1.array[distinctStrip1.used - 1] ) {
                                for (NSUInteger k = 1; k < noDistinct1; k++) {
                                    appendLineStrip(&newLineStrip, distinctStrip1.array[k]);
                                }
                            }
                            noDistinct2 = distinctElementsInLineStrip(pStripNext, &distinctStrip2);
                            if ( noDistinct2 > 0 && distinctStrip2.array[0] > distinctStrip1.array[distinctStrip1.used - 1] && (distinctStrip2.array[0] - distinctStrip1.array[distinctStrip1.used - 1]) / [self getNoColumnsSecondaryGrid] <= diffSecondaryToPrimaryColumns ) {
                                for (NSUInteger k = 1; k < noDistinct2; k++) {
                                    appendLineStrip(&newLineStrip, distinctStrip2.array[k]);
                                }
                            }
                            else {
                                if ( (distinctStrip1.array[distinctStrip1.used - 1] - distinctStrip2.array[0]) / [self getNoColumnsSecondaryGrid] <= diffSecondaryToPrimaryColumns ) {
                                    for (NSInteger k = (NSInteger)noDistinct2 - 1; k > -1 ; k--) {
                                        appendLineStrip(&newLineStrip, distinctStrip2.array[k]);
                                    }
                                }
                            }
                            removeClosedAtIndex(closed, pStripList->used, (NSUInteger)j);
                            removeLineStripListAtIndex(pStripList, (NSUInteger)j);
                            j--;
                        }
                        clearLineStrip(&distinctStrip1);
                        clearLineStrip(&distinctStrip2);
                    }
                }
                if ( newLineStrip.used > 1) {
                    LineStrip addLineStrip;
                    initLineStrip(&addLineStrip, newLineStrip.used);
                    copyLineStrip(&newLineStrip, &addLineStrip);
                    appendLineStripList(pStripList, addLineStrip);
                    closed[pStripList->used - 1] = NO;
                    count = 0;
                    Nstrip = (NSUInteger)pStripList->used;
                    for ( NSUInteger j = 0; j < pStripList->used; j++) {
                        if (!closed[j]) {
                            count++;
                        }
                    }
                }
                freeLineStrip(&newLineStrip);
            }
            
            // is there any open strip ?
            if (count > 1) {
                // Merge the open strips into NewList
                NSUInteger pos = 0;
                for(NSUInteger j = 0; j < Nstrip; j++) {
                    if (!closed[j]) {
                        pStrip = &pStripList->array[pos];
                        insertLineStripListAtIndex(&newList, *pStrip, 0);
                        removeLineStripListAtIndex(pStripList, pos);
                    }
                    else {
                        pos++;
                    }
                }
                
                // are there open strips to process ?
                while(newList.used > 1) {
                    pStripBase = &newList.array[0];
                    // merge the rest to pStripBase
                    again = YES;
                    while (again) {
                        again = NO;
                        for(pos = 1; pos < (NSUInteger)newList.used; pos++) {
                            pStrip = &newList.array[pos];
                            if ([self forceMerge:pStripBase With:pStrip]) {
                                again = YES;
                                removeLineStripListAtIndex(&newList, pos);
                            }
                        }
                    } // while(again)
                    
                    index = pStripBase->array[0];
                    x = [self getXAt:index];
                    y = [self getYAt:index];
                    index = pStripBase->array[pStripBase->used - 1];
                    x -= [self getXAt:index];
                    y -= [self getYAt:index];
                    
                    // if pStripBase is closed or not
                    if (x * x + y * y < weldDist && !self.overrideWeldDistance) {
                        NSLog(@"# Plane %ld: open strip ends close enough based on weldDist  %ld && %ld, continue.\n\n", i, pStripBase->array[0], pStripBase->array[pStripBase->used-1]);
                        insertLineStripListAtIndex(pStripList, *pStripBase, 0);
                        removeLineStripListAtIndex(&newList, 0);
                    }
                    else {
                        if ([self onBoundaryWithStrip:pStripBase]) {
                            NSLog(@"# Plane %ld: open strip ends on boundary %ld(%f,%f) && %ld(%f,%f), continue.\n\n", i, pStripBase->array[0], [self getXAt:pStripBase->array[0]], [self getYAt:pStripBase->array[0]], pStripBase->array[pStripBase->used-1], [self getXAt:pStripBase->array[pStripBase->used-1]], [self getYAt:pStripBase->array[pStripBase->used-1]]);
                            insertLineStripListAtIndex(pStripList, *pStripBase, 0);
                            removeLineStripListAtIndex(&newList, 0);
                        }
                        else {
                            NSLog(@"# Plane %ld: unpaired open strip %ld(%f,%f) && %ld(%f,%f) at 1, override Weld Distance:%@!\n\n", i, pStripBase->array[0], [self getXAt:pStripBase->array[0]], [self getYAt:pStripBase->array[0]], pStripBase->array[pStripBase->used-1], [self getXAt:pStripBase->array[pStripBase->used-1]], [self getYAt:pStripBase->array[pStripBase->used-1]], self.overrideWeldDistance ? @"Y" : @"N");
                            if ( self.overrideWeldDistance ) {
                                insertLineStripListAtIndex(pStripList, *pStripBase, 0);
                                removeLineStripListAtIndex(&newList, 0);
                            }
                            else {
                                //                            [self dumpPlane:i];
                                //                        delete pStripBase;
                                //                            if ( newList.used > 0 ) {
                                //                                insertLineStripListAtIndex(&newList, newList.array[newList.used-1], 0);
                                //                                removeLineStripListAtIndex(&newList, newList.used-1);
                                //                            }
                                //                            newList.front() = newList.back();
                                //                            newList.pop_back();
                                //                        }
                                //            //            exit(0);
                                removeLineStripListAtIndex(&newList, 0);
                                //                            break;
                            }
                        }
                    }
                } // while(newList.size()>1);
                
                
                if (newList.used == 1) {
                    pStripBase = &newList.array[0];
                    if ([self onBoundaryWithStrip:pStripBase]) {
                        NSLog(@"# Plane %ld: open strip ends on boundary %ld(%f,%f) && %ld(%f,%f), continue.\n\n", i, pStripBase->array[0], [self getXAt:pStripBase->array[0]], [self getYAt:pStripBase->array[0]], pStripBase->array[pStripBase->used-1], [self getXAt:pStripBase->array[pStripBase->used-1]], [self getYAt:pStripBase->array[pStripBase->used-1]]);
                        insertLineStripListAtIndex(pStripList, *pStripBase, 0);
                        removeLineStripListAtIndex(&newList, 0);
                    }
                    else {
                        NSLog(@"# Plane %ld: unpaired open strip %ld(%f,%f) && %ld(%f,%f) at 2, override Weld Distance:%@!\n\n", i, pStripBase->array[0], [self getXAt:pStripBase->array[0]], [self getYAt:pStripBase->array[0]], pStripBase->array[pStripBase->used-1], [self getXAt:pStripBase->array[pStripBase->used-1]], [self getYAt:pStripBase->array[pStripBase->used-1]], self.overrideWeldDistance ? @"Y" : @"N");
                        if ( self.overrideWeldDistance ) {
                            insertLineStripListAtIndex(pStripList, *pStripBase, 0);
                            removeLineStripListAtIndex(&newList, 0);
                        }
                        else {
                            removeLineStripListAtIndex(&newList, 0);
                        }
                        //                    [self dumpPlane:i];
                        //                    delete pStripBase;
                        //                    if ( newList.size() > 0 ) {
                        //                        newList.front() = newList.back();
                        //                        newList.pop_back();
                        //                    }
                        //exit(0);
                    }
                }
                clearLineStripList(&newList);
            }
            else if (count == 1) {
                NSUInteger pos = 0;
                for(NSUInteger j = 0;j < Nstrip; j++) {
                    if ( !closed[j] ) {
                        pStripBase = &pStripList->array[pos];
                        break;
                    }
                    pos++;
                }
                if ( pStripBase != NULL ) {
                    if ([self onBoundaryWithStrip:pStripBase]) {
                        NSLog(@"# Plane %ld: open strip ends on boundary %ld(%f,%f) && %ld(%f,%f), continue.\n\n", i, pStripBase->array[0], [self getXAt:pStripBase->array[0]], [self getYAt:pStripBase->array[0]], pStripBase->array[pStripBase->used-1], [self getXAt:pStripBase->array[pStripBase->used-1]], [self getYAt:pStripBase->array[pStripBase->used-1]]);
                    }
                    else {
                        NSLog(@"# Plane %ld: unpaired open strip %ld(%f,%f) && %ld(%f,%f) at 3!\n\n", i, pStripBase->array[0], [self getXAt:pStripBase->array[0]], [self getYAt:pStripBase->array[0]], pStripBase->array[pStripBase->used-1], [self getXAt:pStripBase->array[pStripBase->used-1]], [self getYAt:pStripBase->array[pStripBase->used-1]]);
                        freeLineStrip(pStripBase);
                        removeLineStripListAtIndex(&newList, 0);
                        
                        //                [self dumpPlane:i];
                        //                delete pStripBase;
                        //                if ( newList.size() > 0 ) {
                        //                    newList.front() = newList.back();
                        //                    newList.pop_back();
                        //                }
                        // exit(0);
                    }
                }
            }
            
            for(NSUInteger j = 0; j < pStripList->used; j++) {
                if ( !closed[j] ) {
                    pStripBase = &pStripList->array[j];
                    LineStripList newBorderList;
                    initLineStripList(&newBorderList, 2);
                    if ( [self checkOpenStripNoMoreThan2Boundaries:pStripBase list:&newBorderList] ) {
                        removeLineStripListAtIndex(pStripList, j);
                        for ( NSUInteger k = 0; k < newBorderList.used; k++) {
                            appendLineStripList(pStripList, newBorderList.array[k]);
                        }
                    }
                    else {
                        freeLineStripList(&newBorderList);
                    }
                }
            }
            
            free(closed);
            //////////////////////////////////////////////////////////////////////////////////////////////////
            clearLineStripList(&newList);
        }
        freeLineStripList(&newList);
        freeLineStrip(&distinctStrip1);
        freeLineStrip(&distinctStrip2);
        // clean up any lists with no elements
        for ( NSUInteger i = 0; i < stripLists.used; i++ ) {
            pStripList = &stripLists.array[i];
            for ( NSInteger j = (NSInteger)pStripList->used - 1; j > -1; j-- ) {
                pStrip = &(pStripList->array[j]);
                if ( pStrip->used == 0 ) {
                    removeLineStripListAtIndex(pStripList, (size_t)j);
                }
            }
        }
    }
}

-(BOOL) checkOpenStripNoMoreThan2Boundaries:(LineStrip*) pStrip list:(LineStripList*)pList  {
    BOOL e1 = NO;
    if (pStrip != NULL) {
        if ( pList->size == 0 ) {
            initLineStripList(pList, 2);
        }
        double *limits = [self getLimits];
        double x, y;
        NSUInteger index, start = 0, end;
        for ( NSUInteger pos = 0; pos < (NSUInteger)pStrip->used; pos++ ) {
            index = pStrip->array[pos];
            x = [self getXAt:index];
            y = [self getYAt:index];
            if ( (x == limits[0] || x == limits[1] || y == limits[2] || y == limits[3] || fabs(x - limits[0]) < 1E-6 || fabs(x - limits[1]) < 1E-6 || fabs(y - limits[2]) < 1E-6 || fabs(y - limits[3]) < 1E-6) && !(pos == 0 || pos == (NSUInteger)pStrip->used-1) ) {
                end = pos;
                if ( end - start > 1 ) {
                    LineStrip newStrip;
                    initLineStrip(&newStrip, end - start);
                    for( NSUInteger pos2 = start; pos2 < end + 1; pos2++ ) {
                        appendLineStrip(&newStrip, pStrip->array[pos2]);
                    }
                    appendLineStripList(pList, newStrip);
                    e1 = YES;
                }
                start = end;
            }
        }
    }
    return e1;
}

-(BOOL) onBoundaryWithStrip:(LineStrip*) pStrip {
    BOOL e1 = NO, e2 = NO;
    if (pStrip != NULL) {
        NSUInteger index = pStrip->array[0];
        double x = [self getXAt:index], y = [self getYAt:index];
        double *limits = [self getLimits];
        if (x == limits[0] || x == limits[1] || y == limits[2] || y == limits[3]) {
            e1 = YES;
        }
        else if ( fabs(x - limits[0]) < 1E-6 || fabs(x - limits[1]) < 1E-6 || fabs(y - limits[2]) < 1E-6 || fabs(y - limits[3]) < 1E-6) {
            e1 = YES;
        }
        else {
            e1 = NO;
        }
        index = pStrip->array[pStrip->used - 1];
        x = [self getXAt:index];
        y = [self getYAt:index];
        if (x == limits[0] || x == limits[1] || y == limits[2] || y == limits[3]) {
            e2 = YES;
        }
        else if ( fabs(x - limits[0]) < 1E-6 || fabs(x - limits[1]) < 1E-6 || fabs(y - limits[2]) < 1E-6 || fabs(y - limits[3]) < 1E-6) {
            e1 = YES;
        }
        else {
            e2 = NO;
        }
    }
    return (e1 && e2);
}

-(void) setLinesForPlane:(NSUInteger)iPlane LineStripList:(LineStripList*)lineStripList {
    NSAssert(iPlane != NSNotFound && iPlane < [self getNoIsoCurves], @"Plane not between valid ranges");
    
    LineStripList* pStripList;
    LineStrip* pStrip;
    if(lineStripList->used != 0) {
        for(NSInteger i = 0; i < (NSInteger)lineStripList->used; i++) {
            pStrip = &lineStripList->array[i];
            if(pStrip->used != 0) {
                pStripList = &stripLists.array[iPlane];
                insertLineStripListAtIndex(pStripList, *pStrip, 0);
            }
        }
    }
}

/// debugging
-(void) dumpPlane:(NSUInteger)iPlane {
    NSAssert(iPlane >= 0 && iPlane < [self getNoIsoCurves], @"iPlane index not between range");

    LineStripList* pStripList = &stripLists.array[iPlane];
    printf("Level: %f\n", [self getIsoCurveAt:iPlane]);
    printf("Number of strips : %ld\n", pStripList->used);
    printf("i\tnp\tstart\tend\txstart\tystart\txend\tyend\n");

    LineStrip* pStrip;
    for (NSInteger i = 0; i < (NSInteger)pStripList->used; i++) {
        pStrip = &pStripList->array[i];
        NSAssert(pStrip != NULL, @"pStrip not set");
        if ( pStrip->used > 0 ) {
            printf("%ld\t%ld\t%ld\t%ld\t%0.7f\t%0.7f\t%0.7f\t%0.7f\n", i, pStrip->used, pStrip->array[0], pStrip->array[pStrip->used-1], [self getXAt:pStrip->array[0]], [self getYAt:pStrip->array[0]], [self getXAt:pStrip->array[pStrip->used-1]], [self getYAt:pStrip->array[pStrip->used-1]] );
        }
    }
    printf("\n");
}

// Area given by this function can be positive or negative depending on the winding direction of the contour.
-(double) area:(LineStrip*)line {
    // if Line is not closed, return 0;
    
    double Ar = 0, x, y, x0, y0, x1, y1;
    
    NSUInteger index = line->array[0];
    x0 = x =  [self getXAt:index];
    y0 = y =  [self getYAt:index];
    
    for(NSInteger i = 1; i < (NSInteger)line->used; i++) {
        index =  line->array[i];
        x1 = [self getXAt:index];
        y1 = [self getYAt:index];
        // Ar += (x1-x)*(y1+y);
        Ar += (y1 - y) * (x1 + x) - (x1 - x) * (y1 + y);
        x = x1;
        y = y1;
    }
    
    //Ar += (x0-x)*(y0+y);
    Ar += (y0 - y) * (x0 + x) - (x0 - x) * (y0 + y);
    // if not closed curve, return 0;
    if ((x0 - x) * (x0 - x) + (y0 - y) * (y0 - y) > 20.0 * pow([self getDX], 2.0) + pow([self getDY], 2.0) ) {
        Ar = 0.0;
//        NSLog(@"# open curve!\n");
    }
    //else   Ar /= -2;
    else {
        Ar /= 4.0;
    }
    // result is \int ydex/2 alone the implicit direction.
    return Ar;
}

-(double) edgeWeight:(LineStrip*)line R:(double)R {
    NSUInteger count = 0,index;
    double x,y;
    for(NSUInteger i = 0; i < (NSUInteger)line->used ; i++) {
        index = line->array[i];
        x = [self getXAt:index];
        y = [self getYAt:index];
        if (fabs(x) > R || fabs(y) > R) {
            count ++;
        }
    }
    return (double)count / line->used;
}

-(BOOL) printEdgeWeightContour:(NSString*)fname {
    NSArray *dirPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([dirPaths count] > 0) ? [dirPaths objectAtIndex:0] : nil;
    NSURL *filenameUrl = [NSURL URLWithString:[NSString stringWithFormat:@"%@/Export/%@.contour", basePath, fname]];
    
    NSUInteger index;
    LineStrip* pStrip;
    LineStripList* pStripList;
    NSMutableString *textfilestring = [[NSMutableString alloc] init];
    for(NSUInteger i = 0; i < [self getNoIsoCurves]; i++) {
        pStripList = &stripLists.array[i];
        for(NSUInteger j = 0; j < (NSUInteger)pStripList->used; j++) {
            pStrip = &pStripList->array[j];
            for(NSUInteger k = 0; k < (NSUInteger)pStrip->used; k++) {
                index = pStrip->array[k];
                [textfilestring appendFormat:@"%f\t%f\n", [self getXAt:index], [self getYAt:index]];
            }
            [textfilestring appendString:@"\n"];
        }
    }
    
    NSError *error;
    BOOL OK = [textfilestring writeToURL:filenameUrl atomically:YES encoding:NSUTF16StringEncoding error:&error];
    
    return OK;
}

// returns true if node is touching boundary
-(BOOL) isNodeOnBoundary:(NSUInteger)index {
    BOOL e1 = NO;
    double x = [self getXAt:index];
    double y = [self getYAt:index];
    double *limits = [self getLimits];
    if(x == limits[0] || x == limits[1] || y == limits[2] || y == limits[3]) {
        e1 = YES;
    }
    else if ( fabs(x - limits[0]) < 1E-6 || fabs(x - limits[1]) < 1E-6 || fabs(y - limits[2]) < 1E-6 || fabs(y - limits[3]) < 1E-6) {
        e1 = YES;
    }
    return e1;
}

@end
