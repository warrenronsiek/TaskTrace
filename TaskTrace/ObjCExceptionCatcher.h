#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TTObjCExceptionCatcher : NSObject

/// Executes a block and catches any ObjC NSException, converting it to an NSError.
/// Returns YES on success, NO if an exception was caught (error is set).
+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block
           error:(NSError * _Nullable __autoreleasing * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
