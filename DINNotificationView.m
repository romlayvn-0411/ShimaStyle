#import "DINNotificationView.h"
#import <AudioToolbox/AudioToolbox.h>

@implementation DINNotificationView

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                      appName:(NSString *)appName
                         icon:(UIImage *)icon
                        style:(DINNotificationStyle)style
               textColorStyle:(NSInteger)textColorStyle {
    if (self = [super initWithFrame:CGRectZero]) {
        switch (style) {
            case DINNotificationStyleCompact:
                [self buildCompactWithTitle:title message:message appName:appName icon:icon];
                break;
            case DINNotificationStyleMinimal:
                [self buildMinimalWithAppName:appName icon:icon];
                break;
            default:
                [self buildStandardWithTitle:title message:message appName:appName icon:icon];
                break;
        }
        [self applyTextColorStyle:textColorStyle];
    }
    return self;
}

- (void)applyTextColorStyle:(NSInteger)style {
    UIColor *primaryColor;
    UIColor *secondaryColor;
    
    if (style == 1) { // Light (White)
        primaryColor = [UIColor whiteColor];
        secondaryColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    } else if (style == 2) { // Dark (Black)
        primaryColor = [UIColor blackColor];
        secondaryColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    } else { // Auto
        primaryColor = [UIColor labelColor];
        secondaryColor = [UIColor secondaryLabelColor];
        secondaryColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
                ? [UIColor colorWithWhite:0.85 alpha:1.0] // Trắng xám rõ nét (Dark mode)
                : [UIColor colorWithWhite:0.35 alpha:1.0]; // Đen xám đậm nét (Light mode)
        }];
    }
    
    if (_titleLabel) _titleLabel.textColor = primaryColor;
    if (_messageLabel) _messageLabel.textColor = secondaryColor;
}

#pragma mark - Standard: [Icon 40] Title + Message

- (void)buildStandardWithTitle:(NSString *)title
                       message:(NSString *)message
                       appName:(NSString *)appName
                          icon:(UIImage *)icon {
    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.contentMode = UIViewContentModeScaleAspectFill;
    _iconImageView.layer.cornerRadius = 22; // Bo tròn hoàn hảo (Circular) cho size 44
    _iconImageView.layer.cornerCurve = kCACornerCurveContinuous;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.image = icon;
    _iconImageView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale; // Viền nét mảnh 1 pixel vật lý
    _iconImageView.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.2].CGColor;
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    NSString *displayTitle = (title.length > 0) ? title : appName;
    _titleLabel.text = displayTitle ?: @"Notification";
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _messageContainer = [[UIView alloc] init];
    _messageContainer.clipsToBounds = YES;
    _messageContainer.translatesAutoresizingMaskIntoConstraints = NO;

    _messageLabel = [[UILabel alloc] init];
    _messageLabel.font = [UIFont systemFontOfSize:14]; // Tăng cỡ chữ nhẹ để cân đối với khung
    _messageLabel.textColor = [UIColor secondaryLabelColor];
    _messageLabel.numberOfLines = 1;
    _messageLabel.lineBreakMode = NSLineBreakByClipping; // Không dùng dấu "..." để phục vụ chạy chữ (Marquee)
    _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [_messageContainer addSubview:_messageLabel];
    [self addSubview:_iconImageView];
    [self addSubview:_titleLabel];
    [self addSubview:_messageContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_iconImageView.widthAnchor constraintEqualToConstant:44],
        [_iconImageView.heightAnchor constraintEqualToConstant:44],
        [_iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_iconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:8],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        
        [_messageContainer.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:8],
        [_messageContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],

        [_messageLabel.leadingAnchor constraintEqualToAnchor:_messageContainer.leadingAnchor],
        [_messageLabel.topAnchor constraintEqualToAnchor:_messageContainer.topAnchor],
        [_messageLabel.bottomAnchor constraintEqualToAnchor:_messageContainer.bottomAnchor],
    ]];

    if (message.length > 0) {
        _messageLabel.text = message;
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.bottomAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor constant:1],
            [_messageContainer.topAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor constant:-1],
            [_messageContainer.heightAnchor constraintEqualToConstant:18]
        ]];
    } else {
        _messageContainer.hidden = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.centerYAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor],
        ]];
    }
}

#pragma mark - Compact: [Icon 32] Title only

- (void)buildCompactWithTitle:(NSString *)title
                      message:(NSString *)message
                      appName:(NSString *)appName
                         icon:(UIImage *)icon {
    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.contentMode = UIViewContentModeScaleAspectFill;
    _iconImageView.layer.cornerRadius = 14; // Bo tròn hoàn hảo (size 28)
    _iconImageView.layer.cornerCurve = kCACornerCurveContinuous;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.image = icon;
    _iconImageView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _iconImageView.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.2].CGColor;
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    NSString *displayTitle = (title.length > 0) ? title : appName;
    _titleLabel.text = displayTitle ?: @"Notification";
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _messageContainer = [[UIView alloc] init];
    _messageContainer.clipsToBounds = YES;
    _messageContainer.translatesAutoresizingMaskIntoConstraints = NO;

    _messageLabel = [[UILabel alloc] init];
    _messageLabel.font = [UIFont systemFontOfSize:12]; // Chữ nhỏ hơn tiêu chuẩn
    _messageLabel.textColor = [UIColor secondaryLabelColor];
    _messageLabel.numberOfLines = 1;
    _messageLabel.lineBreakMode = NSLineBreakByClipping;
    _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [_messageContainer addSubview:_messageLabel];
    [self addSubview:_iconImageView];
    [self addSubview:_titleLabel];
    [self addSubview:_messageContainer];

    [NSLayoutConstraint activateConstraints:@[
        [_iconImageView.widthAnchor constraintEqualToConstant:28],
        [_iconImageView.heightAnchor constraintEqualToConstant:28],
        [_iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_iconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:8],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        
        [_messageContainer.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:8],
        [_messageContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],

        [_messageLabel.leadingAnchor constraintEqualToAnchor:_messageContainer.leadingAnchor],
        [_messageLabel.topAnchor constraintEqualToAnchor:_messageContainer.topAnchor],
        [_messageLabel.bottomAnchor constraintEqualToAnchor:_messageContainer.bottomAnchor],
    ]];

    if (message.length > 0) {
        _messageLabel.text = message;
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.bottomAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor constant:0],
            [_messageContainer.topAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor constant:0],
            [_messageContainer.heightAnchor constraintEqualToConstant:15]
        ]];
    } else {
        _messageContainer.hidden = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.centerYAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor],
        ]];
    }
}

#pragma mark - Minimal: Large centered icon + app name

- (void)buildMinimalWithAppName:(NSString *)appName
                           icon:(UIImage *)icon {
    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.contentMode = UIViewContentModeScaleAspectFill;
    _iconImageView.layer.cornerRadius = 16; // Bo tròn hoàn hảo (size 32)
    _iconImageView.layer.cornerCurve = kCACornerCurveContinuous;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.image = icon;
    _iconImageView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _iconImageView.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.2].CGColor;
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _titleLabel.textColor = [UIColor secondaryLabelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 1;
    _titleLabel.text = appName ?: @"App";
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:_iconImageView];
    [self addSubview:_titleLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_iconImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconImageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:8], // Đẩy icon xuống để cân đối theo chiều dọc
        [_iconImageView.widthAnchor constraintEqualToConstant:32],
        [_iconImageView.heightAnchor constraintEqualToConstant:32],

        [_titleLabel.topAnchor constraintEqualToAnchor:_iconImageView.bottomAnchor constant:2], // Thu hẹp khoảng cách giữa icon và tiêu đề
        [_titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-4], // Tránh bị ép giãn chữ
        [self.widthAnchor constraintGreaterThanOrEqualToConstant:32],
    ]];
}

#pragma mark - Stacking Updates

- (void)updateTitle:(NSString *)title message:(NSString *)message appName:(NSString *)appName icon:(UIImage *)icon count:(NSInteger)count {
    NSString *displayTitle = (title.length > 0) ? title : appName;
    if (count > 1) {
        displayTitle = [NSString stringWithFormat:@"(%ld) %@", (long)count, displayTitle ?: @""];
    }
    
    if (_titleLabel) _titleLabel.text = displayTitle ?: @"Notification";
    
    if (_messageContainer) {
        if (message.length > 0) {
            _messageLabel.text = message;
            _messageContainer.hidden = NO;
            _messageLabel.transform = CGAffineTransformIdentity; // Reset vị trí chạy chữ
        } else {
            _messageContainer.hidden = YES;
        }
    }
    
    if (icon && _iconImageView) {
        _iconImageView.image = icon;
    }
}

#pragma mark - Marquee Animation

- (void)startMarquee {
    if (!_messageLabel || !_messageContainer || _messageContainer.hidden) return;
    
    [self.messageLabel.layer removeAllAnimations];
    self.messageLabel.transform = CGAffineTransformIdentity;
    
    CGFloat textWidth = self.messageLabel.intrinsicContentSize.width;
    CGFloat containerWidth = self.messageContainer.bounds.size.width;
    
    if (textWidth > containerWidth && containerWidth > 0) {
        CGFloat distance = textWidth - containerWidth + 12; // Chạy lố ra 12pt để có khoảng thở
        
        // Tính toán thời gian dựa trên độ dài văn bản để tốc độ cuộn luôn êm ái và dễ đọc (vận tốc ~35pt/giây)
        NSTimeInterval scrollDuration = MAX(2.5, distance / 35.0);
        
        [UIView animateWithDuration:scrollDuration delay:0.5 options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.messageLabel.transform = CGAffineTransformMakeTranslation(-distance, 0);
        } completion:nil];
    }
}

#pragma mark - Animation Engine

+ (CAAnimation *)createAnimationForType:(NSInteger)animationType duration:(NSTimeInterval)duration {
    switch (animationType) {
        case 0: // Slide
            {
                CABasicAnimation *slideAnim = [CABasicAnimation animationWithKeyPath:@"position.y"];
                slideAnim.fromValue = @(-100);
                slideAnim.toValue = @(0);
                slideAnim.duration = duration;
                slideAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                return slideAnim;
            }
        case 1: // Fade
            {
                CABasicAnimation *fadeAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
                fadeAnim.fromValue = @(0);
                fadeAnim.toValue = @(1);
                fadeAnim.duration = duration;
                fadeAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
                return fadeAnim;
            }
        case 2: // Pop (overshoot effect)
            {
                CAKeyframeAnimation *popAnim = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
                popAnim.values = @[@(0), @(1.2), @(1.0)];
                popAnim.keyTimes = @[@(0), @(0.6), @(1)];
                popAnim.duration = duration;
                popAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                return popAnim;
            }
        case 3: // Bounce (spring-like)
            {
                CABasicAnimation *bounceAnim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
                bounceAnim.fromValue = @(0.5);
                bounceAnim.toValue = @(1.0);
                bounceAnim.duration = duration;
                CAMediaTimingFunction *timing = [CAMediaTimingFunction functionWithControlPoints:0.34 :1.56 :0.64 :1];
                bounceAnim.timingFunction = timing;
                return bounceAnim;
            }
        case 4: // Scale
            {
                CABasicAnimation *scaleAnim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
                scaleAnim.fromValue = @(0.5);
                scaleAnim.toValue = @(1.0);
                scaleAnim.duration = duration;
                scaleAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                return scaleAnim;
            }
        default:
            return nil;
    }
}

#pragma mark - Color Helper

+ (UIColor *)colorFromHex:(NSString *)hexString {
    if (!hexString || hexString.length < 7) return [UIColor blackColor];

    NSString *hex = [hexString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"#"]];
    if (hex.length != 6) return [UIColor blackColor];

    unsigned int rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    [scanner scanHexInt:&rgbValue];

    return [UIColor colorWithRed:((rgbValue >> 16) & 0xFF) / 255.0
                          green:((rgbValue >> 8) & 0xFF) / 255.0
                           blue:(rgbValue & 0xFF) / 255.0
                          alpha:1.0];
}

#pragma mark - Gradient Background

- (CAGradientLayer *)createGradientLayerWithStartColor:(UIColor *)startColor
                                              endColor:(UIColor *)endColor
                                             direction:(NSInteger)direction
                                                 frame:(CGRect)frame {
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = frame;
    gradientLayer.colors = @[(id)startColor.CGColor, (id)endColor.CGColor];

    switch (direction) {
        case 0: // Left to Right
            gradientLayer.startPoint = CGPointMake(0.0, 0.5);
            gradientLayer.endPoint = CGPointMake(1.0, 0.5);
            break;
        case 1: // Top to Bottom
            gradientLayer.startPoint = CGPointMake(0.5, 0.0);
            gradientLayer.endPoint = CGPointMake(0.5, 1.0);
            break;
        case 2: // Diagonal
            gradientLayer.startPoint = CGPointMake(0.0, 0.0);
            gradientLayer.endPoint = CGPointMake(1.0, 1.0);
            break;
        default:
            break;
    }

    return gradientLayer;
}

#pragma mark - Haptic Feedback

- (void)playHapticFeedbackWithType:(NSInteger)hapticType {
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *hapticGenerator;

        switch (hapticType) {
            case 0: // Tap (Light)
                hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                break;
            case 1: // Light Impact
                hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                break;
            case 2: // Medium Impact
                hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
                break;
            case 3: // Heavy Impact
                hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
                break;
            default:
                return;
        }

        [hapticGenerator impactOccurred];
    }
}

#pragma mark - Sound Effects

- (void)playSoundEffectWithType:(NSInteger)soundType {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);

    if (soundType == 0) {
        AudioServicesPlaySystemSound(1000); // Standard notification
    } else if (soundType == 1) {
        AudioServicesPlaySystemSound(1001); // Alert sound
    } else if (soundType == 2) {
        AudioServicesPlaySystemSound(1002); // Success sound
    }
}

@end

