APP_NAME := VoiceInput
APP_BUNDLE := $(APP_NAME).app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DMG := $(APP_NAME)-$(VERSION).dmg

.PHONY: build run install clean dmg

build:
	swift build -c release
	$(eval BUILD_DIR := $(shell swift build -c release --show-bin-path))
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Assets/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	cp Info.plist $(APP_BUNDLE)/Contents/
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: build
	open $(APP_BUNDLE)

install: build
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE) $(APP_NAME)-*.dmg

# Distributable disk image: app + /Applications symlink, compressed.
dmg: build
	rm -f $(DMG)
	rm -rf .dmg-staging
	mkdir .dmg-staging
	cp -r $(APP_BUNDLE) .dmg-staging/
	ln -s /Applications .dmg-staging/Applications
	hdiutil create -volname "$(APP_NAME) $(VERSION)" -srcfolder .dmg-staging \
		-ov -format UDZO $(DMG)
	rm -rf .dmg-staging
	@echo "Built $(DMG)"
