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

@interface SBApplication : NSObject
- (NSString *)displayName;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface SBSystemApertureContainerView : UIView
@end

@interface NCNotificationShortLookViewController : UIViewController
- (id)notificationRequest;
@end

@interface NCNotificationDispatcher : NSObject
- (void)postNotificationWithRequest:(id)arg1;
@end

// ============================================================================
// MARK: - App Icon Helper
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
        dispatch_sync(dispatch_get_main_queue(), getLockBlock);
    }
    return isLocked;
}

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
    CFPreferencesAppSynchronize((CFStringRef)@"com.romlayvn.shimareborn");
    NSNumber *xVal = (NSNumber *)CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)@"landscapeXOffset", (CFStringRef)@"com.romlayvn.shimareborn"));
    sLandscapeXOffset = xVal ? [xVal floatValue] : 0.0;
    
    NSNumber *yVal = (NSNumber *)CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)@"landscapeYOffset", (CFStringRef)@"com.romlayvn.shimareborn"));
    sLandscapeYOffset = yVal ? [yVal floatValue] : 0.0;
}

// ============================================================================
// MARK: - Native View Morphing (Hướng 2)
// ============================================================================

%hook NCNotificationShortLookViewController

- (CGSize)preferredContentSizeWithPresentationSize:(CGSize)arg1 containerSize:(CGSize)arg2 {
    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (prefs.enabled && prefs.notificationEnabled && !dinIsDeviceLockedOrInCoverSheet()) {
        return CGSizeMake(arg1.width, 80); // Đảm bảo BannerKit cấp đủ chiều cao cho ShimaStyle bung nở
    }
    return %orig;
}

- (void)viewWillLayoutSubviews {
    %orig;

    DINPreferences *prefs = [DINPreferences sharedInstance];
    if (!prefs.enabled || !prefs.notificationEnabled) return;

    id request = [self respondsToSelector:@selector(notificationRequest)] ? [self performSelector:@selector(notificationRequest)] : nil;
    if (!request) return;

    // Bỏ qua, trả lại giao diện gốc nếu đang ở Màn hình khóa
    if (dinIsDeviceLockedOrInCoverSheet()) return;

    // Bỏ qua nếu đang ở Trung tâm thông báo (Notification Center thường đặt Banner trong một UIScrollView)
    UIView *superview = self.view.superview;
    BOOL inScrollView = NO;
    while (superview) {
        if ([superview isKindOfClass:[UIScrollView class]]) {
            inScrollView = YES; break;
        }
        superview = superview.superview;
    }
    if (inScrollView) return;
    
    // Làm tàng hình toàn bộ Khung nền (PlatterView) và Bóng đổ nguyên bản của Apple
    UIView *platterView = self.view.superview;
    if (platterView) {
        platterView.clipsToBounds = NO;
        platterView.backgroundColor = [UIColor clearColor];
        platterView.layer.shadowOpacity = 0;
        for (UIView *sub in platterView.subviews) {
            if ([NSStringFromClass([sub class]) containsString:@"Background"] || [NSStringFromClass([sub class]) containsString:@"Shadow"]) {
                sub.alpha = 0.01;
            }
        }
    }

    // Làm tàng hình nền nguyên bản của Apple (Để lại hiệu ứng đổ bóng ảo diệu của riêng ta)
    self.view.backgroundColor = [UIColor clearColor];
    self.view.layer.shadowOpacity = 0;
    self.view.clipsToBounds = NO; // Cho phép khung của ta lấn ra khỏi giới hạn của BannerKit (tràn lên Tai thỏ)

    // Giấu mọi thứ có sẵn bên trong Banner (Tiêu đề gốc, Icon gốc)
    for (UIView *v in self.view.subviews) {
        if (v.tag != 34306) {
            v.alpha = 0.01; // Giữ alpha 0.01 thay vì hidden = YES để cử chỉ vuốt/chạm vẫn hoạt động 100%
        }
    }

    UIView *containerView = [self.view viewWithTag:34306];
    DINNotificationView *notifView = [containerView viewWithTag:34307];

    // Trích xuất dữ liệu thông báo
    NCNotificationContent *content = [request respondsToSelector:@selector(content)] ? [request performSelector:@selector(content)] : nil;
    NSString *title = [content respondsToSelector:@selector(title)] ? [content performSelector:@selector(title)] : nil;
    NSString *subtitle = [content respondsToSelector:@selector(subtitle)] ? [content performSelector:@selector(subtitle)] : nil;
    NSString *message = [content respondsToSelector:@selector(message)] ? [content performSelector:@selector(message)] : nil;
    NSString *bundleID = [request respondsToSelector:@selector(sectionIdentifier)] ? [request performSelector:@selector(sectionIdentifier)] : nil;

    NSString *finalTitle = title;
    NSString *finalMessage = message;
    if (!finalMessage && subtitle) {
        finalMessage = subtitle;
    } else if (title && subtitle) {
        finalTitle = [NSString stringWithFormat:@"%@ - %@", title, subtitle];
    }

    if (!containerView) {
        containerView = [[UIView alloc] init];
        containerView.tag = 34306;
        containerView.clipsToBounds = YES;
        containerView.layer.cornerCurve = kCACornerCurveContinuous;
        containerView.userInteractionEnabled = NO; // Cho phép thao tác chạm đi xuyên qua lớp khung này truyền cho Apple

        // Vẽ nền (Background)
        if (prefs.customBackgroundEnabled && prefs.customBackgroundImagePath) {
            NSString *bgPath = prefs.customBackgroundImagePath;
            if (dinIsVideoFile(bgPath)) {
                UIView *vidBg = dinCreateVideoBgView(bgPath, prefs.backgroundOpacity);
                vidBg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [containerView addSubview:vidBg];
            } else {
                UIImage *bgImage = dinGetCachedCustomImage(bgPath);
                if (bgImage) {
                    UIImageView *iv = [[UIImageView alloc] initWithImage:bgImage];
                    iv.contentMode = UIViewContentModeScaleAspectFill;
                    iv.alpha = prefs.backgroundOpacity;
                    iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    [containerView addSubview:iv];
                } else {
                    containerView.backgroundColor = [UIColor blackColor];
                }
            }
        } else {
            // Đổi từ nền Đen đặc sang nền Kính Mờ (Blur) tự động thích ứng với chế độ Sáng/Tối
            UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
            blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [containerView addSubview:blurView];
        }

        // Lấy tên App
        NSString *appName = nil;
        static NSCache *sAppNameCache = nil;
        static dispatch_once_t onceTokenName;
        dispatch_once(&onceTokenName, ^{ sAppNameCache = [[NSCache alloc] init]; });
        if (bundleID) {
            appName = [sAppNameCache objectForKey:bundleID];
            if (!appName) {
                Class s_SBAppControllerClass = objc_lookUpClass("SBApplicationController");
                id appController = ((id (*)(Class, SEL))objc_msgSend)(s_SBAppControllerClass, sel_registerName("sharedInstance"));
                if (appController && [appController respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
                    id app = [appController performSelector:@selector(applicationWithBundleIdentifier:) withObject:bundleID];
                    if (app && [app respondsToSelector:@selector(displayName)]) appName = [app performSelector:@selector(displayName)];
                }
                if (appName) [sAppNameCache setObject:appName forKey:bundleID];
            }
        }

        // Lấy Icon
        UIImage *icon = nil;
        
        // Cố gắng "móc" Icon trực tiếp từ UI nguyên bản của Apple để đạt độ chính xác 100%
        NSMutableArray *viewsToSearch = [NSMutableArray arrayWithObject:self.view];
        while (viewsToSearch.count > 0 && !icon) {
            UIView *v = viewsToSearch.firstObject;
            [viewsToSearch removeObjectAtIndex:0];
            if (v.tag == 34306) continue;
            if ([v isKindOfClass:[UIImageView class]]) {
                UIImage *img = ((UIImageView *)v).image;
                if (img && img.size.width >= 20 && img.size.width == img.size.height) { // Tăng size lên 20 để tránh bắt nhầm nút Đóng/Mở rộng
                    icon = img;
                    break;
                }
            }
            [viewsToSearch addObjectsFromArray:v.subviews];
        }
        
        // Nếu không móc được thì mới dùng hàm fallback
        if (!icon) {
            if ([content respondsToSelector:@selector(icons)] && [[content performSelector:@selector(icons)] isKindOfClass:[NSArray class]]) {
                NSArray *icons = [content performSelector:@selector(icons)];
                if (icons.count > 0) icon = icons.firstObject;
            } else if ([content respondsToSelector:@selector(icon)]) {
                icon = [content performSelector:@selector(icon)];
            }
        }
        if (!icon) icon = dinAppIcon(bundleID);
        if (!icon) icon = dinPlaceholderIcon(appName);

        // Gắn ShimaStyle UI vào
        notifView = [[DINNotificationView alloc] initWithTitle:finalTitle message:finalMessage appName:appName icon:icon style:(DINNotificationStyle)prefs.notificationStyle textColorStyle:prefs.textColorStyle];
        notifView.tag = 34307;
        notifView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        notifView.userInteractionEnabled = NO;
        [containerView addSubview:notifView];

        [self.view addSubview:containerView];
        
        // Thêm hiệu ứng Bung mở (Spring Bouncy) mượt mà cho lần hiển thị đầu tiên
        containerView.transform = CGAffineTransformMakeScale(0.6, 0.6);
        containerView.alpha = 0.0;
        [UIView animateWithDuration:prefs.animationDuration delay:0 usingSpringWithDamping:0.65 initialSpringVelocity:1.2 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut animations:^{
            containerView.transform = CGAffineTransformIdentity;
            containerView.alpha = 1.0;
        } completion:nil];

        // Khởi động chữ chạy (Marquee)
        if ([notifView respondsToSelector:@selector(startMarquee)]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [notifView startMarquee];
            });
        }
    } else if ([notifView respondsToSelector:@selector(updateTitle:message:appName:icon:count:)]) {
        // Nếu BannerKit nạp lại View để hiển thị nội dung mới, tự động cập nhật text
        [notifView updateTitle:finalTitle message:finalMessage appName:nil icon:nil count:1];
    }

    // TÍNH TOÁN KHUNG HIỂN THỊ (DYNAMIC ISLAND MORPHING)
    CGFloat w = 320.0;
    CGFloat h = 72.0;
    if (prefs.notificationStyle == 1) { w = 220.0; h = 56.0; }
    else if (prefs.notificationStyle == 2) { w = 120.0; h = 64.0; }
    else {
        if (notifView) {
            CGFloat titleW = [notifView.titleLabel intrinsicContentSize].width;
            CGFloat msgW = [notifView.messageLabel intrinsicContentSize].width;
            CGFloat desiredWidth = MAX(240.0, MAX(titleW, msgW) + 68.0);
            w = MIN(desiredWidth, UIScreen.mainScreen.bounds.size.width - 16.0);
        }
    }

    BOOL isLandscape = UIScreen.mainScreen.bounds.size.width > UIScreen.mainScreen.bounds.size.height;
    CGFloat yOffset = isLandscape ? sLandscapeYOffset : prefs.notificationYOffset;
    CGFloat xOffset = isLandscape ? sLandscapeXOffset : 0.0;

    // Căn giữa viên thuốc so với khung ẩn của BannerKit
    CGFloat centerX = (self.view.bounds.size.width - w) / 2.0 + xOffset;
    
    // Lực đẩy Y âm (-15) giúp viên thuốc nhảy lên che khuất tai thỏ (Do BannerKit mặc định đặt nó hơi thấp)
    CGFloat defaultUpwardShift = isLandscape ? 0.0 : -15.0; 
    
    containerView.frame = CGRectMake(centerX, defaultUpwardShift + yOffset, w, h);
    containerView.layer.cornerRadius = h / 2.0;
}

%end

// ============================================================================
// MARK: - Test Notification Dispatcher Grabber
// ============================================================================

static id sharedDispatcher = nil;

%hook NCNotificationDispatcher

- (id)init {
    sharedDispatcher = %orig;
    return sharedDispatcher;
}

- (id)initWithAlertingController:(id)arg1 {
    sharedDispatcher = %orig;
    return sharedDispatcher;
}

- (id)initWithNotificationDestinations:(id)arg1 alertingController:(id)arg2 {
    sharedDispatcher = %orig;
    return sharedDispatcher;
}

- (void)postNotificationWithRequest:(id)arg1 {
    sharedDispatcher = self; // Bắt lấy Dispatcher mỗi khi có 1 thông báo thật bay qua
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
    dinReloadLandscapeOffsets();

    int token = 0;
    notify_register_dispatch("com.romlayvn.shimareborn/prefsChanged",
        &token, dispatch_get_main_queue(), ^(int t) {
            [[DINPreferences sharedInstance] reloadPreferences];
            dinReloadLandscapeOffsets();
        });

    int testToken = 0;
    notify_register_dispatch("com.romlayvn.shimareborn/testNotification",
        &testToken, dispatch_get_main_queue(), ^(int t) {
            if (sharedDispatcher) {
                @try {
                    Class mutContentClass = objc_getClass("NCMutableNotificationContent");
                    id content = [[mutContentClass alloc] init];
                    if ([content respondsToSelector:@selector(setHeader:)]) [content performSelector:@selector(setHeader:) withObject:@"ShimaReborn"];
                    if ([content respondsToSelector:@selector(setTitle:)]) [content performSelector:@selector(setTitle:) withObject:@"ShimaReborn"];
                    if ([content respondsToSelector:@selector(setMessage:)]) [content performSelector:@selector(setMessage:) withObject:@"Tuyệt vời! Hiển thị Native đang hoạt động hoàn hảo!"];

                    Class mutRequestClass = objc_getClass("NCMutableNotificationRequest");
                    id request = [[mutRequestClass alloc] init];
                    if ([request respondsToSelector:@selector(setSectionIdentifier:)]) [request performSelector:@selector(setSectionIdentifier:) withObject:@"com.apple.Preferences"];
                    if ([request respondsToSelector:@selector(setNotificationIdentifier:)]) [request performSelector:@selector(setNotificationIdentifier:) withObject:[[NSUUID UUID] UUIDString]];
                    if ([request respondsToSelector:@selector(setContent:)]) [request performSelector:@selector(setContent:) withObject:content];
                    if ([request respondsToSelector:@selector(setTimestamp:)]) [request performSelector:@selector(setTimestamp:) withObject:[NSDate date]];
                    
                    // Bắt buộc phải có Options và Destinations trên iOS 16 thì thông báo mới được phép bung ra
                    Class mutOptionsClass = objc_getClass("NCMutableNotificationOptions");
                    if (mutOptionsClass) {
                        id options = [[mutOptionsClass alloc] init];
                        if ([options respondsToSelector:@selector(setPreemptsPresentedNotification:)]) [options performSelector:@selector(setPreemptsPresentedNotification:) withObject:@(YES)];
                        if ([request respondsToSelector:@selector(setOptions:)]) [request performSelector:@selector(setOptions:) withObject:options];
                    }
                    if ([request respondsToSelector:@selector(setDestinations:)]) {
                        [request performSelector:@selector(setDestinations:) withObject:[NSSet setWithObject:@"SBNotificationDestinationBanner"]];
                    }

                    if ([sharedDispatcher respondsToSelector:@selector(postNotificationWithRequest:)]) {
                        [sharedDispatcher performSelector:@selector(postNotificationWithRequest:) withObject:request];
                    }
                } @catch (NSException *e) {}
            } else {
                // Fallback nếu Dispatcher chưa kịp nạp vào RAM
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ShimaReborn" message:@"Hệ thống chưa tải xong bộ nhận thông báo. Hãy chờ vài giây hoặc nhờ ai đó gửi 1 tin nhắn thật để Tweak ghi nhớ hệ thống!" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Đã hiểu" style:UIAlertActionStyleDefault handler:nil]];
                    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
                    if (keyWindow && keyWindow.rootViewController) {
                        [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
                    }
                });
            }
        });

    %init;
}
