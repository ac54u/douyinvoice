ARCHS = arm64
# 巨魔只支持 arm64 (因为大部分是非越狱机)，arm64e 也可以但没必要
TARGET := iphone:clang:14.5:13.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DouyinHook

DouyinHook_FILES = Tweak.x
# 强制链接 C++ 库，忽略报错
DouyinHook_CFLAGS = -fobjc-arc -Wno-error -Wno-deprecated-declarations
DouyinHook_LDFLAGS = -lc++

# 确保包含这些框架
DouyinHook_FRAMEWORKS = UIKit Foundation AVFoundation CoreGraphics QuartzCore MobileCoreServices

include $(THEOS_MAKE_PATH)/tweak.mk