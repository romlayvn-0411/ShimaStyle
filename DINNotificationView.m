#import "DINNotificationView.h"

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
                [self buildCompactWithTitle:title appName:appName icon:icon];
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

    // Cấu hình vị trí (Constraints) chung cho cả 2 trường hợp
    [NSLayoutConstraint activateConstraints:@[
        // 1. Icon: Kích thước 44x44, đưa ra sát viền hơn (cách 8pt thay vì 16pt)
        [_iconImageView.widthAnchor constraintEqualToConstant:44],
        [_iconImageView.heightAnchor constraintEqualToConstant:44],
        [_iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_iconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        // 2. Kéo Tiêu đề và Nội dung lại gần Icon hơn (cách 8pt thay vì 12pt)
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:8],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        
        [_messageContainer.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:8],
        [_messageContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],

        // 3. Nội dung Label bên trong Container
        [_messageLabel.leadingAnchor constraintEqualToAnchor:_messageContainer.leadingAnchor],
        [_messageLabel.topAnchor constraintEqualToAnchor:_messageContainer.topAnchor],
        [_messageLabel.bottomAnchor constraintEqualToAnchor:_messageContainer.bottomAnchor],
    ]];

    if (message.length > 0) {
        _messageLabel.text = message;
        // Thu ngắn khoảng cách giữa Tiêu đề và Nội dung: Cho 2 thành phần ôm sát vào đường giữa (CenterY) của Icon
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.bottomAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor constant:1],
            [_messageContainer.topAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor constant:-1],
            [_messageContainer.heightAnchor constraintEqualToConstant:18]
        ]];
    } else {
        _messageContainer.hidden = YES;
        // Nếu KHÔNG có Nội dung: Tiêu đề tự động căn giữa theo Icon
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.centerYAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor],
        ]];
    }
}

#pragma mark - Compact: [Icon 32] Title only

- (void)buildCompactWithTitle:(NSString *)title
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

    UIStackView *hStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[_iconImageView, _titleLabel]];
    hStack.axis = UILayoutConstraintAxisHorizontal;
    hStack.spacing = 6; // Đưa chữ gần icon hơn
    hStack.alignment = UIStackViewAlignmentCenter;
    hStack.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:hStack];
    [NSLayoutConstraint activateConstraints:@[
        [_iconImageView.widthAnchor constraintEqualToConstant:28],
        [_iconImageView.heightAnchor constraintEqualToConstant:28],
        [hStack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [hStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8], // Đưa ra sát viền
        [hStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [hStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

#pragma mark - Minimal: Large centered icon + app name

- (void)buildMinimalWithAppName:(NSString *)appName
                           icon:(UIImage *)icon {
    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.contentMode = UIViewContentModeScaleAspectFill;
    _iconImageView.layer.cornerRadius = 22; // Bo tròn hoàn hảo (size 44)
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
        [_iconImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_iconImageView.widthAnchor constraintEqualToConstant:44],
        [_iconImageView.heightAnchor constraintEqualToConstant:44],

        [_titleLabel.topAnchor constraintEqualToAnchor:_iconImageView.bottomAnchor constant:4],
        [_titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.widthAnchor constraintGreaterThanOrEqualToConstant:44],
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
        
        [UIView animateWithDuration:2.5 delay:0.5 options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.messageLabel.transform = CGAffineTransformMakeTranslation(-distance, 0);
        } completion:nil];
    }
}

@end
