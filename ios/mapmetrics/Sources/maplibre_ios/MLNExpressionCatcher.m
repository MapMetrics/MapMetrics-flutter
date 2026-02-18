#import "MLNExpressionCatcher.h"
@import MapLibre;

@implementation MLNExpressionCatcher

+ (nullable NSExpression *)tryMglJSONObject:(id)jsonObject {
    @try {
        return [NSExpression expressionWithMLNJSONObject:jsonObject];
    } @catch (NSException *exception) {
        NSLog(@"iOS: ⚠️ MLNExpressionCatcher caught ObjC exception: %@ — %@",
              exception.name, exception.reason);
        return nil;
    }
}

+ (BOOL)performSafely:(void (NS_NOESCAPE ^)(void))block {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"iOS: ⚠️ MLNExpressionCatcher caught ObjC exception in block: %@ — %@",
              exception.name, exception.reason);
        return NO;
    }
}

@end
