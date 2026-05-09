FINALPACKAGE = 1
TARGET := iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ShimaStyle
$(TWEAK_NAME)_FILES = Tweak.x DINNotificationView.m DINPreferences.m
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-nullability-completeness
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreServices AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += dynamicislandnotifyprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
