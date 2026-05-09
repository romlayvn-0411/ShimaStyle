#import "DINNotificationView.h"

@implementation DINNotificationView

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                      appName:(NSString *)appName
                         icon:(UIImage *)icon
                        style:(DINNotificationStyle)style {
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
    }
    return self;
}

#pragma mark - Standard: [Icon 40] Title + Message

- (void)buildStandardWithTitle:(NSString *)title
                       message:(NSString *)message
                       appName:(NSString *)appName
                          icon:(UIImage *)icon {
    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.contentMode = UIViewContentModeScaleAspectFill;
    _iconImageView.layer.cornerRadius = 10;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.image = icon;
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *displayTitle = (title.length > 0) ? title : appName;
    _titleLabel.text = displayTitle ?: @"Notification";

    _messageLabel = [[UILabel alloc] init];
    _messageLabel.font = [UIFont systemFontOfSize:13];
    _messageLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    _messageLabel.numberOfLines = 1;
    _messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    if (message.length > 0) {
        _messageLabel.text = message;
    } else {
        _messageLabel.hidden = YES;
    }

    [self addSubview:_iconImageView];
    [self addSubview:_titleLabel];
    [self addSubview:_messageLabel];

    // AirDrop-style layout: icon centered, title bottom near icon centerY, message below
    [NSLayoutConstraint activateConstraints:@[
        // Icon: 40x40, vertically centered
        [_iconImageView.widthAnchor constraintEqualToConstant:40],
        [_iconImageView.heightAnchor constraintEqualToConstant:40],
        [_iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_iconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        // Title: leading to icon
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:10],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],

        [_messageLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_messageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
    ]];

    // Fix layout issue when message is empty
    if (message.length > 0) {
        [NSLayoutConstraint activateConstraints:@[
            [_messageLabel.bottomAnchor constraintEqualToAnchor:_iconImageView.bottomAnchor],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:_messageLabel.topAnchor constant:0],
        ]];
    } else {
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
    _iconImageView.layer.cornerRadius = 8;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.image = icon;
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    NSString *displayTitle = (title.length > 0) ? title : appName;
    _titleLabel.text = displayTitle ?: @"Notification";

    UIStackView *hStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[_iconImageView, _titleLabel]];
    hStack.axis = UILayoutConstraintAxisHorizontal;
    hStack.spacing = 10;
    hStack.alignment = UIStackViewAlignmentCenter;
    hStack.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:hStack];
    [NSLayoutConstraint activateConstraints:@[
        [_iconImageView.widthAnchor constraintEqualToConstant:32],
        [_iconImageView.heightAnchor constraintEqualToConstant:32],
        [hStack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [hStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [hStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [hStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

#pragma mark - Minimal: Large centered icon + app name

- (void)buildMinimalWithAppName:(NSString *)appName
                           icon:(UIImage *)icon {
    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.contentMode = UIViewContentModeScaleAspectFill;
    _iconImageView.layer.cornerRadius = 14;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.image = icon;
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 1;
    _titleLabel.text = appName ?: @"App";
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:_iconImageView];
    [self addSubview:_titleLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_iconImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_iconImageView.widthAnchor constraintEqualToConstant:56],
        [_iconImageView.heightAnchor constraintEqualToConstant:56],

        [_titleLabel.topAnchor constraintEqualToAnchor:_iconImageView.bottomAnchor constant:4],
        [_titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
        [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

@end
