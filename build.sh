#!/bin/bash

echo "Starting build..."

# 1. Kill existing Timer app if it's running
pkill -x "Timer" || true
pkill -x "TimerApp" || true

# 2. Compile the binary directly into the .app bundle
swiftc main.swift -o Timer.app/Contents/MacOS/TimerApp -framework Cocoa -framework Carbon

if [ $? -eq 0 ]; then
    echo "Compilation successful. Updating app..."
    
    # 3. Update icon if possible
    if [ -d "AppIcon.iconset" ]; then
        iconutil -c icns AppIcon.iconset -o Timer.app/Contents/Resources/AppIcon.icns
    fi

    # 4. Copy .app to /Applications (removing the old one first)
    rm -rf /Applications/Timer.app
    cp -R Timer.app /Applications/

    echo "App copied to /Applications/Timer.app"
    
    # 5. Automatically launch the updated app
    open /Applications/Timer.app
else
    echo "Compilation failed!"
    exit 1
fi
