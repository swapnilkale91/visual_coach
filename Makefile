APP_NAME   = VisualCoach
BUILD_DIR  = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BINARY     = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
SOURCES    = $(wildcard Sources/*.m)
HEADERS    = $(wildcard Sources/*.h)
FRAMEWORKS = -framework Cocoa -framework Carbon -framework ScreenCaptureKit \
             -framework Vision -framework CoreGraphics -framework Security
CFLAGS     = -fobjc-arc -fmodules -mmacosx-version-min=14.0 -Wall \
             -Wno-deprecated-declarations

all: $(BINARY)

$(BINARY): $(SOURCES) $(HEADERS) Resources/Info.plist
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	clang $(CFLAGS) $(SOURCES) -o $(BINARY) $(FRAMEWORKS)
	codesign --force --sign - $(APP_BUNDLE)

run: all
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run clean
