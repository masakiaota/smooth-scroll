APP := SmoothScroll.app
SOURCES := main.swift Settings.swift
SIGN_IDENTITY ?=
SIGN_OPTIONS = $(if $(filter -,$(SIGN_IDENTITY)),,--options runtime --timestamp)

.PHONY: app test check-signing

app: check-signing
	$(MAKE) test
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" .build
	swift scripts/icons.swift .build
	iconutil -c icns .build/AppIcon.iconset -o "$(APP)/Contents/Resources/AppIcon.icns"
	cp .build/MenuIcon*.png "$(APP)/Contents/Resources/"
	cp Info.plist "$(APP)/Contents/Info.plist"
	swiftc $(SOURCES) -o .build/SmoothScroll
	cp .build/SmoothScroll "$(APP)/Contents/MacOS/SmoothScroll"
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_OPTIONS) "$(APP)"
	codesign --verify --strict "$(APP)"

check-signing:
	@test -n "$(SIGN_IDENTITY)" || { echo 'SIGN_IDENTITY に署名証明書を指定してください。一時署名は権限を失う場合があるため、必要な場合だけ SIGN_IDENTITY=- を明示してください。' >&2; exit 1; }

test:
	mkdir -p .build
	swiftc $(SOURCES) -o .build/SmoothScroll-test
	.build/SmoothScroll-test --self-test
