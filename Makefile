APP := SmoothScroll.app
SOURCES := main.swift Settings.swift
SIGN_IDENTITY ?= -
SIGN_OPTIONS = $(if $(filter -,$(SIGN_IDENTITY)),,--options runtime --timestamp)

.PHONY: app test

app: test
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" .build
	swift scripts/icons.swift .build
	iconutil -c icns .build/AppIcon.iconset -o "$(APP)/Contents/Resources/AppIcon.icns"
	cp .build/MenuIcon*.png "$(APP)/Contents/Resources/"
	cp Info.plist "$(APP)/Contents/Info.plist"
	swiftc $(SOURCES) -o .build/SmoothScroll
	cp .build/SmoothScroll "$(APP)/Contents/MacOS/SmoothScroll"
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_OPTIONS) "$(APP)"
	codesign --verify --strict "$(APP)"

test:
	mkdir -p .build
	swiftc $(SOURCES) -o .build/SmoothScroll-test
	.build/SmoothScroll-test --self-test
