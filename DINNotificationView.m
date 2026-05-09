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
    _iconImageView.layer.cornerRadius = 10;
    _iconImageView.layer.cornerCurve = kCACornerCurveContinuous;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.image = icon;
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    NSString *displayTitle = (title.length > 0) ? title : appName;
    _titleLabel.text = displayTitle ?: @"Notification";

    _messageLabel = [[UILabel alloc] init];
    _messageLabel.font = [UIFont systemFontOfSize:13];
    _messageLabel.textColor = [UIColor secondaryLabelColor];
    _messageLabel.numberOfLines = 1;
    _messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    if (message.length > 0) {
        _messageLabel.text = message;
    } else {
        _messageLabel.hidden = YES;
    }

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _messageLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 1;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:_iconImageView];
    [self addSubview:textStack];

    // AirDrop-style layout: icon centered, title bottom near icon centerY, message below
    [NSLayoutConstraint activateConstraints:@[
        // Icon: 40x40, vertically centered
        [_iconImageView.widthAnchor constraintEqualToConstant:40],
        [_iconImageView.heightAnchor constraintEqualToConstant:40],
        [_iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_iconImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_iconImageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        // Text Stack: vertically centered alongside icon
        [textStack.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:10],
        [textStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [textStack.centerYAnchor constraintEqualToAnchor:_iconImageView.centerYAnchor],
    ]];
}

#pragma mark - Compact: [Icon 32] Title only

- (void)buildCompactWithTitle:(NSString *)title
                      appName:(NSString *)appName
                         icon:(UIImage *)icon {
    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.contentMode = UIViewContentModeScaleAspectFill;
    _iconImageView.layer.cornerRadius = 6;
    _iconImageView.layer.cornerCurve = kCACornerCurveContinuous;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.image = icon;
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
    hStack.spacing = 8;
    hStack.alignment = UIStackViewAlignmentCenter;
    hStack.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:hStack];
    [NSLayoutConstraint activateConstraints:@[
        [_iconImageView.widthAnchor constraintEqualToConstant:28],
        [_iconImageView.heightAnchor constraintEqualToConstant:28],
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
    _iconImageView.layer.cornerRadius = 10;
    _iconImageView.layer.cornerCurve = kCACornerCurveContinuous;
    _iconImageView.clipsToBounds = YES;
    _iconImageView.image = icon;
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
    
    if (_messageLabel) {
        if (message.length > 0) {
            _messageLabel.text = message;
            _messageLabel.hidden = NO;
        } else {
            _messageLabel.hidden = YES;
        }
    }
    
    if (icon && _iconImageView) {
        _iconImageView.image = icon;
    }
}

@end
