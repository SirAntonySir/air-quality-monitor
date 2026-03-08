.PHONY: build install clean run

APP_NAME = Air Quality Monitor
BINARY_NAME = AirQualityMonitor
BUILD_DIR = build

build:
	swift build -c release
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS"
	@mkdir -p "$(BUILD_DIR)/$(APP_NAME).app/Contents/Resources"
	@cp ".build/release/$(BINARY_NAME)" "$(BUILD_DIR)/$(APP_NAME).app/Contents/MacOS/"
	@cp Info.plist "$(BUILD_DIR)/$(APP_NAME).app/Contents/"
	@codesign --force --sign - "$(BUILD_DIR)/$(APP_NAME).app"
	@echo "Built: $(BUILD_DIR)/$(APP_NAME).app"

install: build
	@cp -r "$(BUILD_DIR)/$(APP_NAME).app" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

run: build
	@open "$(BUILD_DIR)/$(APP_NAME).app"

clean:
	@rm -rf $(BUILD_DIR) .build
