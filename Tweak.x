#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import "DINNotificationView.h"
#import "DINPreferences.h"

@interface DINNotificationView (Stacking)
- (void)updateTitle:(NSString *)title message:(NSString *)message appName:(NSString *)appName icon:(UIImage *)icon count:(NSInteger)count;
@end

// ============================================================================
// MARK: - Private Class Interfaces
// ============================================================================

@interface NCNotificationContent : NSObject
- (NSString *)title;
- (NSString *)subtitle;
- (NSString *)message;
@end

@interface NCNotificationRequest : NSObject
- (NSString *)sectionIdentifier;
- (NSString *)notificationIdentifier;
- (NCNotificationContent *)content;
@end

@interface NCNotificationDispatcher : NSObject
- (void)postNotificationWithRequest:(NCNotificationRequest *)request;
@end

@interface SBApplication : NSObject
- (NSString *)displayName;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
- (NSString *)localizedName;
- (NSURL *)bundleURL;
@end

@interface SBSystemApertureContainerView : UIView
@end

@interface SBNCAlertingController : NSObject
@end

@interface NCNotificationBannerDestination : NSObject
@end

@interface SBNotificationBannerDestination : NSObject
@end

@interface BNBannerSource : NSObject
@end

@interface SBNCSystemApertureNotificationDestination : NSObject
@end

@interface SBSystemApertureNotificationDestination : NSObject
@end

@interface NCNotificationSystemApertureDestination : NSObject
@end

// ============================================================================
// MARK: - Rate Limiting
// ============================================================================

static NSDate *sLastNotificationTime = nil;
static NSTimeInterval const kMinNotificationInterval = 0.2; // Giảm thời gian chặn để xử lý thông báo tức thì

static BOOL dinShouldThrottle(void) {
    if (!sLastNotificationTime) return NO;
    return [[NSDate date] timeIntervalSinceDate:sLastNotificationTime] < kMinNotificationInterval;
}

// ============================================================================
// MARK: - Helper: Lock Screen & CoverSheet State
// ============================================================================

static BOOL dinIsDeviceLockedOrInCoverSheet(void) {
    BOOL isLocked = NO;
    // Tối ưu hóa 1: Cache Class bằng dispatch_once để không tốn CPU tra cứu lại
    static Class s_SBLockScreenManagerClass = nil;
    static dispatch_once_t onceTokenLock;
    dispatch_once(&onceTokenLock, ^{ s_SBLockScreenManagerClass = objc_lookUpClass("SBLockScreenManager"); });
    
    if (s_SBLockScreenManagerClass) {
        id lockScreenManager = ((id (*)(Class, SEL))objc_msgSend)(s_SBLockScreenManagerClass, sel_registerName("sharedInstance"));
        if (lockScreenManager) {
            if ([lockScreenManager respondsToSelector:sel_registerName("isLockScreenVisible")] &&
                ((BOOL (*)(id, SEL))objc_msgSend)(lockScreenManager, sel_registerName("isLockScreenVisible"))) {
                isLocked = YES;
            } else if ([lockScreenManager respondsToSelector:sel_registerName("isUILocked")] &&
                       ((BOOL (*)(id, SEL))objc_msgSend)(lockScreenManager, sel_registerName("isUILocked"))) {
                isLocked = YES;
            } else if ([lockScreenManager respondsToSelector:sel_registerName("coverSheetViewController")]) {
                id csvc = ((id (*)(id, SEL))objc_msgSend)(lockScreenManager, sel_registerName("coverSheetViewController"));
                if (csvc) {
                    if ([csvc respondsToSelector:sel_registerName("isPresented")] && ((BOOL (*)(id, SEL))objc_msgSend)(csvc, sel_registerName("isPresented"))) {
                        isLocked = YES;
                    } else if ([csvc respondsToSelector:sel_registerName("isPresenting")] && ((BOOL (*)(id, SEL))objc_msgSend)(csvc, sel_registerName("isPresenting"))) {
                        isLocked = YES;
                    }
                }
            }
        }
    }
    return isLocked;
}

// --- Helper: Lấy hướng xoay THỰC TẾ của ứng dụng đang mở ---
static UIInterfaceOrientation dinGetActiveOrientation(void) {
    id sb = [UIApplication sharedApplication];
    if ([sb respondsToSelector:sel_registerName("activeInterfaceOrientation")]) {
        return (UIInterfaceOrientation)((NSInteger (*)(id, SEL))objc_msgSend)(sb, sel_registerName("activeInterfaceOrientation"));
    }
    return UIInterfaceOrientationPortrait;
}

// ============================================================================
// MARK: - App Icon Helper
// ============================================================================

static UIImage *dinAppIcon(NSString *bundleIdentifier) {
    if (!bundleIdentifier) return nil;

    static NSCache *sAppIconCache = nil;
    static dispatch_once_t onceTokenIcon;
    dispatch_once(&onceTokenIcon, ^{ sAppIconCache = [[NSCache alloc] init]; });

    UIImage *cachedIcon = [sAppIconCache objectForKey:bundleIdentifier];
    if (cachedIcon) return cachedIcon;

    UIImage *foundIcon = nil;

    // Method 1: UIImage private API (most reliable)
    @try {
        SEL iconSel = sel_registerName("_applicationIconImageForBundleIdentifier:format:scale:");
        if ([UIImage respondsToSelector:iconSel]) {
            foundIcon = ((id (*)(Class, SEL, id, int, CGFloat))objc_msgSend)(
                [UIImage class], iconSel, bundleIdentifier, 2, UIScreen.mainScreen.scale);
        }
    } @catch (NSException *e) {}

    // Method 2: SBIconController → SBIconModel
    if (!foundIcon) {
        @try {
        Class iconControllerClass = objc_lookUpClass("SBIconController");
        if (iconControllerClass) {
            id iconController = ((id (*)(Class, SEL))objc_msgSend)(
                iconControllerClass, sel_registerName("sharedInstance"));
            if (iconController) {
                id model = ((id (*)(id, SEL))objc_msgSend)(
                    iconController, sel_registerName("model"));
                if (model) {
                    id icon = ((id (*)(id, SEL, id))objc_msgSend)(model,
                        sel_registerName("applicationIconForBundleIdentifier:"),
                        bundleIdentifier);
                    if (icon && [icon respondsToSelector:sel_registerName("getIconImage:")]) {
                            foundIcon = ((id (*)(id, SEL, int))objc_msgSend)(
                            icon, sel_registerName("getIconImage:"), 2);
                    }
                        else if (icon && [icon respondsToSelector:sel_registerName("generateIconImage:")]) {
                            foundIcon = ((id (*)(id, SEL, int))objc_msgSend)(
                            icon, sel_registerName("generateIconImage:"), 2);
                    }
                }
            }
        }
        } @catch (NSException *e) {}
    }

    // Method 3: Load from app bundle
    if (!foundIcon) {
        @try {
        LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:bundleIdentifier];
        if (proxy) {
            NSURL *bundleURL = [proxy bundleURL];
            if (bundleURL) {
                for (NSString *iconName in @[@"AppIcon60x60@2x.png", @"AppIcon60x60@3x.png",
                        @"AppIcon76x76@2x.png", @"Icon-60@2x.png", @"Icon-60@3x.png"]) {
                        UIImage *img = [UIImage imageWithContentsOfFile:
                        [[bundleURL path] stringByAppendingPathComponent:iconName]];
                        if (img) { foundIcon = img; break; }
                }
            }
        }
        } @catch (NSException *e) {}
    }

    if (foundIcon) [sAppIconCache setObject:foundIcon forKey:bundleIdentifier];
    return foundIcon;
}

// Generate a placeholder icon with app initial
static UIImage *dinPlaceholderIcon(NSString *appName) {
    CGFloat size = 56.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    [[UIColor colorWithWhite:0.3 alpha:1.0] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:13] fill];

    NSString *initial = (appName.length > 0) ? [appName substringToIndex:1] : @"?";
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:20 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    CGSize textSize = [initial sizeWithAttributes:attrs];
    [initial drawAtPoint:CGPointMake((size - textSize.width) / 2.0,
                                     (size - textSize.height) / 2.0)
          withAttributes:attrs];

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// --- Helper: Tối ưu hóa 2: Cache hình nền tùy chỉnh để tránh đọc ổ cứng liên tục ---
static UIImage *dinGetCachedCustomImage(NSString *path) {
    if (!path) return nil;
    static NSCache *sImageCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sImageCache = [[NSCache alloc] init]; });
    UIImage *img = [sImageCache objectForKey:path];
    if (!img) {
        img = [UIImage imageWithContentsOfFile:path];
        if (img) [sImageCache setObject:img forKey:path];
    }
    return img;
}

// ============================================================================
// MARK: - Video Background Helper
// ============================================================================

static BOOL dinIsVideoFile(NSString *path) {
    if (!path) return NO;
    NSString *ext = [path.pathExtension lowercaseString];
    return [@[@"mp4", @"mov", @"m4v", @"avi", @"mkv"] containsObject:ext];
}

@interface DINVideoBgView : UIView
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, strong) AVQueuePlayer *player;
@end

@implementation DINVideoBgView
- (void)layoutSubviews {
    [super layoutSubviews];
    self.playerLayer.frame = self.bounds;
}
- (void)dealloc {
    // Tối ưu hóa 3: Hủy bỏ vòng lặp Video để giải phóng RAM triệt để
    [self.looper disableLooping];
    [self.player pause];
    self.player = nil;
    self.looper = nil;
}
@end

static UIView *dinCreateVideoBgView(NSString *path, CGFloat opacity) {
    // Ensure video playback doesn't interrupt music
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];

    NSURL *videoURL = [NSURL fileURLWithPath:path];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:videoURL];
    AVQueuePlayer *player = [AVQueuePlayer playerWithPlayerItem:item];
    player.muted = YES;
    player.preventsDisplaySleepDuringVideoPlayback = NO;

    AVPlayerLooper *looper = [AVPlayerLooper playerLooperWithPlayer:player
                                                      templateItem:item];

    AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
    playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    playerLayer.opacity = opacity;

    DINVideoBgView *view = [[DINVideoBgView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.clipsToBounds = YES;
    view.player = player;
    view.looper = looper;
    view.playerLayer = playerLayer;
    [view.layer addSublayer:playerLayer];

    [player play];
    return view;
}

// ============================================================================
// MARK: - Pass-through Views
// ============================================================================

@class DINPassthroughWindow;

@interface DINOverlayManager : NSObject
@property (nonatomic, strong) DINPassthroughWindow *window;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *bgView;
@property (nonatomic, strong) DINNotificationView *notifView;
@property (nonatomic, strong) NSTimer *dismissTimer;
@property (nonatomic, copy) NSString *currentBundleIdentifier;
@property (nonatomic, assign) BOOL showing;
@property (nonatomic, assign) NSInteger notificationCount;
+ (instancetype)sharedInstance;
- (void)updateLayoutForNewSize:(CGSize)size;
- (void)showWithTitle:(NSString *)title message:(NSString *)message
              appName:(NSString *)appName icon:(UIImage *)icon
     bundleIdentifier:(NSString *)bundleIdentifier;
- (void)dismiss;
- (void)openAppAndDismiss;
@end

@interface DINPassthroughView : UIView
@end

@implementation DINPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    return (hitView == self) ? nil : hitView;
}
@end

@interface DINPassthroughViewController : UIViewController
@end

@implementation DINPassthroughViewController
- (void)loadView {
    self.view = [[DINPassthroughView alloc] init];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.backgroundColor = [UIColor clearColor];
}
- (BOOL)shouldAutorotate {
    return YES;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // Luôn bám theo hướng xoay thực tế của App/Game đang mở (bỏ qua Khóa xoay)
    UIInterfaceOrientation orientation = dinGetActiveOrientation();
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            return UIInterfaceOrientationMaskLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return UIInterfaceOrientationMaskLandscapeRight;
        case UIInterfaceOrientationPortraitUpsideDown:
            return UIInterfaceOrientationMaskPortraitUpsideDown;
        default:
            return UIInterfaceOrientationMaskPortrait;
    }
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [[DINOverlayManager sharedInstance] updateLayoutForNewSize:size];
    } completion:nil];
}
@end

@interface DINPassthroughWindow : UIWindow
@end

@implementation DINPassthroughWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) return nil;
    return hitView;
}
- (BOOL)_shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return YES;
}
- (BOOL)_shouldControlAutorotation {
    return YES;
}
@end

// ============================================================================
// MARK: - Dynamic Island Overlay Manager
// ============================================================================

@implementation DINOverlayManager

+ (instancetype)sharedInstance {
    static DINOverlayManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (CGRect)pillFrame {
    CGFloat screenWidth = self.window ? self.window.bounds.size.width : UIScreen.mainScreen.bounds.size.width;
    CGFloat yOffset = [DINPreferences sharedInstance].notificationYOffset;
    return CGRectMake((screenWidth - 126.0) / 2.0, 11.0 + yOffset, 126.0, 37.33);
}

- (CGRect)expandedFrameForWidth:(CGFloat)width height:(CGFloat)height {
    CGFloat screenWidth = self.window ? self.window.bounds.size.width : UIScreen.mainScreen.bounds.size.width;
    CGFloat yOffset = [DINPreferences sharedInstance].notificationYOffset;
    CGFloat w = MIN(width, screenWidth - 16.0);
    CGFloat h = MAX(44.0, MIN(height, 160.0));
    return CGRectMake((screenWidth - w) / 2.0, 11.0 + yOffset, w, h);
}

- (void)updateLayoutForNewSize:(CGSize)size {
    if (!self.showing) {
        CGFloat yOffset = [DINPreferences sharedInstance].notificationYOffset;
        self.containerView.frame = CGRectMake((size.width - 126.0) / 2.0, 11.0 + yOffset, 126.0, 37.33);
        return;
    }
    
    CGFloat expandedWidth, expandedHeight;
    NSInteger style = [DINPreferences sharedInstance].notificationStyle;
    switch (style) {
        case 1: expandedWidth = 220.0; expandedHeight = 56.0; break;
        case 2: expandedWidth = 120.0; expandedHeight = 80.0; break;
        default: expandedWidth = 320.0; expandedHeight = 72.0; break;
    }
    
    CGFloat yOffset = [DINPreferences sharedInstance].notificationYOffset;
    CGFloat w = MIN(expandedWidth, size.width - 16.0);
    CGFloat h = MAX(44.0, MIN(expandedHeight, 160.0));
    CGRect expandedFrame = CGRectMake((size.width - w) / 2.0, 11.0 + yOffset, w, h);
    
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.containerView.frame = expandedFrame;
    } completion:nil];
}

- (void)ensureWindow {
    if (self.window && self.window.windowScene &&
        self.window.windowScene.activationState == UISceneActivationStateUnattached) {
        self.window.hidden = YES;
        self.window = nil;
        self.containerView = nil;
    }

    if (self.window) return;

    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)s;
            if (ws.activationState == UISceneActivationStateForegroundActive) {
                scene = ws; break;
            }
            if (!scene) scene = ws;
        }
    }

    if (scene) {
        self.window = [[DINPassthroughWindow alloc] initWithWindowScene:scene];
    } else {
        self.window = [[DINPassthroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }

    self.window.windowLevel = UIWindowLevelStatusBar + 100;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.rootViewController = [[DINPassthroughViewController alloc] init];

    // Container view - starts as Dynamic Island pill shape, invisible
    CGRect pill = [self pillFrame];
    self.containerView = [[UIView alloc] initWithFrame:pill];
    self.containerView.backgroundColor = [UIColor clearColor]; // Đổi thành clear để xuyên thấu
    self.containerView.layer.cornerRadius = pill.size.height / 2.0;
    self.containerView.layer.cornerCurve = kCACornerCurveContinuous;
    self.containerView.clipsToBounds = NO; // Tắt clip để bóng đổ (shadow) có thể tràn ra ngoài
    
    // Thêm hiệu ứng Shadow bồng bềnh
    self.containerView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.containerView.layer.shadowOffset = CGSizeMake(0, 8);
    self.containerView.layer.shadowRadius = 24.0;
    self.containerView.layer.shadowOpacity = 0.4;
    
    self.containerView.alpha = 0; // Hidden at pill size, avoid corner mismatch with real DI
    [self.window.rootViewController.view addSubview:self.containerView];

    // Gestures
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismiss)];
    swipe.direction = UISwipeGestureRecognizerDirectionUp;
    [self.containerView addGestureRecognizer:swipe];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(openAppAndDismiss)];
    [self.containerView addGestureRecognizer:tap];
}

- (void)openAppAndDismiss {
    if (self.currentBundleIdentifier.length > 0) {
        SEL launchSel = sel_registerName("launchApplicationWithIdentifier:suspended:");
        id app = [UIApplication sharedApplication];
        if ([app respondsToSelector:launchSel]) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(app, launchSel,
                self.currentBundleIdentifier, NO);
        }
    }
    [self dismiss];
}

- (void)showWithTitle:(NSString *)title message:(NSString *)message
              appName:(NSString *)appName icon:(UIImage *)icon
     bundleIdentifier:(NSString *)bundleIdentifier {

    // --- Feature: Notification Stacking (Gom nhóm thông báo) ---
    if (self.showing) {
        if ([self.currentBundleIdentifier isEqualToString:bundleIdentifier]) {
            self.notificationCount++;
        } else {
            self.notificationCount = 1;
            self.currentBundleIdentifier = bundleIdentifier;
        }

        // Hiệu ứng Cross-dissolve (mờ dần đổi nội dung) siêu mượt
        [UIView transitionWithView:self.notifView
                          duration:0.25
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
            if ([self.notifView respondsToSelector:@selector(updateTitle:message:appName:icon:count:)]) {
                [self.notifView updateTitle:title message:message appName:appName icon:icon count:self.notificationCount];
            }
        } completion:nil];

        // Khởi động lại thời gian hiển thị
        [self.dismissTimer invalidate];
        double duration = [DINPreferences sharedInstance].dismissDuration;
        if (duration < 1.0) duration = 1.0;
        self.dismissTimer = [NSTimer scheduledTimerWithTimeInterval:duration target:self selector:@selector(dismiss) userInfo:nil repeats:NO];
        return;
    }

    self.notificationCount = 1;
    self.currentBundleIdentifier = bundleIdentifier;
    [self ensureWindow];

    // Ép Window cập nhật hướng xoay ngay lập tức khớp với Game
    if (@available(iOS 16.0, *)) {
        [self.window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [UIViewController attemptRotationToDeviceOrientation];
#pragma clang diagnostic pop
    }

    [self.dismissTimer invalidate];
    self.dismissTimer = nil;

    [self.notifView removeFromSuperview];
    [self.bgView removeFromSuperview];

    DINPreferences *prefs = [DINPreferences sharedInstance];

    // Liquid Glass Background Base
    NSString *bgPath = prefs.customBackgroundEnabled ? prefs.customBackgroundImagePath : nil;

    if (bgPath && dinIsVideoFile(bgPath)) {
        self.bgView = dinCreateVideoBgView(bgPath, prefs.backgroundOpacity);
    } else if (bgPath && [[NSFileManager defaultManager] fileExistsAtPath:bgPath]) {
        self.bgView = [[UIView alloc] init];
        self.bgView.translatesAutoresizingMaskIntoConstraints = NO;
        UIImage *bgImage = dinGetCachedCustomImage(bgPath);
        if (bgImage) {
            UIImageView *iv = [[UIImageView alloc] initWithImage:bgImage];
            iv.contentMode = UIViewContentModeScaleAspectFill;
            iv.translatesAutoresizingMaskIntoConstraints = NO;
            iv.alpha = prefs.backgroundOpacity;
            [self.bgView addSubview:iv];
            [NSLayoutConstraint activateConstraints:@[
                [iv.topAnchor constraintEqualToAnchor:self.bgView.topAnchor],
                [iv.leadingAnchor constraintEqualToAnchor:self.bgView.leadingAnchor],
                [iv.trailingAnchor constraintEqualToAnchor:self.bgView.trailingAnchor],
                [iv.bottomAnchor constraintEqualToAnchor:self.bgView.bottomAnchor],
            ]];
        }
    } else {
        // Tự động sử dụng Blur theo giao diện Sáng/Tối của hệ thống
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        blurView.translatesAutoresizingMaskIntoConstraints = NO;
        blurView.alpha = prefs.blurOpacity; // Áp dụng độ mờ riêng cho Blur
        self.bgView = blurView;
    }

    // Kích hoạt cắt viền bo tròn trực tiếp trên bgView để thay thế cho containerView
    self.bgView.clipsToBounds = YES;
    self.bgView.layer.cornerCurve = kCACornerCurveContinuous;
    self.bgView.layer.cornerRadius = self.containerView.layer.cornerRadius;

    [self.containerView insertSubview:self.bgView atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.bgView.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
        [self.bgView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [self.bgView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
        [self.bgView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor],
    ]];

    // Get notification style
    NSInteger style = prefs.notificationStyle;
    NSInteger textColorStyle = prefs.textColorStyle;

    self.notifView = [[DINNotificationView alloc] initWithTitle:title message:message
                                                        appName:appName icon:icon
                                                          style:(DINNotificationStyle)style
                                                 textColorStyle:textColorStyle];
    self.notifView.translatesAutoresizingMaskIntoConstraints = NO;
    self.notifView.alpha = 0;
    self.notifView.transform = CGAffineTransformMakeScale(0.5, 0.5);
    [self.containerView addSubview:self.notifView];

    // Layout dimensions per style
    CGFloat expandedWidth, expandedHeight, centerYOffset, leadingPad;
    switch (style) {
        case 1: // Compact
            expandedWidth = 220.0;
            expandedHeight = 56.0;
            centerYOffset = 0.0;
            leadingPad = 12.0;
            break;
        case 2: // Minimal
            expandedWidth = 120.0;
            expandedHeight = 80.0;
            centerYOffset = 0.0;
            leadingPad = 12.0;
            break;
        default: // Standard
            expandedWidth = 320.0;
            expandedHeight = 72.0;
            centerYOffset = 0.0;
            leadingPad = 16.0;
            break;
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.notifView.centerYAnchor constraintEqualToAnchor:self.containerView.centerYAnchor constant:centerYOffset],
        [self.notifView.centerXAnchor constraintEqualToAnchor:self.containerView.centerXAnchor],
        [self.notifView.widthAnchor constraintLessThanOrEqualToAnchor:self.containerView.widthAnchor constant:-(leadingPad * 2)],
    ]];

    // Start from pill shape
    if (!self.showing) {
        CGRect pill = [self pillFrame];
        self.containerView.frame = pill;
        self.containerView.layer.cornerRadius = pill.size.height / 2.0;
        self.bgView.layer.cornerRadius = pill.size.height / 2.0;
        self.containerView.alpha = 0;
    }

    self.window.hidden = NO;
    self.showing = YES;

    CGRect expandedFrame = [self expandedFrameForWidth:expandedWidth height:expandedHeight];
    CGFloat expandedRadius = expandedFrame.size.height / 2.0; // Capsule shape like AirDrop

    // Đã xóa hiệu ứng Haptic rung ở đây vì %orig sẽ tự động kích hoạt rung/chuông mặc định của iOS

    double animDuration = [DINPreferences sharedInstance].animationDuration;
    // Spring expand animation - Hiệu ứng "giọt nước rơi" mượt mà, đàn hồi
    [UIView animateWithDuration:animDuration delay:0
         usingSpringWithDamping:0.6 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.containerView.alpha = 1.0;
        self.containerView.frame = expandedFrame;
        self.containerView.layer.cornerRadius = expandedRadius;
        self.bgView.layer.cornerRadius = expandedRadius;
        self.notifView.alpha = 1.0;
        self.notifView.transform = CGAffineTransformIdentity;
    } completion:nil];

    // Auto-dismiss after configured duration
    double duration = [DINPreferences sharedInstance].dismissDuration;
    if (duration < 1.0) duration = 1.0;
    self.dismissTimer = [NSTimer scheduledTimerWithTimeInterval:duration
        target:self selector:@selector(dismiss) userInfo:nil repeats:NO];
}

- (void)dismiss {
    if (!self.showing) return;

    [self.dismissTimer invalidate];
    self.dismissTimer = nil;

    CGRect pill = [self pillFrame];
    CGFloat pillRadius = pill.size.height / 2.0;

    double animDuration = [DINPreferences sharedInstance].animationDuration;
    double fadeOutTextDur = (animDuration / 0.45) * 0.15;
    double shrinkDelay = (animDuration / 0.45) * 0.1;
    double shrinkDur = (animDuration / 0.45) * 0.4;
    double fadeOutBgDur = (animDuration / 0.45) * 0.2;

    // 1. Làm mờ (Fade out) phần văn bản/nội dung cực nhanh trước
    [UIView animateWithDuration:fadeOutTextDur delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.notifView.alpha = 0;
        self.notifView.transform = CGAffineTransformMakeScale(0.6, 0.6);
    } completion:nil];

    // 2. Khung viền thu nhỏ lại thành viên thuốc (delay để chờ chữ mờ đi)
    [UIView animateWithDuration:shrinkDur delay:shrinkDelay
     usingSpringWithDamping:0.7 initialSpringVelocity:1.0
                    options:UIViewAnimationOptionCurveEaseInOut
                 animations:^{
        self.containerView.frame = pill;
        self.containerView.layer.cornerRadius = pillRadius;
        self.bgView.layer.cornerRadius = pillRadius;
        self.bgView.alpha = 0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:fadeOutBgDur animations:^{
            self.containerView.alpha = 0;
        } completion:^(BOOL finished) {
            self.window.hidden = YES;
            self.showing = NO;
            [self.notifView removeFromSuperview];
            [self.bgView removeFromSuperview];
            self.notifView = nil;
            self.bgView = nil;
        }];
    }];
}

@end

// ============================================================================
// MARK: - Hooks
// ============================================================================

%hook NCNotificationDispatcher

- (void)postNotificationWithRequest:(NCNotificationRequest *)request {
    // 1. Luôn gọi %orig ĐẦU TIÊN để hệ thống lưu thông báo (vào Màn hình khóa/Trung tâm thông báo) và phát âm thanh
    %orig;

    DINPreferences *prefs = [DINPreferences sharedInstance];

    // 2. Nếu Tweak bị tắt, không làm gì thêm
    if (!prefs.enabled || !prefs.notificationEnabled) {
        return;
    }

    // 3. Nếu đang ở màn hình khóa hoặc đang kéo thanh thông báo, nhường quyền cho iOS hiển thị Banner gốc
    if (dinIsDeviceLockedOrInCoverSheet()) {
        return;
    }

    // 4. Bắt đầu hiển thị giao diện ShimaStyle
    NCNotificationContent *content = [request content];
    if (!content) return;

    NSString *title = [content title];
    NSString *message = [content message];
    if (!title && !message) return;

    if (dinShouldThrottle()) {
        // Suppress entirely when throttled
        return;
    }
    sLastNotificationTime = [NSDate date];

    NSString *bundleIdentifier = [request sectionIdentifier];
    NSString *appName = nil;

    // --- Fix: Lưu Cache tên ứng dụng để tránh Delay ---
    static NSCache *sAppNameCache = nil;
    static dispatch_once_t onceTokenName;
    dispatch_once(&onceTokenName, ^{ sAppNameCache = [[NSCache alloc] init]; });

    if (bundleIdentifier) {
        appName = [sAppNameCache objectForKey:bundleIdentifier];
        if (!appName) {
            // Tối ưu hóa 1: Cache AppController Class
            static Class s_SBAppControllerClass = nil;
            static dispatch_once_t onceTokenApp;
            dispatch_once(&onceTokenApp, ^{ s_SBAppControllerClass = objc_lookUpClass("SBApplicationController"); });
            
            SBApplicationController *appController = [s_SBAppControllerClass sharedInstance];
            if (appController) {
                SBApplication *app = [appController applicationWithBundleIdentifier:bundleIdentifier];
                if (app && [app respondsToSelector:@selector(displayName)]) appName = [app displayName];
            }
            if (!appName) {
                LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:bundleIdentifier];
                if (proxy) appName = [proxy localizedName];
            }
            if (appName) [sAppNameCache setObject:appName forKey:bundleIdentifier];
        }
    }

    UIImage *icon = dinAppIcon(bundleIdentifier);
    if (!icon) icon = dinPlaceholderIcon(appName);

    // Do NOT call %orig — fully suppress system notification (banner + notification center)
    // Show DI overlay instead
    dispatch_block_t showBlock = ^{
        [[DINOverlayManager sharedInstance] showWithTitle:title message:message
                                                  appName:appName icon:icon
                                         bundleIdentifier:bundleIdentifier];
    };
    if ([NSThread isMainThread]) {
        showBlock(); // Nếu đang ở luồng chính thì hiển thị ngay lập tức không cần chờ
    } else {
        dispatch_async(dispatch_get_main_queue(), showBlock);
    }
}

%end

// --- Chặn Banner mặc định của iOS khi ShimaStyle đang hoạt động trên màn hình chính ---

%hook SBNCAlertingController
- (BOOL)alertDispatcher:(id)arg1 shouldPresentAlertForNotificationRequest:(id)arg2 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) {
        return NO; // Chặn Banner
    }
    return %orig;
}
- (void)alertDispatcher:(id)arg1 postAlertForNotificationRequest:(id)arg2 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
%end

%hook NCNotificationBannerDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return NO;
    return %orig;
}
- (void)postNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
- (void)modifyNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
%end

%hook SBNotificationBannerDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return NO;
    return %orig;
}
- (void)postNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
- (void)modifyNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
%end

// --- Ultimate Fail-safe chặn thông báo gốc thông qua BannerKit ---
%hook BNBannerSource
- (BOOL)postPresentable:(id)arg1 options:(id)arg2 userInfo:(id)arg3 error:(id *)arg4 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) {
        // Kiểm tra xem đối tượng chuẩn bị vẽ lên màn hình có phải là Thông báo không
        if ([arg1 respondsToSelector:@selector(notificationRequest)]) {
            return YES; // Giả vờ đã hiển thị thành công để hệ thống không báo lỗi
        }
    }
    return %orig;
}
%end

// --- Chặn thông báo nguyên bản của Dynamic Island (System Aperture) ---

%hook SBNCSystemApertureNotificationDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return NO;
    return %orig;
}
- (void)postNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
- (void)modifyNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
%end

%hook SBSystemApertureNotificationDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return NO;
    return %orig;
}
- (void)postNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
- (void)modifyNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
%end

%hook NCNotificationSystemApertureDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return NO;
    return %orig;
}
- (void)postNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
- (void)modifyNotificationRequest:(id)arg1 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) return;
    %orig;
}
%end

// ============================================================================
// MARK: - Custom Background + Border for Real Dynamic Island Content
// ============================================================================

static void *kDINCustomBgViewKey = &kDINCustomBgViewKey;
static void *kDINBorderLayerKey = &kDINBorderLayerKey;

%hook SBSystemApertureContainerView

- (id)initWithInterfaceElementIdentifier:(id)identifier {
    id result = %orig;
    if (!result) return nil;

    DINPreferences *prefs = [DINPreferences sharedInstance];
    UIView *selfView = (UIView *)result;

    if (prefs.customBackgroundEnabled) {
        NSString *bgPath = prefs.customBackgroundImagePath;
        UIView *customBg;

        if (bgPath && dinIsVideoFile(bgPath)) {
            customBg = dinCreateVideoBgView(bgPath, prefs.backgroundOpacity);
        } else if (bgPath && [[NSFileManager defaultManager] fileExistsAtPath:bgPath]) {
            customBg = [[UIView alloc] init];
            customBg.translatesAutoresizingMaskIntoConstraints = NO;
            customBg.clipsToBounds = YES;
            UIImage *bgImage = dinGetCachedCustomImage(bgPath);
            if (bgImage) {
                UIImageView *iv = [[UIImageView alloc] initWithImage:bgImage];
                iv.contentMode = UIViewContentModeScaleAspectFill;
                iv.translatesAutoresizingMaskIntoConstraints = NO;
                iv.alpha = prefs.backgroundOpacity;
                [customBg addSubview:iv];
                [NSLayoutConstraint activateConstraints:@[
                    [iv.topAnchor constraintEqualToAnchor:customBg.topAnchor],
                    [iv.leadingAnchor constraintEqualToAnchor:customBg.leadingAnchor],
                    [iv.trailingAnchor constraintEqualToAnchor:customBg.trailingAnchor],
                    [iv.bottomAnchor constraintEqualToAnchor:customBg.bottomAnchor],
                ]];
            }
        } else {
            UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
            blurView.translatesAutoresizingMaskIntoConstraints = NO;
            blurView.alpha = prefs.blurOpacity; // Áp dụng độ mờ riêng cho Blur
            customBg = blurView;
        }

        [selfView insertSubview:customBg atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [customBg.topAnchor constraintEqualToAnchor:selfView.topAnchor],
            [customBg.leadingAnchor constraintEqualToAnchor:selfView.leadingAnchor],
            [customBg.trailingAnchor constraintEqualToAnchor:selfView.trailingAnchor],
            [customBg.bottomAnchor constraintEqualToAnchor:selfView.bottomAnchor],
        ]];

        objc_setAssociatedObject(result, kDINCustomBgViewKey, customBg,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return result;
}

- (void)layoutSubviews {
    %orig;

    // Clip custom background to match the DI shape (pill or expanded)
    UIView *customBg = objc_getAssociatedObject(self, kDINCustomBgViewKey);
    if (customBg) {
        if (self.layer.mask && [self.layer.mask isKindOfClass:[CAShapeLayer class]]) {
            CGPathRef maskPath = ((CAShapeLayer *)self.layer.mask).path;
            CAShapeLayer *bgMask = [CAShapeLayer layer];
            bgMask.frame = self.bounds;
            bgMask.path = maskPath;
            customBg.layer.mask = bgMask;
        } else {
            CGFloat radius = self.layer.cornerRadius;
            if (radius <= 0) radius = self.bounds.size.height / 2.0;
            customBg.layer.cornerRadius = radius;
            customBg.layer.cornerCurve = kCACornerCurveContinuous;
            customBg.clipsToBounds = YES;
            customBg.layer.mask = nil;
        }

        // Resume video playback if it was paused during DI state transitions
        if ([customBg isKindOfClass:[DINVideoBgView class]]) {
            AVQueuePlayer *player = ((DINVideoBgView *)customBg).player;
            if (player && player.rate == 0) {
                [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
                [player play];
            }
        }
    }
}

%end

// ============================================================================
// MARK: - Constructor
// ============================================================================

%ctor {
    [[DINPreferences sharedInstance] reloadPreferences];

    int token = 0;
    notify_register_dispatch("com.34306.shimastyle/prefsChanged",
        &token, dispatch_get_main_queue(), ^(int t) {
            [[DINPreferences sharedInstance] reloadPreferences];
        });

    int testToken = 0;
    notify_register_dispatch("com.34306.shimastyle/testNotification",
        &testToken, dispatch_get_main_queue(), ^(int t) {
            UIImage *icon = dinAppIcon(@"com.apple.Preferences");
            if (!icon) icon = dinPlaceholderIcon(@"Settings");
            [[DINOverlayManager sharedInstance] showWithTitle:@"Test Notification"
                                                     message:@"This is a test notification from ShimaStyle"
                                                     appName:@"Settings"
                                                        icon:icon
                                            bundleIdentifier:@"com.apple.Preferences"];
        });

    %init;
}
