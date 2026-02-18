#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Catches ObjC NSExceptions that Swift's do/catch cannot handle.
/// Used to safely call NSExpression(mglJSONObject:) which throws ObjC exceptions
/// for unsupported expressions like ["accumulated"].
@interface MLNExpressionCatcher : NSObject

/// Try to create an NSExpression from a MapLibre JSON object.
/// Returns nil if an ObjC exception is thrown (instead of crashing).
+ (nullable NSExpression *)tryMglJSONObject:(id)jsonObject;

/// Execute a block safely, catching any ObjC NSException.
/// Returns YES if the block executed without throwing, NO if an exception was caught.
+ (BOOL)performSafely:(void (NS_NOESCAPE ^)(void))block;

@end

NS_ASSUME_NONNULL_END
