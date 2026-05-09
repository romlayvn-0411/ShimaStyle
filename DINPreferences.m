#import "DINPreferences.h"

static NSString *const kPrefsDomain = @"com.34306.shimastyle";

@implementation DINPreferences

+ (instancetype)sharedInstance {
    static DINPreferences *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DINPreferences alloc] init];
        [instance reloadPreferences];
    });
    return instance;
}

- (void)reloadPreferences {
    // Bắt buộc đồng bộ (Force sync) với cfprefsd để không bị lấy dữ liệu cũ
    CFPreferencesAppSynchronize((CFStringRef)kPrefsDomain);
    
    NSDictionary *prefs = nil;
    CFArrayRef keyList = CFPreferencesCopyKeyList((CFStringRef)kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keyList) {
        prefs = (NSDictionary *)CFBridgingRelease(CFPreferencesCopyMultiple(keyList, (CFStringRef)kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        CFRelease(keyList);
    }
    if (!prefs) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.34306.shimastyle.plist"];
    }

    _enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
    _notificationEnabled = prefs[@"notificationEnabled"] ? [prefs[@"notificationEnabled"] boolValue] : YES;
    _customBackgroundEnabled = prefs[@"customBackgroundEnabled"] ? [prefs[@"customBackgroundEnabled"] boolValue] : NO;
    
    NSString *bgPath = prefs[@"customBackgroundImagePath"];
    _customBackgroundImagePath = (bgPath.length > 0) ? bgPath : nil;
    
    _backgroundOpacity = prefs[@"backgroundOpacity"] ? [prefs[@"backgroundOpacity"] floatValue] : 1.0;
    _blurOpacity = prefs[@"blurOpacity"] ? [prefs[@"blurOpacity"] floatValue] : 1.0;
    _dismissDuration = prefs[@"dismissDuration"] ? [prefs[@"dismissDuration"] doubleValue] : 5.0;
    _notificationYOffset = prefs[@"notificationYOffset"] ? [prefs[@"notificationYOffset"] floatValue] : 0.0;
    _notificationStyle = prefs[@"notificationStyle"] ? [prefs[@"notificationStyle"] integerValue] : 0;
}

@end
