#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface DINPreferences : NSObject

// Existing properties
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL customBackgroundEnabled;
@property (nonatomic, copy) NSString *customBackgroundImagePath;
@property (nonatomic, assign) CGFloat backgroundOpacity;
@property (nonatomic, assign) CGFloat blurOpacity;
@property (nonatomic, assign) double dismissDuration;
@property (nonatomic, assign) CGFloat notificationYOffset;
@property (nonatomic, assign) double animationDuration;
@property (nonatomic, assign) NSInteger notificationStyle;
@property (nonatomic, assign) NSInteger textColorStyle;

// Advanced Colors
@property (nonatomic, copy) NSString *colorPickerBgColor;
@property (nonatomic, copy) NSString *colorPickerTitleColor;
@property (nonatomic, copy) NSString *colorPickerMessageColor;
@property (nonatomic, copy) NSString *borderColor;
@property (nonatomic, assign) BOOL gradientEnabled;
@property (nonatomic, assign) NSInteger gradientDirection;
@property (nonatomic, copy) NSString *selectedPreset;

// Animation Types
@property (nonatomic, assign) NSInteger animationType;
@property (nonatomic, assign) NSInteger entranceAnimation;
@property (nonatomic, assign) NSInteger exitAnimation;

// Size & Layout
@property (nonatomic, assign) NSInteger iconSize;
@property (nonatomic, assign) CGFloat cornerRadiusValue;
@property (nonatomic, assign) CGFloat maxNotificationWidth;
@property (nonatomic, assign) CGFloat maxNotificationHeight;
@property (nonatomic, assign) NSInteger safeAreaAdjustment;
@property (nonatomic, assign) CGFloat landscapeXOffset;
@property (nonatomic, assign) CGFloat landscapeYOffset;

// App Filtering
@property (nonatomic, assign) NSInteger filteringMode;
@property (nonatomic, copy) NSArray<NSString *> *whitelistedApps;
@property (nonatomic, copy) NSArray<NSString *> *blacklistedApps;

// Sound & Haptic
@property (nonatomic, assign) BOOL hapticEnabled;
@property (nonatomic, assign) NSInteger hapticType;
@property (nonatomic, assign) BOOL soundEnabled;
@property (nonatomic, assign) NSInteger soundType;

// Debug & Analytics
@property (nonatomic, assign) BOOL debugEnabled;
@property (nonatomic, assign) BOOL showNotificationQueue;
@property (nonatomic, assign) BOOL showPerformanceMetrics;

+ (instancetype)sharedInstance;
- (void)reloadPreferences;

@end
