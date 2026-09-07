APP := SmoothScroll.app
CONTENTS := $(APP)/Contents
BINARY := $(CONTENTS)/MacOS/SmoothScroll

.PHONY: app test

app: test
	mkdir -p $(CONTENTS)/MacOS
	cp Info.plist $(CONTENTS)/Info.plist
	swiftc smooth-scroll.swift -o $(BINARY)
	codesign --force --sign - $(APP)

test:
	swiftc smooth-scroll.swift -o smooth-scroll.test
	./smooth-scroll.test --self-test
	rm smooth-scroll.test
