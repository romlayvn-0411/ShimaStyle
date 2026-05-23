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

    // Existing preferences
    _enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
    _notificationEnabled = YES;
    _customBackgroundEnabled = prefs[@"customBackgroundEnabled"] ? [prefs[@"customBackgroundEnabled"] boolValue] : NO;

    NSString *bgPath = prefs[@"customBackgroundImagePath"];
    _customBackgroundImagePath = (bgPath.length > 0) ? bgPath : nil;

    _backgroundOpacity = prefs[@"backgroundOpacity"] ? [prefs[@"backgroundOpacity"] floatValue] : 1.0;
    _blurOpacity = prefs[@"blurOpacity"] ? [prefs[@"blurOpacity"] floatValue] : 1.0;
    _dismissDuration = prefs[@"dismissDuration"] ? [prefs[@"dismissDuration"] doubleValue] : 5.0;
    _notificationYOffset = prefs[@"notificationYOffset"] ? [prefs[@"notificationYOffset"] floatValue] : 0.0;
    _animationDuration = prefs[@"animationDuration"] ? [prefs[@"animationDuration"] doubleValue] : 0.45;
    _notificationStyle = prefs[@"notificationStyle"] ? [prefs[@"notificationStyle"] integerValue] : 0;
    _textColorStyle = prefs[@"textColorStyle"] ? [prefs[@"textColorStyle"] integerValue] : 0;

    // Advanced Colors
    _colorPickerBgColor = prefs[@"colorPickerBgColor"] ?: @"#000000";
    _colorPickerTitleColor = prefs[@"colorPickerTitleColor"] ?: @"#FFFFFF";
    _colorPickerMessageColor = prefs[@"colorPickerMessageColor"] ?: @"#CCCCCC";
    _borderColor = prefs[@"borderColor"] ?: @"#333333";
    _gradientEnabled = prefs[@"gradientEnabled"] ? [prefs[@"gradientEnabled"] boolValue] : NO;
    _gradientDirection = prefs[@"gradientDirection"] ? [prefs[@"gradientDirection"] integerValue] : 0;
    _selectedPreset = prefs[@"selectedPreset"] ?: @"dark";

    // Animation Types
    _animationType = prefs[@"animationType"] ? [prefs[@"animationType"] integerValue] : 0;
    _entranceAnimation = prefs[@"entranceAnimation"] ? [prefs[@"entranceAnimation"] integerValue] : 0;
    _exitAnimation = prefs[@"exitAnimation"] ? [prefs[@"exitAnimation"] integerValue] : 0;

    // Size & Layout
    _iconSize = prefs[@"iconSize"] ? [prefs[@"iconSize"] integerValue] : 1;
    _cornerRadiusValue = prefs[@"cornerRadiusValue"] ? [prefs[@"cornerRadiusValue"] floatValue] : 20.0;
    _maxNotificationWidth = prefs[@"maxNotificationWidth"] ? [prefs[@"maxNotificationWidth"] floatValue] : 300.0;
    _maxNotificationHeight = prefs[@"maxNotificationHeight"] ? [prefs[@"maxNotificationHeight"] floatValue] : 120.0;
    _safeAreaAdjustment = prefs[@"safeAreaAdjustment"] ? [prefs[@"safeAreaAdjustment"] integerValue] : 0;

    // App Filtering
    _filteringMode = prefs[@"filteringMode"] ? [prefs[@"filteringMode"] integerValue] : 0;
    _whitelistedApps = prefs[@"whitelistedApps"] ?: @[];
    _blacklistedApps = prefs[@"blacklistedApps"] ?: @[];

    // Sound & Haptic
    _hapticEnabled = prefs[@"hapticEnabled"] ? [prefs[@"hapticEnabled"] boolValue] : YES;
    _hapticType = prefs[@"hapticType"] ? [prefs[@"hapticType"] integerValue] : 1;
    _soundEnabled = prefs[@"soundEnabled"] ? [prefs[@"soundEnabled"] boolValue] : NO;
    _soundType = prefs[@"soundType"] ? [prefs[@"soundType"] integerValue] : 0;

    // Debug & Analytics
    _debugEnabled = prefs[@"debugEnabled"] ? [prefs[@"debugEnabled"] boolValue] : NO;
    _showNotificationQueue = prefs[@"showNotificationQueue"] ? [prefs[@"showNotificationQueue"] boolValue] : NO;
    _showPerformanceMetrics = prefs[@"showPerformanceMetrics"] ? [prefs[@"showPerformanceMetrics"] boolValue] : NO;
}

@end
