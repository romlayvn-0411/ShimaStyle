#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, DINNotificationStyle) {
    DINNotificationStyleStandard = 0, // Icon + Title + Message (like AirDrop)
    DINNotificationStyleCompact  = 1, // Small icon + Title only
    DINNotificationStyleMinimal  = 2, // Large centered icon + app name
};

@interface DINNotificationView : UIView
@property (nonatomic, strong, readonly) UIImageView *iconImageView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *messageLabel;
@property (nonatomic, strong, readonly) UIView *messageContainer;

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                      appName:(NSString *)appName
                         icon:(UIImage *)icon
                        style:(DINNotificationStyle)style
               textColorStyle:(NSInteger)textColorStyle;
- (void)startMarquee;
@end
