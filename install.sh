#!/usr/bin/env bash
# Bei "sh install.sh" laeuft dash und stolpert ueber die Array-Syntax weiter
# unten. Deshalb hier POSIX-konform pruefen und mit bash neu starten.
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="default"
PROFILE="auto"

# Alles was auch headless Sinn ergibt
BASE_PACKAGES=(zsh tmux vim fzf stow curl git unzip thefuck wl-clipboard xclip mosh)
BASE_STOW=(zsh bash git tmux misc)

# Nur auf einem Desktop sinnvoll: Terminal-Emulator, Fonts, VS Code
GUI_PACKAGES=(kitty fontconfig)
GUI_STOW=(kitty vscode)

info()  { printf "\033[1;34m[INFO]\033[0m  %s\n" "$1"; }
ok()    { printf "\033[1;32m[OK]\033[0m    %s\n" "$1"; }
warn()  { printf "\033[1;33m[WARN]\033[0m  %s\n" "$1"; }
error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"; }

usage() {
    echo "Usage: $0 [--backup | --overwrite] [--server | --desktop]"
    echo ""
    echo "  (default)     Fail if existing dotfiles conflict with stow"
    echo "  --backup      Back up existing dotfiles before symlinking"
    echo "  --overwrite   Overwrite existing dotfiles with these configs"
    echo ""
    echo "  --server      Skip kitty, fonts and VS Code (headless machines)"
    echo "  --desktop     Force the full desktop install"
    echo "                Without either flag the profile is auto-detected."
    exit 1
}

# ---------- parse arguments ----------
for arg in "$@"; do
    case "$arg" in
        --backup)    MODE="backup" ;;
        --overwrite) MODE="overwrite" ;;
        --server)    PROFILE="server" ;;
        --desktop)   PROFILE="desktop" ;;
        -h|--help)   usage ;;
        *)           error "Unknown option: $arg"; usage ;;
    esac
done

# ---------- desktop oder server? ----------
# Absichtlich an den installierten Session-Verzeichnissen festgemacht und nicht
# an $DISPLAY: per "ssh -X" auf eine Droplet waere $DISPLAY gesetzt, obwohl die
# Maschine headless ist.
if [ "$PROFILE" = "auto" ]; then
    if [ -d /usr/share/xsessions ] || [ -d /usr/share/wayland-sessions ]; then
        PROFILE="desktop"
    else
        PROFILE="server"
    fi
fi

APT_PACKAGES=("${BASE_PACKAGES[@]}")
STOW_PACKAGES=("${BASE_STOW[@]}")
if [ "$PROFILE" = "desktop" ]; then
    APT_PACKAGES+=("${GUI_PACKAGES[@]}")
    STOW_PACKAGES+=("${GUI_STOW[@]}")
fi

# ---------- sudo nur wenn noetig und vorhanden ----------
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    error "Neither running as root nor is sudo available"
    exit 1
fi

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
info "Installing system packages ($PROFILE profile)..."

# Ein kaputtes Fremd-Repo (abgelaufene PPA, fehlender Key) laesst apt update mit
# Exit-Code 100 zurueckkommen. Das darf die Installation nicht abbrechen, die
# Paketlisten der funktionierenden Repos sind trotzdem aktuell.
if ! $SUDO apt update; then
    warn "apt update reported errors (broken third-party repo?), continuing"
fi

$SUDO apt install -y "${APT_PACKAGES[@]}"

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

# ---------- desktop-only: Fonts, VS Code ----------
if [ "$PROFILE" = "desktop" ]; then
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
        $SUDO dpkg -i /tmp/vscode.deb || $SUDO apt install -f -y
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
else
    info "Server profile: skipping fonts, VS Code and its extensions"
fi

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

TMUX_PLUGINS_DIR="$HOME/.tmux/plugins"
declare -A TMUX_PLUGINS=(
    [tmux-fzf]="https://github.com/sainnhe/tmux-fzf"
    [tmux]="https://github.com/dracula/tmux"
)

for plugin in "${!TMUX_PLUGINS[@]}"; do
    if [ ! -d "$TMUX_PLUGINS_DIR/$plugin" ]; then
        info "Installing tmux plugin: $plugin"
        git clone --depth=1 "${TMUX_PLUGINS[$plugin]}" "$TMUX_PLUGINS_DIR/$plugin"
        ok "$plugin installed"
    else
        ok "$plugin already installed"
    fi
done

# ---------- set default shell ----------
if [ "$SHELL" != "$(which zsh)" ]; then
    info "Setting zsh as default shell..."
    if chsh -s "$(which zsh)"; then
        ok "Default shell changed to zsh (takes effect on next login)"
    else
        warn "chsh failed, set the shell manually: chsh -s $(which zsh)"
    fi
else
    ok "zsh is already the default shell"
fi

echo ""
ok "All done! Log out and back in, or run: exec zsh"
