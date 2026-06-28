#!/bin/bash

# Terminal color modification script
# Changes the blue color in Terminal.app to a lighter shade

echo "Modifying Terminal.app colors..."

# Backup the original plist file
if [[ -f ~/Library/Preferences/com.apple.Terminal.plist ]]; then
    cp ~/Library/Preferences/com.apple.Terminal.plist ~/Library/Preferences/com.apple.Terminal.plist.backup.$(date +%Y%m%d_%H%M%S)
    echo "✅ Backed up original Terminal.plist"
    plutil -convert xml1 ~/Library/Preferences/com.apple.Terminal.plist
else
    echo "⚠️  Terminal.plist not found; defaults will create preferences as needed"
fi

# Create a temporary file with the modified colors
cat > /tmp/terminal_colors.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Window Settings</key>
    <dict>
        <key>Basic</key>
        <dict>
            <key>ANSIBlueColor</key>
            <data>
            AAAAAA==
            </data>
            <key>ANSIBrightBlueColor</key>
            <data>
            AAAAAA==
            </data>
        </dict>
    </dict>
</dict>
</plist>
EOF

# Use defaults command to modify the blue color for Homebrew profile
# This sets the blue color to a lighter shade (RGB: 0.6, 0.8, 1.0)
defaults write com.apple.Terminal "Window Settings.Homebrew.ANSIBlueColor" -array 0.6 0.8 1.0
defaults write com.apple.Terminal "Window Settings.Homebrew.ANSIBrightBlueColor" -array 0.8 0.9 1.0

echo "✅ Modified Terminal blue colors to lighter shades"
echo "⚠️  Please restart Terminal.app for changes to take effect"
echo "💡 You can also manually adjust colors in Terminal → Preferences → Profiles → Text → ANSI Colors"
