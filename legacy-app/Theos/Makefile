PACKAGE_NAME = com.example.nvcam
ARCHS = arm64 arm64e
TARGET = iphone:clang:15.0:15.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = NVcam
NVcam_FILES = Tweak.xm
NVcam_FRAMEWORKS = Foundation AVFoundation CoreMedia
include $(THEOS_MAKE_PATH)/tweak.mk
after-install::
	@install.exec "killall -9 SpringBoard"
