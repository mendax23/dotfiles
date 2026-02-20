#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
STOW_PACKAGES=(zsh bash git tmux kitty vscode misc)
MODE="default"

info()  { printf "\033[1;34m[INFO]\033[0m  %s\n" "$1"; }
ok()    { printf "\033[1;32m[OK]\033[0m    %s\n" "$1"; }
warn()  { printf "\033[1;33m[WARN]\033[0m  %s\n" "$1"; }
error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"; }

usage() {
    echo "Usage: $0 [--backup | --overwrite]"
    echo ""
    echo "  (default)     Fail if existing dotfiles conflict with stow"
    echo "  --backup      Back up existing dotfiles before symlinking"
    echo "  --overwrite   Overwrite existing dotfiles with these configs"
    exit 1
}

# ---------- parse arguments ----------
for arg in "$@"; do
    case "$arg" in
        --backup)    MODE="backup" ;;
        --overwrite) MODE="overwrite" ;;
        -h|--help)   usage ;;
        *)           error "Unknown option: $arg"; usage ;;
    esac
done

# ---------- find conflicting files ----------
find_conflicts() {
    local conflicts=()
    for package in "${STOW_PACKAGES[@]}"; do
        while IFS= read -r -d '' file; do
            local rel="${file#"$DOTFILES_DIR/$package/"}"
            local target="$HOME/$rel"
            if [ -e "$target" ] && [ ! -L "$target" ]; then
                conflicts+=("$target")
            fi
        done < <(find "$DOTFILES_DIR/$package" -type f -print0)
    done
    printf '%s\n' "${conflicts[@]}"
}

# ---------- backup conflicting dotfiles ----------
backup_dotfiles() {
    local backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    local conflicts
    conflicts="$(find_conflicts)"

    if [ -z "$conflicts" ]; then
        info "No conflicting dotfiles found, nothing to back up"
        return
    fi

    info "Backing up existing dotfiles to $backup_dir"
    mkdir -p "$backup_dir"
    while IFS= read -r file; do
        local rel="${file#"$HOME/"}"
        mkdir -p "$backup_dir/$(dirname "$rel")"
        mv "$file" "$backup_dir/$rel"
        info "  Backed up $rel"
    done <<< "$conflicts"
    ok "Backup saved to $backup_dir"
}

# ---------- system packages ----------
info "Installing system packages..."
sudo apt update
sudo apt install -y \
    zsh tmux kitty vim fzf stow curl git \
    thefuck wl-clipboard xclip

ok "System packages installed"

# ---------- oh-my-zsh ----------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    info "Installing Oh My Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ok "Oh My Zsh installed"
else
    ok "Oh My Zsh already installed"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# ---------- powerlevel10k ----------
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    info "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
        "$ZSH_CUSTOM/themes/powerlevel10k"
    ok "Powerlevel10k installed"
else
    ok "Powerlevel10k already installed"
fi

# ---------- zsh plugins ----------
declare -A ZSH_PLUGINS=(
    [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
    [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
    [history-substring-search]="https://github.com/zsh-users/zsh-history-substring-search"
)

for plugin in "${!ZSH_PLUGINS[@]}"; do
    if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        info "Installing zsh plugin: $plugin"
        git clone --depth=1 "${ZSH_PLUGINS[$plugin]}" "$ZSH_CUSTOM/plugins/$plugin"
        ok "$plugin installed"
    else
        ok "$plugin already installed"
    fi
done

# ---------- nvm ----------
if [ ! -d "$HOME/.nvm" ]; then
    info "Installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    ok "nvm installed"
else
    ok "nvm already installed"
fi

# ---------- tpm (tmux plugin manager) ----------
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    info "Installing TPM (Tmux Plugin Manager)..."
    git clone --depth=1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    ok "TPM installed"
else
    ok "TPM already installed"
fi

# ---------- FiraCode Nerd Font ----------
FONT_DIR="$HOME/.local/share/fonts"
if ! fc-list | grep -qi "FiraCode Nerd Font"; then
    info "Installing FiraCode Nerd Font..."
    mkdir -p "$FONT_DIR"
    curl -fLo /tmp/FiraCode.zip \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip
    unzip -o /tmp/FiraCode.zip -d "$FONT_DIR/FiraCode"
    fc-cache -fv
    rm /tmp/FiraCode.zip
    ok "FiraCode Nerd Font installed"
else
    ok "FiraCode Nerd Font already installed"
fi

# ---------- VS Code ----------
if ! command -v code &>/dev/null; then
    info "Installing VS Code..."
    curl -fLo /tmp/vscode.deb \
        "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
    sudo dpkg -i /tmp/vscode.deb || sudo apt install -f -y
    rm /tmp/vscode.deb
    ok "VS Code installed"
else
    ok "VS Code already installed"
fi

# ---------- VS Code extensions ----------
VSCODE_EXTENSIONS=(
    ms-python.debugpy
    ms-python.python
    ms-python.vscode-pylance
    ms-python.vscode-python-envs
    ms-vscode-remote.remote-ssh
    ms-vscode-remote.remote-ssh-edit
    ms-vscode.remote-explorer
)

info "Installing VS Code extensions..."
for ext in "${VSCODE_EXTENSIONS[@]}"; do
    code --install-extension "$ext" --force 2>/dev/null || warn "Failed to install $ext"
done
ok "VS Code extensions done"

# ---------- symlink dotfiles with stow ----------
cd "$DOTFILES_DIR"

if [ "$MODE" = "backup" ]; then
    backup_dotfiles
elif [ "$MODE" = "overwrite" ]; then
    info "Overwriting existing dotfiles..."
elif [ "$MODE" = "default" ]; then
    conflicts="$(find_conflicts)"
    if [ -n "$conflicts" ]; then
        error "Existing dotfiles would conflict with stow:"
        echo "$conflicts" | while IFS= read -r f; do printf "  %s\n" "$f"; done
        echo ""
        info "Re-run with one of:"
        info "  $0 --backup      Back up existing files, then symlink"
        info "  $0 --overwrite   Overwrite existing files"
        exit 1
    fi
fi

info "Symlinking dotfiles with stow..."
for package in "${STOW_PACKAGES[@]}"; do
    if [ "$MODE" = "overwrite" ]; then
        stow -v --adopt --target="$HOME" "$package"
    else
        stow -v --restow --target="$HOME" "$package"
    fi
done

if [ "$MODE" = "overwrite" ]; then
    info "Restoring repo versions over adopted files..."
    git -C "$DOTFILES_DIR" checkout -- .
fi

ok "Dotfiles symlinked"

# ---------- install tmux plugins ----------
info "Installing tmux plugins..."
"$HOME/.tmux/plugins/tpm/bin/install_plugins" || warn "Run 'prefix + I' inside tmux to install plugins"

# ---------- set default shell ----------
if [ "$SHELL" != "$(which zsh)" ]; then
    info "Setting zsh as default shell..."
    chsh -s "$(which zsh)"
    ok "Default shell changed to zsh (takes effect on next login)"
else
    ok "zsh is already the default shell"
fi

echo ""
ok "All done! Log out and back in, or run: exec zsh"
