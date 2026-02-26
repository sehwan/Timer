#!/bin/bash

# 0. Kill existing Timer app if it's running
pkill -x "Timer" || true

# 1. Compile the binary directly into the .app bundle
# CFBundleExecutable is "TimerApp", so the binary MUST be named "TimerApp" inside "Contents/MacOS/"
swiftc main.swift -o Timer.app/Contents/MacOS/TimerApp -framework Cocoa -framework Carbon

# 2. Update icon if possible
if [ -d "AppIcon.iconset" ]; then
    iconutil -c icns AppIcon.iconset -o Timer.app/Contents/Resources/AppIcon.icns
fi

# 3. Copy .app to /Applications (removing the old one first)
rm -rf /Applications/Timer.app
cp -R Timer.app /Applications/

# 4. (Optional) Launch the app from /Applications
# open /Applications/Timer.app

# 5. Git operations
git add .
git commit -m "[Auto] build & deploy: $(date '+%Y-%m-%d %H:%M:%S')"
git push origin main
