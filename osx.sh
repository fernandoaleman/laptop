#!/bin/sh

# Enable menu bar auto hide
defaults write NSGlobalDomain _HIHideMenuBar -bool true

# Enable dock auto hide
defaults write com.apple.dock autohide -bool true

# Disable dock delay
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -int 0

# Hide recent apps from Dock
defaults write com.apple.dock show-recents -bool false

# Disable auto arrange spaces
defaults write com.apple.dock mru-spaces -bool false

# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Disable auto-capitalization
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Disable adding period after double space
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Disable smart quotes
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# Always expand open/save dialogs
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Always show scroll bars
defaults write -g AppleShowScrollBars -string "Always"

# Set sidebar icon size to large
defaults write -g NSTableViewDefaultSizeMode -int 3

# Don't show open dialog when launching document apps
# via https://mas.to/@timac@mastodon.social/109851379681544342
defaults write -g NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false

# "Delay until repeat" setting in System Settings > Keyboard
# 15 (225 ms) is normal minimum configurable via UI
# via https://gist.github.com/hofmannsven/ff21749b0e6afc50da458bebbd9989c5
# Also see https://github.com/ZaymonFC/mac-os-key-repeat
defaults write -g InitialKeyRepeat -int 15

# "Key repeat rate" setting in System Settings > Keyboard
# Note that this is the interval in between repeats, so the lower this value the faster the repeats will be fired
# 2 (30 ms) is normal minimum configurable via UI
# via https://gist.github.com/hofmannsven/ff21749b0e6afc50da458bebbd9989c5
# Also see https://github.com/ZaymonFC/mac-os-key-repeat
defaults write -g KeyRepeat -int 2

# Always show full file extension in Finder
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show path bar in Finder
defaults write com.apple.finder ShowPathbar -bool true

# Don't display warning when changing file extension in Finder
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Set default location of new Finder windows to ~/Downloads
defaults write com.apple.finder NewWindowTarget -string "PfLo"
defaults write com.apple.finder NewWindowTargetPath -string "file://$HOME/Downloads"

# Set TextEdit default document format to plain text
defaults write com.apple.TextEdit RichText -bool false

# Set Activity Monitor update frequency to 2s
defaults write com.apple.ActivityMonitor UpdatePeriod -int 2

# Restart processes
for app in "Dock" "Finder"; do
  killall "$app" >/dev/null 2>&1
done
