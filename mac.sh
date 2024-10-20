#!/bin/sh
# ft=shell

# shellcheck disable=SC3043

fancy_echo() {
  local fmt="$1"
  shift

  # shellcheck disable=SC2059
  printf "\\n$fmt\\n\\n" "$@"
}

append_to_zshrc() {
  local text="$1" zshrc
  local skip_new_line="${2:-0}"

  if [ -w "$HOME/.zshrc.local" ]; then
    zshrc="$HOME/.zshrc.local"
  else
    zshrc="$HOME/.zshrc"
  fi

  if ! grep -Fqs "$text" "$zshrc"; then
    if [ "$skip_new_line" -eq 1 ]; then
      printf "%s\\n" "$text" >>"$zshrc"
    else
      printf "\\n%s\\n" "$text" >>"$zshrc"
    fi
  fi
}

# shellcheck disable=SC2154
trap 'ret=$?; test $ret -ne 0 && printf "failed\n\n" >&2; exit $ret' EXIT

set -e

if [ ! -f "$HOME/.zshrc" ]; then
  touch "$HOME/.zshrc"
fi

if [ ! -d "$HOME/.bin/" ]; then
  mkdir "$HOME/.bin"
fi

# shellcheck disable=SC2016
append_to_zshrc 'export PATH="$HOME/.bin:$PATH"'

arch="$(uname -m)"

if [ "$arch" = "arm64" ]; then
  HOMEBREW_PREFIX="/opt/homebrew"
else
  HOMEBREW_PREFIX="/usr/local"
fi

update_shell() {
  local shell_path
  shell_path="$(command -v zsh)"

  fancy_echo "Changing your shell to zsh ..."
  if ! grep "$shell_path" /etc/shells >/dev/null 2>&1; then
    fancy_echo "Adding '$shell_path' to /etc/shells"
    sudo sh -c "echo $shell_path >> /etc/shells"
  fi
  sudo chsh -s "$shell_path" "$USER"
}

case "$SHELL" in
*/zsh)
  if [ "$(command -v zsh)" != "$HOMEBREW_PREFIX/bin/zsh" ]; then
    update_shell
  fi
  ;;
*)
  update_shell
  ;;
esac

if [ "$arch" = "arm64" ]; then
  if ! pkgutil --pkg-info=com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    fancy_echo 'Installing Rosetta ...'
    softwareupdate --install-rosetta --agree-to-license
  fi
fi

if ! command -v brew >/dev/null; then
  fancy_echo "Installing Homebrew ..."
  /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  append_to_zshrc "eval \"\$($HOMEBREW_PREFIX/bin/brew shellenv)\""

  export PATH="$HOMEBREW_PREFIX/bin:$PATH"
fi

fancy_echo "Updating homebrew formulae ..."
brew update --force # https://github.com/Homebrew/brew/issues/1151
brew bundle --file=- <<EOF
# Fonts
cask "font-jetbrains-mono-nerd-font"

# Unix
brew "awscli"
brew "bash"
brew "bat"
brew "curl"
brew "diff-so-fancy"
brew "eza"
brew "fastfetch"
brew "fd"
brew "fzf"
brew "git"
brew "jq"
brew "lazygit"
brew "lf"
brew "ncdu"
brew "nmap"
brew "nvim"
brew "openssl"
brew "rcm"
brew "reattach-to-user-namespace"
brew "ripgrep"
brew "shellcheck"
brew "starship"
brew "tldr"
brew "tmux"
brew "tree"
brew "wget"
brew "zoxide"
brew "zsh"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"

# GitHub
brew "gh"

# Image manipulation
brew "imagemagick"

# PDF Rendering
cask "wkhtmltopdf"

# Programming language prerequisites and package managers
brew "coreutils"
brew "libyaml" # should come after openssl
brew "readline"
brew "yarn"
brew "zlib"

# Databases
brew "libpq", link: true

# Mac apps
cask "1password"
cask "alacritty"
cask "appcleaner"
cask "chatgpt"
cask "discord"
cask "docker"
cask "espanso"
cask "google-chrome"
cask "flycut"
cask "loom"
cask "macx-youtube-downloader"
cask "raindropio"
cask "rectangle"
cask "reflex"
cask "slack"
cask "sync"
EOF

append_to_zshrc "eval \"\$(starship init zsh)\"" 1
append_to_zshrc "eval \"\$(zoxide init zsh)\"" 1

fancy_echo "Installing sesh ..."
brew install joshmedeski/sesh/sesh

fancy_echo "Installing gitmux ..."
brew tap arl/arl
brew install gitmux

fancy_echo "Installing i2cssh ..."
brew install wouterdebie/repo/i2cssh

if [ ! -d "$HOME/.config/tmux/plugins" ]; then
  mkdir -p "$HOME/.config/tmux/plugins"
fi

if [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
  git clone "https://github.com/tmux-plugins/tpm" "$HOME/.config/tmux/plugins/tpm"
fi

if [ ! -d "$HOME/.config/alacritty" ]; then
  mkdir "$HOME/.config/alacritty"
fi

if [ ! -d "$HOME/.config/alacritty/catppuccin" ]; then
  git clone "https://github.com/catppuccin/alacritty.git" "$HOME/.config/alacritty/catppuccin"
fi

if [ ! -d "$HOME/.config/espanso" ]; then
  mkdir "$HOME/.config/espanso"
fi

if [ ! -d "$HOME/Library/Application Support/espanso" ] && [ ! -L "$HOME/Library/Application Support/espanso" ]; then
  ln -s "$HOME/.config/espanso" "$HOME/Library/Application Support/espanso"
fi

if [ ! -d "$HOME/.asdf" ]; then
  fancy_echo "Installing asdf version manager ..."
  git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf" --branch v0.14.1

  # shellcheck disable=SC2016
  append_to_zshrc '. "$HOME/.asdf/asdf.sh"'
  # shellcheck disable=SC2016
  append_to_zshrc 'fpath=(${ASDF_DIR}/completions $fpath)' 1
  append_to_zshrc 'autoload -Uz compinit && compinit' 1
fi

alias install_asdf_plugin=add_or_update_asdf_plugin
add_or_update_asdf_plugin() {
  local name="$1"
  local url="$2"

  if ! asdf plugin-list | grep -Fq "$name"; then
    asdf plugin-add "$name" "$url"
  else
    asdf plugin-update "$name"
  fi
}

install_asdf_language() {
  local language="$1"
  local version
  version="$(asdf list-all "$language" | grep -v "[a-z]" | tail -1)"

  if ! asdf list "$language" | grep -Fq "$version"; then
    asdf install "$language" "$version"
    asdf global "$language" "$version"
  fi
}

gem_install_or_update() {
  if gem list "$1" --installed >/dev/null; then
    gem update "$@"
  else
    gem install "$@"
  fi
}

# shellcheck disable=SC1091
. "$HOME/.asdf/asdf.sh"

fancy_echo "Installing latest Ruby ..."
add_or_update_asdf_plugin "ruby" "https://github.com/asdf-vm/asdf-ruby.git"
install_asdf_language "ruby"
gem update --system
number_of_cores=$(sysctl -n hw.ncpu)
bundle config --global jobs $((number_of_cores - 1))

if [ ! -f "$HOME/.gemrc" ]; then
  echo "gem: --no-document" >"$HOME/.gemrc"
fi

fancy_echo "Installing Ruby 2.6.7 ..."
if ! asdf list ruby | grep -Fq 2.6.7; then
  export DLDFLAGS="-Wl,-undefined,dynamic_lookup"
  export OPENSSL_CFLAGS="-Wno-error=implicit-function-declaration"
  export CFLAGS=-Wno-error="implicit-function-declaration"
  asdf install ruby 2.6.7
  asdf global ruby 2.6.7
fi

asdf shell ruby 2.6.7

if ! gem list bundler -v 1.17.3 --installed >/dev/null; then
  gem install bundler -v 1.17.3
fi

fancy_echo "Installing neovim gem dependencies ..."
if ! gem list rubocop-ast -v 1.30.0 --installed >/dev/null; then
  gem install rubocop-ast -v 1.30.0
fi

if ! gem list parallel -v 1.24.0 --installed >/dev/null; then
  gem install parallel -v 1.24.0
fi

if ! gem list rubocop -v 1.25.1 --installed >/dev/null; then
  gem install rubocop -v=1.25.1
fi

if ! gem list rubocop-rspec -v 2.11.1 --installed >/dev/null; then
  gem install rubocop-rspec -v 2.11.1
fi

if ! gem list nokogiri -v 1.13.10 --installed >/dev/null; then
  gem install nokogiri -v 1.13.10
fi

if ! gem list solargraph -v 0.41.2 --installed >/dev/null; then
  gem install solargraph -v=0.41.2
fi

fancy_echo "Installing latest Node ..."
add_or_update_asdf_plugin "nodejs" "https://github.com/asdf-vm/asdf-nodejs.git"
install_asdf_language "nodejs"

npm i changelog-maker -g

fancy_echo "Installing latest Python ..."
add_or_update_asdf_plugin "python" "https://github.com/asdf-community/asdf-python.git"
install_asdf_language "python"

fancy_echo "Laptop setup is complete!

Please restart your laptop for settings to take effect.
"
