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
    _customBackgroundColorHex = prefs[@"customBackgroundColorHex"] ?: @"#1C1C1E";
    
    NSString *bgPath = prefs[@"customBackgroundImagePath"];
    _customBackgroundImagePath = (bgPath.length > 0) ? bgPath : nil;
    
    _backgroundOpacity = prefs[@"backgroundOpacity"] ? [prefs[@"backgroundOpacity"] floatValue] : 1.0;
    _dismissDuration = prefs[@"dismissDuration"] ? [prefs[@"dismissDuration"] doubleValue] : 5.0;
    _notificationYOffset = prefs[@"notificationYOffset"] ? [prefs[@"notificationYOffset"] floatValue] : 0.0;
    _notificationStyle = prefs[@"notificationStyle"] ? [prefs[@"notificationStyle"] integerValue] : 0;
}

- (UIColor *)customBackgroundColor {
    NSString *hex = _customBackgroundColorHex;
    if (!hex || [hex length] < 6) return [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:1.0];

    if ([hex hasPrefix:@"#"]) {
        hex = [hex substringFromIndex:1];
    }

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    [scanner scanHexInt:&value];

    if (hex.length == 8) { // Định dạng RRGGBBAA (từ libcolorpicker)
        return [UIColor colorWithRed:((value >> 24) & 0xFF) / 255.0
                               green:((value >> 16) & 0xFF) / 255.0
                                blue:((value >> 8) & 0xFF) / 255.0
                               alpha:((value & 0xFF) / 255.0) * _backgroundOpacity];
    } else { // Định dạng RRGGBB thông thường
        return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                               green:((value >> 8) & 0xFF) / 255.0
                                blue:(value & 0xFF) / 255.0
                               alpha:_backgroundOpacity];
    }
}

@end
