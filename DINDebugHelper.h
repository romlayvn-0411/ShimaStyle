#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

@interface DINDebugHelper : NSObject

@property (nonatomic, copy, readonly) NSString *lastNotificationTime;
@property (nonatomic, copy, readonly) NSString *queueLength;
@property (nonatomic, copy, readonly) NSString *throttleStatus;
@property (nonatomic, copy, readonly) NSString *memoryUsage;

+ (instancetype)sharedInstance;

- (void)logNotification:(NSString *)bundleID title:(NSString *)title;
- (NSString *)getDebugInfoString;

@end
