ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCamTestTweak
VCamTestTweak_FILES = Tweak.x
VCamTestTweak_CFLAGS = -fobjc-arc -Wno-error=deprecated-declarations
VCamTestTweak_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia CoreVideo CoreText QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
