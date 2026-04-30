#import "ObjCExceptionCatcher.h"

@implementation TTObjCExceptionCatcher

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block
           error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            if (exception.reason) {
                userInfo[NSLocalizedDescriptionKey] = exception.reason;
            }
            if (exception.userInfo) {
                userInfo[NSLocalizedFailureReasonErrorKey] =
                    [exception.userInfo description];
            }
            *error = [NSError errorWithDomain:@"TaskTrace.ObjCException"
                                         code:-1
                                     userInfo:userInfo];
        }
        return NO;
    }
}

@end
