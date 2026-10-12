include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = HotspotAutoOffPrefs
HotspotAutoOffPrefs_FILES = HAOPreferences.m
HotspotAutoOffPrefs_CFLAGS = -fobjc-arc -Wall -Wextra
HotspotAutoOffPrefs_FRAMEWORKS = UIKit Foundation
HotspotAutoOffPrefs_PRIVATE_FRAMEWORKS = Preferences
HotspotAutoOffPrefs_INSTALL_PATH = /Library/PreferenceBundles
HotspotAutoOffPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk
