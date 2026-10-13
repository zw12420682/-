ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HotspotAutoOff
HotspotAutoOff_FILES = Sources/Tweak.m Sources/HAOController.m Sources/HAODiagnostics.m Sources/HAOHotspot.m Sources/HAOPreferences.m Sources/HAOSharing.m
HotspotAutoOff_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-error
HotspotAutoOff_FRAMEWORKS = Foundation SystemConfiguration
HotspotAutoOff_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
