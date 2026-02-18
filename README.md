# dotfiles

my personal dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## setup

```bash
git clone git@github.com:mendax23/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

## what's included

| package | files |
|---------|-------|
| zsh | `.zshrc`, `.p10k.zsh` |
| bash | `.bashrc`, `.profile` |
| git | `.gitconfig` |
| tmux | `.tmux.conf` |
| kitty | `kitty.conf`, `theme.conf` |
| vscode | `settings.json` |

`install.sh` handles all dependencies — oh-my-zsh, plugins, fonts, nvm, tpm, vscode extensions.
