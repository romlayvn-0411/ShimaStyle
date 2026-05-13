# ShimaReborn - Development Notes

## 📌 Code Structure Overview

```
Tweak.x
├── Imports & Private Class Interfaces
├── App Icon Helper Functions
├── Device State Detection
├── Image & Cache Management
├── Video Background Support
├── Landscape Offset Management
├── Native View Morphing Hook (NCNotificationShortLookViewController)
├── Gesture Handling System
├── Memory Management
├── SBSystemApertureContainerView Hook
├── Constructor & Initialization
└── Notification Dispatcher

DINNotificationView.h/m
├── Notification Style Definitions
├── UI Component Initialization
├── Layout Constraints
├── Marquee Animation
└── Advanced Animation Methods (NEW)
```

---

## 🔄 Execution Flow

### 1. **System Initialization** (`%ctor`)
```
┌─ dinInitPrefCache()
├─ dinIsDynamicIslandSupported() check
├─ [DINPreferences sharedInstance] reload
├─ dinReloadLandscapeOffsets()
├─ Memory warning handler registration
└─ Notification observer registration
```

### 2. **Notification Arrival**
```
┌─ NCNotificationDispatcher hook
├─ sharedDispatcher capture
├─ viewDidLayoutSubviews trigger
├─ Device lock check
├─ ScrollView detection
├─ Clip configuration
├─ Background setup
├─ Icon extraction (3 methods fallback)
└─ Aura color calculation & cache
```

### 3. **Notification Display**
```
┌─ containerView creation
├─ Background rendering (blur/image/video)
├─ DINNotificationView initialization
├─ Gesture recognizers addition
├─ Position calculation
├─ Frame setup
├─ Shadow/glow effects
├─ Haptic feedback
└─ Spring animation
```

### 4. **User Interaction**
```
┌─ Swipe gesture detected
├─ din_dismissNotification called
├─ Scale animation (0.5x)
├─ Alpha fade-out
└─ Removal from superview
```

---

## 🎯 Key Hooks & Extensions

### NCNotificationShortLookViewController
- `preferredContentSizeWithPresentationSize:containerSize:` - Ensure height
- `viewDidLayoutSubviews` - Main customization point
- `din_dismissNotification` - Swipe handler
- `din_tapNotification` - Tap handler
- `gestureRecognizerShouldBegin:` - Delegate
- `gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:` - Multi-gesture support

### SBSystemApertureContainerView
- `initWithInterfaceElementIdentifier:` - Add custom background
- `layoutSubviews` - Update background clipping

### NCNotificationDispatcher
- `init` - Capture dispatcher
- `initWithAlertingController:` - Alternative capture
- `initWithNotificationDestinations:alertingController:` - Alternative capture
- `postNotificationWithRequest:` - Main dispatcher hook

---

## 💾 Cache Management

### 1. **Image Caches**
```objc
static NSCache *sAppIconCache         // Bundle ID -> UIImage
static NSCache *sAuraColorCache       // UIImage -> UIColor
static NSCache *sImageCache           // Path -> UIImage (GIF/PNG/etc)
static NSCache *sAppNameCache         // Bundle ID -> NSString
```

**Size Limits**: Default NSCache (unbounded but managed by system)
**Cleanup**: Automatic on memory warning + manual in dinHandleMemoryWarning()

### 2. **Preference Cache**
```objc
static NSMutableDictionary *sDINPrefCache
static dispatch_queue_t sDINPrefCacheQueue
```

**Thread-Safety**: Serial dispatch queue
**Operations**: Read/write preference values without main thread blocking

### 3. **Static Variables**
```objc
static CGFloat sLandscapeXOffset  // Cached landscape X offset
static CGFloat sLandscapeYOffset  // Cached landscape Y offset
static __weak id sharedDispatcher // Weak reference to dispatcher
```

---

## 🎨 Animation Pipeline

### 1. **Initial Appearance**
```
Initial State:
  - scale: 0.6
  - alpha: 0.0
  - shadowOpacity: 0.0

Animation (0.45s with spring):
  - scale → 1.0
  - alpha → 1.0
  - shadowOpacity → 0.9

Dependencies:
  - prefs.animationDuration
  - prefs.auraGlowEnabled
  - UIViewAnimationOptionCurveEaseOut
  - usingSpringWithDamping: 0.65
  - initialSpringVelocity: 1.2
```

### 2. **Marquee Scrolling**
```
Trigger: After 0.5s delay from appearance
Scroll Duration: MAX(2.5s, distance / 35pt/s)
Animation: Linear curve, continuous
Direction: Left (-distance)
Easing: UIViewAnimationOptionCurveLinear
```

### 3. **Dismissal**
```
Duration: 0.5 * animationDuration
Animation: EaseIn curve
- scale → 0.5
- alpha → 0.0
- Completion: Remove from superview
Feedback: UIImpactFeedbackStyleRigid (on appear)
          UIImpactFeedbackStyleMedium (on tap)
```

### 4. **Pulsing Effect (NEW)**
```
Parameters:
  - From: opacity 0.7
  - To: opacity 1.0
  - EaseInEaseOut curve
  - Auto-reverse
  - Repeat infinite
```

---

## 🔐 Thread Safety Guarantees

### Main Thread Only
- All UI updates (animations, property changes)
- All gesture handler callbacks
- All view hierarchy modifications
- CADisplayLink-based rendering

### Background Thread Safe
- Preference cache reads/writes (via dispatch_queue)
- Image cache access (NSCache is thread-safe)
- File I/O operations (GIF parsing, image loading)

### Weak References
- `__weak id sharedDispatcher` - Prevent retain cycles
- Associated objects with OBJC_ASSOCIATION_RETAIN_NONATOMIC

---

## 📊 Performance Characteristics

### Icon Loading Hierarchy
```
Method 1: SBIconController (FASTEST - RAM cached)
  └─ Fallback to Method 2 if unavailable

Method 2: UIImage Private API (MEDIUM - File system)
  └─ Fallback to Method 3 if unavailable

Method 3: IconServices (SLOWEST - XPC call)
  └─ Fallback to placeholder if all fail
```

### Image Cache Lookup Chain
```
┌─ Check app icon cache
├─ If miss: Try SBIconController → Cache
├─ If miss: Try UIImage._applicationIconImageForBundleIdentifier → Cache
├─ If miss: Try IconServices → Cache
└─ If miss: Generate placeholder → Cache
```

### Aura Color Calculation
```
1. Check aura color cache (instant)
2. If miss:
   - Create 1x1 bitmap context
   - Draw image with interpolation = low
   - Extract RGBA values
   - Calculate with alpha multiplier
   - Return UIColor
   - Store in cache
```

**Typical Time**: 0.1ms cached, 2-3ms uncached

---

## 🛡️ Error Handling

### Graceful Degradation
```objc
if (!image) return [UIColor clearColor];           // Null safety
if (context) { CGContextRelease(context); }       // Leak prevention
if (!appName) appName = @"Notification";          // Default fallback
if (!icon) icon = dinPlaceholderIcon(appName);    // Fallback icon
```

### Try-Catch Blocks
```objc
@try {
    // Video playback operations
    // XPC calls (IconServices)
    // Runtime method invocations
} @catch (NSException *e) {
    // Gracefully continue with fallback
}
```

### Selector Checks
```objc
if ([object respondsToSelector:@selector(method:)]) {
    // Safe method invocation
}
```

---

## 📦 New Components Added

### DINNotificationView Extensions
```objc
// Animation methods
- addPulsingAnimationWithDuration:
- stopPulsingAnimation
- applyVibrantBlurEffect
- updateAppearanceForTraitCollection:
```

### Gesture System
```objc
dinAddDismissGesture()                              // Setup function
- din_dismissNotification                          // Swipe handler
- din_tapNotification                              // Tap handler
- gestureRecognizerShouldBegin:                   // Delegate
- gestureRecognizer:shouldRecognizeSimultaneously // Multi-gesture
```

### Utility Functions
```objc
dinIsDynamicIslandSupported()                      // Device check
dinGetDeviceScale()                                // Resolution query
dinIsTweakEnabled()                                // Feature check
dinOptimizeShadowPerformance()                     // Render optimization
dinInitPrefCache()                                 // Initialization
dinHandleMemoryWarning()                           // Memory cleanup
```

---

## 🚀 Optimization Techniques Used

1. **Caching**: Multi-level caching (icon, color, image, app name)
2. **Lazy Loading**: Defer operations until needed
3. **Thread Pool**: Use dispatch_queue for background work
4. **Static Initialization**: dispatch_once for one-time setup
5. **Weak References**: Prevent retain cycles
6. **Path Pre-rendering**: Shadow path calculation
7. **Low Interpolation**: Image sampling quality set to low
8. **One-Time Setup**: Configuration flags to run setup once
9. **Object Reuse**: Gesture recognizers attached once
10. **Early Exit**: Return early on error conditions

---

## ✅ Testing Checklist

- [ ] App icons load correctly on different bundle IDs
- [ ] Aura glow color matches app icon dominant color
- [ ] Haptic feedback triggers on appear and tap
- [ ] Swipe gesture dismisses notification smoothly
- [ ] Marquee scrolling works for long text
- [ ] Memory warning clears caches without crash
- [ ] Dark mode appearance updates correctly
- [ ] Multiple notifications stack without conflicts
- [ ] Video background plays smoothly
- [ ] Landscape orientation works correctly
- [ ] Dynamic Island detection accurate
- [ ] No memory leaks after 100+ notifications

---

*Development Document - ShimaReborn*
*Last Updated: 13 May 2026*
