#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <ImageIO/ImageIO.h>
#import <notify.h>
#import "DINNotificationView.h"
#import "DINPreferences.h"

@interface DINNotificationView (Stacking)
- (void)updateTitle:(NSString *)title message:(NSString *)message appName:(NSString *)appName icon:(UIImage *)icon count:(NSInteger)count;
- (void)startMarquee;
@end

// ============================================================================
// MARK: - Private Class Interfaces
// ============================================================================

@interface NCNotificationContent : NSObject
- (NSString *)title;
- (NSString *)subtitle;
- (NSString *)message;
- (UIImage *)icon;
- (NSArray *)icons;
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

@interface PKPushPayload : NSObject
- (NSDictionary *)dictionaryPayload;
@end

// ============================================================================
// MARK: - Rate Limiting
// ============================================================================

static NSDate *sLastNotificationTime = nil;
static NSTimeInterval const kMinNotificationInterval = 0.2;

static BOOL dinShouldThrottle(void) {
    if (!sLastNotificationTime) return NO;
    return [[NSDate date] timeIntervalSinceDate:sLastNotificationTime] < kMinNotificationInterval;
}

// ============================================================================
// MARK: - Helper: Lock Screen & CoverSheet State
// ============================================================================

static BOOL dinIsDeviceLockedOrInCoverSheet(void) {
    __block BOOL isLocked = NO;
    dispatch_block_t getLockBlock = ^{
        static Class s_SBLockScreenManagerClass = nil;
        static dispatch_once_t onceTokenLock;
        dispatch_once(&onceTokenLock, ^{ s_SBLockScreenManagerClass = objc_lookUpClass("SBLockScreenManager"); });
        
        if (s_SBLockScreenManagerClass) {
            id lockScreenManager = ((id (*)(Class, SEL))objc_msgSend)(s_SBLockScreenManagerClass, sel_registerName("sharedInstance"));
            if (lockScreenManager && [lockScreenManager respondsToSelector:@selector(isLockScreenVisible)]) {
                isLocked = ((BOOL (*)(id, SEL))objc_msgSend)(lockScreenManager, @selector(isLockScreenVisible));
            }
        }
    };
    if ([NSThread isMainThread]) {
        getLockBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), getLockBlock); // Ép chạy an toàn trên luồng chính
    }
    return isLocked;
}

// --- Helper: Lấy BundleID của ứng dụng đang hiển thị trên màn hình ---
static NSString *dinActiveAppBundleID(void) {
    __block NSString *activeApp = nil;
    dispatch_block_t getAppBlock = ^{
        @try {
            id sb = [UIApplication sharedApplication];
            if ([sb respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
                id app = [sb performSelector:@selector(_accessibilityFrontMostApplication)];
                if (app && [app respondsToSelector:@selector(bundleIdentifier)]) {
                    activeApp = [app performSelector:@selector(bundleIdentifier)];
                }
            }
        } @catch (NSException *e) {}
    };
    if ([NSThread isMainThread]) {
        getAppBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), getAppBlock); // Tránh gây treo luồng nền của iOS
    }
    return activeApp;
}

// --- Helper: Lấy hướng xoay THỰC TẾ của ứng dụng đang mở ---
static UIInterfaceOrientation dinGetActiveOrientation(void) {
    __block UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
    dispatch_block_t getOrientationBlock = ^{
        id sb = [UIApplication sharedApplication];
        if ([sb respondsToSelector:sel_registerName("activeInterfaceOrientation")]) {
            orientation = (UIInterfaceOrientation)((NSInteger (*)(id, SEL))objc_msgSend)(sb, sel_registerName("activeInterfaceOrientation"));
        }
    };
    if ([NSThread isMainThread]) {
        getOrientationBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), getOrientationBlock);
    }
    return orientation;
}

// ============================================================================
// MARK: - Bộ Lọc Hiển Thị Thông Minh (Smart Banner Filter)
// ============================================================================

static BOOL dinShouldShowCustomBanner(id request) {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (!prefs.enabled || !prefs.notificationEnabled) return NO;
    
    if (dinIsDeviceLockedOrInCoverSheet()) return NO; // Đang ở Màn hình khóa -> Nhường hệ thống

    NSString *bundleIdentifier = [request respondsToSelector:@selector(sectionIdentifier)] ? [request sectionIdentifier] : nil;
    NSString *activeApp = dinActiveAppBundleID();
    
    if (bundleIdentifier && [bundleIdentifier isEqualToString:activeApp]) {
        return NO; // Nhận tin nhắn từ app đang mở -> Nhường app tự hiện thông báo trong
    }
    
    return YES;
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

    // Method 1: SBIconController (Nhanh nhất & Tối ưu RAM vì đọc trực tiếp trên bộ nhớ SpringBoard)
    @try {
        Class iconControllerClass = objc_lookUpClass("SBIconController");
        if (iconControllerClass) {
            id iconController = ((id (*)(Class, SEL))objc_msgSend)(iconControllerClass, sel_registerName("sharedInstance"));
            if (iconController) {
                id iconManager = nil;
                if ([iconController respondsToSelector:sel_registerName("iconManager")]) {
                    iconManager = ((id (*)(id, SEL))objc_msgSend)(iconController, sel_registerName("iconManager"));
                }
                id model = nil;
                if (iconManager && [iconManager respondsToSelector:sel_registerName("iconModel")]) {
                    model = ((id (*)(id, SEL))objc_msgSend)(iconManager, sel_registerName("iconModel"));
                } else if ([iconController respondsToSelector:sel_registerName("model")]) {
                    model = ((id (*)(id, SEL))objc_msgSend)(iconController, sel_registerName("model"));
                }
                
                if (model) {
                    id icon = ((id (*)(id, SEL, id))objc_msgSend)(model, sel_registerName("applicationIconForBundleIdentifier:"), bundleIdentifier);
                    if (icon && [icon respondsToSelector:sel_registerName("getIconImage:")]) {
                        foundIcon = ((id (*)(id, SEL, int))objc_msgSend)(icon, sel_registerName("getIconImage:"), 2);
                    } else if (icon && [icon respondsToSelector:sel_registerName("generateIconImage:")]) {
                        foundIcon = ((id (*)(id, SEL, int))objc_msgSend)(icon, sel_registerName("generateIconImage:"), 2);
                    }
                }
            }
        }
    } @catch (NSException *e) {}

    // Method 2: UIImage private API
    if (!foundIcon) {
        @try {
            SEL iconSel = sel_registerName("_applicationIconImageForBundleIdentifier:format:scale:");
            if ([UIImage respondsToSelector:iconSel]) {
                foundIcon = ((id (*)(Class, SEL, id, int, CGFloat))objc_msgSend)(
                    [UIImage class], iconSel, bundleIdentifier, 1, UIScreen.mainScreen.scale);
                if (!foundIcon) {
                    foundIcon = ((id (*)(Class, SEL, id, int, CGFloat))objc_msgSend)(
                        [UIImage class], iconSel, bundleIdentifier, 2, UIScreen.mainScreen.scale);
                }
                if (!foundIcon) {
                    foundIcon = ((id (*)(Class, SEL, id, int, CGFloat))objc_msgSend)(
                        [UIImage class], iconSel, bundleIdentifier, 0, UIScreen.mainScreen.scale);
                }
            }
        } @catch (NSException *e) {}
    }

    // Method 3: IconServices (Chuyên trị Ứng dụng Hệ thống, nhưng XPC call khá chậm)
    if (!foundIcon) {
        @try {
            Class isIconClass = objc_lookUpClass("ISIcon");
            Class isImageDescriptorClass = objc_lookUpClass("ISImageDescriptor");
            if (isIconClass && isImageDescriptorClass) {
                id icon = ((id (*)(id, SEL, id))objc_msgSend)([isIconClass alloc], sel_registerName("initWithBundleIdentifier:"), bundleIdentifier);
                if (icon) {
                    id descriptor = ((id (*)(id, SEL, CGSize, CGFloat))objc_msgSend)([isImageDescriptorClass alloc], sel_registerName("initWithSize:scale:"), CGSizeMake(60, 60), UIScreen.mainScreen.scale);
                    if (descriptor) {
                        id isImage = ((id (*)(id, SEL, id))objc_msgSend)(icon, sel_registerName("imageForImageDescriptor:"), descriptor);
                        if (isImage) {
                            CGImageRef cgImage = (__bridge CGImageRef)((id (*)(id, SEL))objc_msgSend)(isImage, sel_registerName("CGImage"));
                            if (cgImage) {
                                foundIcon = [UIImage imageWithCGImage:cgImage scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp];
                            }
                        }
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
        if ([[path.pathExtension lowercaseString] isEqualToString:@"gif"]) {
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (data) {
                CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
                if (source) {
                    size_t count = CGImageSourceGetCount(source);
                    NSMutableArray *images = [NSMutableArray array];
                    NSTimeInterval duration = 0.0f;
                    
                    for (size_t i = 0; i < count; i++) {
                        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
                        if (imageRef) {
                            [images addObject:[UIImage imageWithCGImage:imageRef scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp]];
                            
                            NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
                            NSDictionary *gifProperties = properties[(NSString *)kCGImagePropertyGIFDictionary];
                            NSNumber *delayTime = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
                            if (!delayTime) delayTime = gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
                            duration += [delayTime doubleValue] ?: 0.1;
                            
                            CGImageRelease(imageRef);
                        }
                    }
                    CFRelease(source);
                    
                    if (images.count > 0) {
                        img = [UIImage animatedImageWithImages:images duration:duration];
                    }
                }
            }
        } else {
            img = [UIImage imageWithContentsOfFile:path];
        }
        
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
// MARK: - Landscape Offset Preferences Cache
// ============================================================================

static CGFloat sLandscapeXOffset = 0.0;
static CGFloat sLandscapeYOffset = 0.0;

static void dinReloadLandscapeOffsets() {
    CFPreferencesAppSynchronize((CFStringRef)@"com.34306.shimastyle");
    NSNumber *xVal = (NSNumber *)CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)@"landscapeXOffset", (CFStringRef)@"com.34306.shimastyle"));
    sLandscapeXOffset = xVal ? [xVal floatValue] : 0.0;
    
    NSNumber *yVal = (NSNumber *)CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)@"landscapeYOffset", (CFStringRef)@"com.34306.shimastyle"));
    sLandscapeYOffset = yVal ? [yVal floatValue] : 0.0;
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
- (CGRect)calculateFrameForWidth:(CGFloat)width height:(CGFloat)height size:(CGSize)size;
+ (void)presentNotificationFromRequest:(id)request withForcedTitle:(NSString *)forcedTitle message:(NSString *)forcedMessage bundleIdentifier:(NSString *)forcedBundleID;
+ (void)presentNotificationFromRequest:(id)request;
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

- (CGRect)calculateFrameForWidth:(CGFloat)width height:(CGFloat)height size:(CGSize)size {
    BOOL isLandscape = size.width > size.height;
    CGFloat yOffset = isLandscape ? sLandscapeYOffset : [DINPreferences sharedInstance].notificationYOffset;
    CGFloat xOffset = isLandscape ? sLandscapeXOffset : 0.0;
    
    CGFloat x = (size.width - width) / 2.0; // Default Center (Chế độ dọc)
    
    if (isLandscape) {
        UIInterfaceOrientation orientation = dinGetActiveOrientation();
        if (orientation == UIInterfaceOrientationLandscapeRight) {
            // Nút Home bên Phải -> Tai thỏ nằm ở mép Trái
            x = 16.0;
        } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
            // Nút Home bên Trái -> Tai thỏ nằm ở mép Phải
            x = size.width - width - 16.0;
        } else {
            x = 16.0;
        }
    }
    
    x += xOffset;
    
    return CGRectMake(x, 11.0 + yOffset, width, height);
}

- (CGRect)pillFrame {
    CGSize size = self.window ? self.window.bounds.size : UIScreen.mainScreen.bounds.size;
    return [self calculateFrameForWidth:126.0 height:37.33 size:size];
}

- (CGRect)expandedFrameForWidth:(CGFloat)width height:(CGFloat)height {
    CGSize size = self.window ? self.window.bounds.size : UIScreen.mainScreen.bounds.size;
    CGFloat w = MIN(width, size.width - 16.0);
    CGFloat h = MAX(44.0, MIN(height, 160.0));
    return [self calculateFrameForWidth:w height:h size:size];
}

- (void)updateLayoutForNewSize:(CGSize)size {
    if (!self.showing) {
        self.containerView.frame = [self calculateFrameForWidth:126.0 height:37.33 size:size];
        return;
    }
    
    CGFloat expandedWidth, expandedHeight;
    NSInteger style = [DINPreferences sharedInstance].notificationStyle;
    switch (style) {
        case 1: expandedWidth = 220.0; expandedHeight = 56.0; break;
        case 2: expandedWidth = 120.0; expandedHeight = 64.0; break;
        default: {
            expandedHeight = 72.0; // Khoá cố định chiều cao
            BOOL isLandscape = size.width > size.height;
            if (isLandscape) {
                expandedWidth = 320.0; // Giữ nguyên kích thước 320pt khi xoay ngang
            } else {
                CGFloat titleW = [self.notifView.titleLabel intrinsicContentSize].width;
                CGFloat msgW = [self.notifView.messageLabel intrinsicContentSize].width;
                CGFloat desiredWidth = MAX(240.0, MAX(titleW, msgW) + 68.0); // Tính toán độ dài chuẩn xác dựa trên số lượng chữ
                expandedWidth = MIN(desiredWidth, size.width - 16.0); // Không vượt quá 2 mép màn hình
            }
            break;
        }
    }
    
    CGFloat w = MIN(expandedWidth, size.width - 16.0);
    CGFloat h = MAX(44.0, MIN(expandedHeight, 160.0));
    CGRect expandedFrame = [self calculateFrameForWidth:w height:h size:size];
    
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
            
            // Tự động co giãn chiều dài khung (Chỉ dành cho chế độ Tiêu chuẩn)
            DINPreferences *prefs = [DINPreferences sharedInstance];
            if (prefs.notificationStyle == 0) {
                BOOL isLandscape = self.window.bounds.size.width > self.window.bounds.size.height;
                CGFloat w;
                if (isLandscape) {
                    w = MIN(320.0, self.window.bounds.size.width - 16.0);
                } else {
                    CGFloat titleW = [self.notifView.titleLabel intrinsicContentSize].width;
                    CGFloat msgW = [self.notifView.messageLabel intrinsicContentSize].width;
                    CGFloat desiredWidth = MAX(240.0, MAX(titleW, msgW) + 68.0);
                    w = MIN(desiredWidth, self.window.bounds.size.width - 16.0);
                }
                CGRect newFrame = [self expandedFrameForWidth:w height:72.0];
                
                self.containerView.frame = newFrame;
            }
    } completion:^(BOOL finished) {
        if ([self.notifView respondsToSelector:@selector(startMarquee)]) {
            [self.notifView startMarquee];
        }
    }];

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
    [self.window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];

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
    CGFloat expandedWidth, expandedHeight;
    switch (style) {
        case 1: // Compact
            expandedWidth = 220.0;
            expandedHeight = 56.0;
            break;
        case 2: // Minimal
            expandedWidth = 120.0;
            expandedHeight = 64.0;
            break;
        default: // Standard
        {
            expandedHeight = 72.0;
            BOOL isLandscape = self.window.bounds.size.width > self.window.bounds.size.height;
            if (isLandscape) {
                expandedWidth = 320.0;
            } else {
                CGFloat titleW = [self.notifView.titleLabel intrinsicContentSize].width;
                CGFloat msgW = [self.notifView.messageLabel intrinsicContentSize].width;
                CGFloat desiredWidth = MAX(240.0, MAX(titleW, msgW) + 68.0);
                expandedWidth = MIN(desiredWidth, self.window.bounds.size.width - 16.0);
            }
            break;
        }
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.notifView.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
        [self.notifView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor],
        [self.notifView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [self.notifView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
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
         usingSpringWithDamping:0.65 initialSpringVelocity:1.2
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.containerView.alpha = 1.0;
        self.containerView.frame = expandedFrame;
        self.containerView.layer.cornerRadius = expandedRadius;
        self.bgView.layer.cornerRadius = expandedRadius;
        self.notifView.alpha = 1.0;
        self.notifView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        // Sau khi bung mở xong, kiểm tra và chạy hiệu ứng chữ nếu dài
        if ([self.notifView respondsToSelector:@selector(startMarquee)]) {
            [self.notifView startMarquee];
        }
    }];

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
    
    // Dừng ngay hiệu ứng cuộn chữ (nếu có) để tránh giật hình
    [self.notifView.messageLabel.layer removeAllAnimations];

    // 1. Làm mờ phần văn bản/nội dung cực nhanh (chỉ tốn 1/3 thời gian tổng)
    [UIView animateWithDuration:animDuration * 0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.notifView.alpha = 0;
        self.notifView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:nil];

    // 2. Thu nhỏ khung viền và hoà quyện mờ dần vào DI nguyên bản
    [UIView animateWithDuration:animDuration delay:0
         usingSpringWithDamping:0.75 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                 animations:^{
        self.containerView.frame = pill;
        self.containerView.layer.cornerRadius = pillRadius;
        self.bgView.layer.cornerRadius = pillRadius;
        self.containerView.alpha = 0; // Làm mờ bóng đổ và viền ĐỒNG THỜI khi thu nhỏ
    } completion:^(BOOL finished) {
        self.window.hidden = YES;
        self.showing = NO;
        [self.notifView removeFromSuperview];
        [self.bgView removeFromSuperview];
        self.notifView = nil;
        self.bgView = nil;
    }];
}

    // ============================================================================
    // MARK: - Core Notification Presentation Logic
    // ============================================================================

+ (void)presentNotificationFromRequest:(id)request withForcedTitle:(NSString *)forcedTitle message:(NSString *)forcedMessage bundleIdentifier:(NSString *)forcedBundleID {
    [self _presentWithRequest:request forcedTitle:forcedTitle forcedMessage:forcedMessage forcedBundleID:forcedBundleID];
}

+ (void)presentNotificationFromRequest:(id)request {
    [self _presentWithRequest:request forcedTitle:nil forcedMessage:nil forcedBundleID:nil];
}

+ (void)_presentWithRequest:(id)request forcedTitle:(NSString *)forcedTitle forcedMessage:(NSString *)forcedMessage forcedBundleID:(NSString *)forcedBundleID {
    NCNotificationContent *content = [request respondsToSelector:@selector(content)] ? [request content] : nil;
    NSString *bundleIdentifier = forcedBundleID ?: ([request respondsToSelector:@selector(sectionIdentifier)] ? [request sectionIdentifier] : nil);

    dispatch_block_t showBlock = ^{
        
        NSString *title = [content respondsToSelector:@selector(title)] ? [content title] : nil;
        NSString *message = [content respondsToSelector:@selector(message)] ? [content message] : nil;
        
        NSString *finalTitle = title;
        NSString *finalMessage = message;

        if (forcedTitle || forcedMessage) {
            finalTitle = forcedTitle;
            finalMessage = forcedMessage;
        } else {
            NSString *subtitle = [content respondsToSelector:@selector(subtitle)] ? [content subtitle] : nil;
            if (!finalMessage && subtitle) {
                finalMessage = subtitle; // Nếu không có message, lấy subtitle đắp vào
            } else if (title && subtitle) {
                finalTitle = [NSString stringWithFormat:@"%@ - %@", title, subtitle]; // Nối title và subtitle
            }
        }
        
        if (!finalTitle && !finalMessage) return;

        NSString *appName = nil;
        static NSCache *sAppNameCache = nil;
        static dispatch_once_t onceTokenName;
        dispatch_once(&onceTokenName, ^{ sAppNameCache = [[NSCache alloc] init]; });
        
        if (bundleIdentifier) {
            appName = [sAppNameCache objectForKey:bundleIdentifier];
            if (!appName) {
                static Class s_SBAppControllerClass = nil;
                static dispatch_once_t onceTokenApp;
                dispatch_once(&onceTokenApp, ^{ s_SBAppControllerClass = objc_lookUpClass("SBApplicationController"); });
                
                SBApplicationController *appController = [s_SBAppControllerClass sharedInstance];
                if (appController && [appController respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
                    SBApplication *app = [appController applicationWithBundleIdentifier:bundleIdentifier];
                    if (app && [app respondsToSelector:@selector(displayName)]) appName = [app displayName];
                }
                if (appName) [sAppNameCache setObject:appName forKey:bundleIdentifier];
            }
        }
        
        UIImage *icon = nil;
        if ([content respondsToSelector:@selector(icons)] && [[content performSelector:@selector(icons)] isKindOfClass:[NSArray class]]) {
            NSArray *icons = [content performSelector:@selector(icons)];
            if (icons.count > 0) icon = icons.firstObject;
        } else if ([content respondsToSelector:@selector(icon)]) {
            icon = [content performSelector:@selector(icon)];
        }
        if (!icon) icon = dinAppIcon(bundleIdentifier);
        if (!icon) icon = dinPlaceholderIcon(appName);
        
        [[DINOverlayManager sharedInstance] showWithTitle:finalTitle message:finalMessage
                                                  appName:appName icon:icon
                                         bundleIdentifier:bundleIdentifier];
    };

    if ([NSThread isMainThread]) {
        showBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), showBlock);
    }
}

@end

// ============================================================================
// MARK: - Hooks
// ============================================================================

%hook NCNotificationDispatcher

- (void)postNotificationWithRequest:(id)request {
    %orig; 

    if (!dinShouldShowCustomBanner(request)) return;
    if (dinShouldThrottle()) return;
    
    sLastNotificationTime = [NSDate date];
    [DINOverlayManager presentNotificationFromRequest:request];
}

- (void)modifyNotificationWithRequest:(id)request {
    %orig;
    if (!dinShouldShowCustomBanner(request)) return;
    [DINOverlayManager presentNotificationFromRequest:request];
}

%end

// --- Chặn Banner mặc định của iOS ---

%hook SBNCAlertingController
- (BOOL)alertDispatcher:(id)arg1 shouldPresentAlertForNotificationRequest:(id)arg2 {
    if (dinShouldShowCustomBanner(arg2)) return NO;
    return %orig;
}
- (void)alertDispatcher:(id)arg1 postAlertForNotificationRequest:(id)arg2 {
    if (dinShouldShowCustomBanner(arg2)) return;
    %orig;
}
%end

%hook NCNotificationBannerDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    if (dinShouldShowCustomBanner(arg1)) return NO;
    return %orig;
}
%end

%hook SBNotificationBannerDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    if (dinShouldShowCustomBanner(arg1)) return NO;
    return %orig;
}
%end

// --- Chặn thông báo nguyên bản của Dynamic Island (System Aperture) ---

%hook SBNCSystemApertureNotificationDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    if (dinShouldShowCustomBanner(arg1)) return NO;
    return %orig;
}
%end

%hook SBSystemApertureNotificationDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    if (dinShouldShowCustomBanner(arg1)) return NO;
    return %orig;
}
%end

%hook NCNotificationSystemApertureDestination
- (BOOL)canReceiveNotificationRequest:(id)arg1 {
    if (dinShouldShowCustomBanner(arg1)) return NO;
    return %orig;
}
%end

%hook PKPushRegistry
- (void)pushRegistry:(id)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type withCompletionHandler:(void (^)(void))completion {
    %orig;

    @try {
        // Chỉ xử lý PushKit của Telegram
        id delegate = [(id)self delegate];
        NSString *bundleIdentifier = nil;
        if ([delegate respondsToSelector:@selector(bundleIdentifier)]) {
            bundleIdentifier = [delegate performSelector:@selector(bundleIdentifier)];
        }
        if (![bundleIdentifier isEqualToString:@"ph.telegra.Telegraph"]) {
            return;
        }

        if (!dinShouldShowCustomBanner(nil)) return; // Dùng bộ lọc chung (đã bao gồm check Tweak bật/tắt, Lockscreen, Active App)
        
        NSDictionary *dict = [payload dictionaryPayload];
        if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return;
        
        NSDictionary *aps = dict[@"aps"];
        if (!aps || ![aps isKindOfClass:[NSDictionary class]]) return;

        id alert = aps[@"alert"];
        NSString *title = nil;
        NSString *message = nil;

        if ([alert isKindOfClass:[NSString class]]) {
            message = alert;
        } else if ([alert isKindOfClass:[NSDictionary class]]) {
            title = alert[@"title"];
            message = alert[@"body"];
        }

        if (title || message) {
            [DINOverlayManager presentNotificationFromRequest:nil withForcedTitle:title message:message bundleIdentifier:bundleIdentifier];
        }
    } @catch (NSException *e) {}
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
    dinReloadLandscapeOffsets();

    int token = 0;
    notify_register_dispatch("com.34306.shimastyle/prefsChanged",
        &token, dispatch_get_main_queue(), ^(int t) {
            [[DINPreferences sharedInstance] reloadPreferences];
            dinReloadLandscapeOffsets();
        });

    int testToken = 0;
    notify_register_dispatch("com.34306.shimastyle/testNotification",
        &testToken, dispatch_get_main_queue(), ^(int t) {
            UIImage *icon = dinAppIcon(@"com.apple.Preferences");
            if (!icon) icon = dinPlaceholderIcon(@"Settings");
            [[DINOverlayManager sharedInstance] showWithTitle:@"ShimaStyle"
                                                     message:@"Chào mừng bạn đến với ShimaStyle! Tinh chỉnh này sẽ mang trải nghiệm thông báo Dynamic Island tuyệt đẹp và mượt mà nhất lên thiết bị của bạn. Chúc bạn sử dụng vui vẻ!"
                                                     appName:@"Cài đặt"
                                                        icon:icon
                                            bundleIdentifier:@"com.apple.Preferences"];
        });

    %init;
}
