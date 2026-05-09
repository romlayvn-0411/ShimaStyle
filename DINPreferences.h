#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DINPreferences : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL notificationEnabled;
@property (nonatomic, assign) BOOL customBackgroundEnabled;
@property (nonatomic, copy) NSString *customBackgroundColorHex;
@property (nonatomic, copy) NSString *customBackgroundImagePath;
@property (nonatomic, assign) CGFloat backgroundOpacity;
@property (nonatomic, assign) double dismissDuration;
@property (nonatomic, assign) CGFloat notificationYOffset;
@property (nonatomic, assign) NSInteger notificationStyle;

+ (instancetype)sharedInstance;
- (void)reloadPreferences;
- (UIColor *)customBackgroundColor;

@end
