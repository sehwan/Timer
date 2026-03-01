#!/bin/bash

TARGET="main.swift"
BUILD_SCRIPT="./build.sh"

# Ensure build script is executable
chmod +x "$BUILD_SCRIPT"

if [ ! -f "$TARGET" ]; then
    echo "Error: $TARGET not found!"
    exit 1
fi

echo "Watching $TARGET for modifications..."
echo "Press [Ctrl+C] to stop."

LAST_MODIFIED=$(stat -f "%m" "$TARGET")

while true; do
    CURRENT_MODIFIED=$(stat -f "%m" "$TARGET")
    
    if [ "$CURRENT_MODIFIED" -ne "$LAST_MODIFIED" ]; then
        echo -e "\n[$TARGET modified at $(date +%T)]"
        $BUILD_SCRIPT
        LAST_MODIFIED=$CURRENT_MODIFIED
        
        # In case the build takes a second, update timestamp again to prevent double builds
        LAST_MODIFIED=$(stat -f "%m" "$TARGET")
    fi
    
    sleep 1 # check every 1 second
done
