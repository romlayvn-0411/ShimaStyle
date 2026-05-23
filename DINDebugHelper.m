#import "DINDebugHelper.h"
#import <Foundation/Foundation.h>
#import <sys/resource.h>

@implementation DINDebugHelper {
    NSDate *_lastNotificationTime;
    NSMutableArray *_notificationQueue;
}

+ (instancetype)sharedInstance {
    static DINDebugHelper *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DINDebugHelper alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _notificationQueue = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)logNotification:(NSString *)bundleID title:(NSString *)title {
    _lastNotificationTime = [NSDate date];

    NSDictionary *notifInfo = @{
        @"bundleID": bundleID ?: @"Unknown",
        @"title": title ?: @"No Title",
        @"timestamp": _lastNotificationTime
    };

    [_notificationQueue addObject:notifInfo];

    if (_notificationQueue.count > 50) {
        [_notificationQueue removeObjectAtIndex:0];
    }
}

- (NSString *)lastNotificationTime {
    if (!_lastNotificationTime) return @"No notification yet";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    return [formatter stringFromDate:_lastNotificationTime];
}

- (NSString *)queueLength {
    return [NSString stringWithFormat:@"%lu", (unsigned long)_notificationQueue.count];
}

- (NSString *)throttleStatus {
    return @"Active";
}

- (NSString *)memoryUsage {
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    long memoryMB = usage.ru_maxrss / 1024;
    return [NSString stringWithFormat:@"%ld MB", memoryMB];
}

- (NSString *)getDebugInfoString {
    return [NSString stringWithFormat:
        @"ShimaStyle Debug Info\n"
        @"Last Notification: %@\n"
        @"Queue Length: %@\n"
        @"Throttle Status: %@\n"
        @"Memory Usage: %@",
        self.lastNotificationTime,
        self.queueLength,
        self.throttleStatus,
        self.memoryUsage];
}

@end
