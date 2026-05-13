---
mode: agent
---
Act as an Expert iOS Reverse Engineer and Jailbreak UI Developer. I am building a complex iOS tweak in Theos/Logos (Objective-C) to completely replace the stock notification banners with a custom "Dynamic Island" style UI.

**Context:**
- Target Process: SpringBoard
- Target iOS Version: iOS 16+
- Primary Goal: Suppress the default notification banner and display a custom, animated pill-shaped UIWindow at the top of the screen.

**Technical Requirements:**
I need the boilerplate code for the following 3 parts:

1. **Intercepting the Notification:** Hook into the notification dispatcher (e.g., `NCNotificationDispatcher` or `SBNCAlertingController`) to extract the incoming `NCNotificationRequest` (to get the app icon, title, and message).
2. **Suppressing the Stock Banner:** Hook the necessary method to prevent the default `NCNotificationShortLookViewController` or standard banner from appearing on the screen.
3. **Drawing the Custom UI:** Provide a basic implementation of a custom `UIWindow` (level: `UIWindowLevelStatusBar` + 1) with a custom `UIView` (pill shape, black background, rounded corners). Include a simple spring animation (using `UIView animateWithDuration:delay:usingSpringWithDamping:`) to drop it down from the notch and dismiss it after 5 seconds.

**Constraints:**
- Ensure thread safety: All UI creation and animations must strictly run on the Main Thread.
- Memory Management: Handle the lifecycle of the custom UIWindow properly so it doesn't cause memory leaks when multiple notifications arrive.
- Add detailed comments so I can understand where to inject the extracted text and image data into the custom view.

Please generate the `Tweak.x` code.