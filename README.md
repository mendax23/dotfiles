# dotfiles

my personal dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## fresh machine? do this

```bash
git clone git@github.com:mendax23/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

that's it. the install script handles everything — packages, oh-my-zsh, plugins, fonts, nvm, tpm, vscode extensions, and symlinks all the dotfiles into place.

## what's included

| package | files |
|---------|-------|
| zsh | `.zshrc`, `.p10k.zsh` |
| bash | `.bashrc`, `.profile` |
| git | `.gitconfig` |
| tmux | `.tmux.conf` |
| kitty | `kitty.conf`, `theme.conf` |
| vscode | `settings.json` |

## how stow works

stow is just a symlink manager. each folder in this repo (like `zsh/`, `tmux/`) mirrors your home directory structure. when you run stow, it creates symlinks from `~` pointing into this repo.

so `~/.zshrc` is actually a symlink to `~/dotfiles/zsh/.zshrc`. you edit your dotfiles like normal, but they live in the git repo. no copying files back and forth.

### already have dotfiles on the machine?

```bash
cd ~/dotfiles
stow --adopt -v --target="$HOME" zsh bash git tmux kitty vscode misc
```

`--adopt` replaces your existing files with symlinks and pulls the originals into the repo. check `git diff` after to see if anything changed.

### adding new dotfiles later

say you want to track a new config, like `~/.config/something/config.toml`:

```bash
mkdir -p ~/dotfiles/something/.config/something
mv ~/.config/something/config.toml ~/dotfiles/something/.config/something/
cd ~/dotfiles
stow -v --target="$HOME" something
```

now it's symlinked and tracked.

## dependencies installed by the script

- zsh, oh-my-zsh, powerlevel10k
- zsh-autosuggestions, zsh-syntax-highlighting, history-substring-search
- tmux, tpm, dracula theme
- kitty, FiraCode Nerd Font
- nvm, fzf, thefuck, vim
- vscode + extensions
