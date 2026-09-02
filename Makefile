APP      := NotchGlow.app
BUNDLE   := build/$(APP)
BINARY   := build/NotchGlow-bin
SWIFT    := swiftc
SWIFTFLAGS := -O -target arm64-apple-macosx12.0

.PHONY: all run clean install icon

all: $(BUNDLE)/Contents/MacOS/NotchGlow $(BUNDLE)/Contents/Resources/AppIcon.icns

ICONSET := build/AppIcon.iconset
ICONSRC := build/icon-1024.png

$(ICONSRC): Sources/render-icon.swift
	@mkdir -p build
	swift -O $< $@

$(BUNDLE)/Contents/Resources/AppIcon.icns: $(ICONSRC)
	@mkdir -p $(ICONSET) $(BUNDLE)/Contents/Resources
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size $(ICONSRC) --out $(ICONSET)/icon_$${size}x$${size}.png >/dev/null; \
		sips -z $$((size*2)) $$((size*2)) $(ICONSRC) --out $(ICONSET)/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns $(ICONSET) -o $@

$(BINARY): Sources/main.swift
	@mkdir -p build
	$(SWIFT) $(SWIFTFLAGS) $< -o $@

$(BUNDLE)/Contents/MacOS/NotchGlow: $(BINARY) Info.plist
	@mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/NotchGlow
	cp Info.plist $(BUNDLE)/Contents/Info.plist

run: all
	open $(BUNDLE) --args --file ~/.notch-color --interval 10

install: all
	rm -rf /Applications/$(APP)
	cp -r $(BUNDLE) /Applications/$(APP)

clean:
	rm -rf build
