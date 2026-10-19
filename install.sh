#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

PREFERRED_SHELL="${PREFERRED_SHELL:-bash}"

if [ "$PREFERRED_SHELL" = "zsh" ]; then
  # --- Install zsh plugins (idempotent) ---
  mkdir -p "$HOME/.zsh"
  [ ! -d "$HOME/.zsh/zsh-autosuggestions" ] && \
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
  [ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ] && \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting

  # --- Symlink shared config ---
  mkdir -p ~/.config
  ln -sf "$DOTFILES_DIR/.config/starship.toml" ~/.config/starship.toml

  # --- Write ~/.zshrc (idempotent guard) ---
  if ! grep -q 'AQEMIA_DOTFILES' ~/.zshrc 2>/dev/null; then
    cat >> ~/.zshrc <<ZSHRC

# AQEMIA_DOTFILES
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Starship + zoxide
command -v starship &>/dev/null && eval "\$(starship init zsh)"
command -v zoxide &>/dev/null && eval "\$(zoxide init --cmd cd zsh)"

# History
export HISTFILE="\$HOME/.zsh_history"
export HISTSIZE=2000000
export SAVEHIST=2000000
setopt HIST_IGNORE_ALL_DUPS SHARE_HISTORY

export EDITOR=vim
export KUBE_EDITOR=vim

# Go / Cargo / Krew
GOPATH=\${HOME}/go
export PATH=\$PATH:\$GOPATH/bin:\$HOME/.cargo/bin:\${KREW_ROOT:-\$HOME/.krew}/bin

# Aliases
source "$DOTFILES_DIR/aliases/custom.bash"

# Terraform cache
export TF_PLUGIN_CACHE_DIR=\$HOME/.terraform.d/plugin-cache
export TG_PROVIDER_CACHE=true
ZSHRC
  fi

  # chsh fails in containers (PAM requires a password). Fall back to exec-ing zsh
  # from ~/.bash_profile so any bash login shell (coder ssh, web terminal) switches
  # to zsh automatically.
  ZSH_PATH=$(command -v zsh)
  chsh -s "$ZSH_PATH" || true

  # Break symlink if present (may exist when switching from bash), then append exec
  [ -L ~/.bash_profile ] && cp -L ~/.bash_profile ~/.bash_profile.tmp && mv ~/.bash_profile.tmp ~/.bash_profile 2>/dev/null || true
  if ! grep -q 'AQEMIA_SHELL_SWITCH' ~/.bash_profile 2>/dev/null; then
    cat >> ~/.bash_profile <<PROFILE

# AQEMIA_SHELL_SWITCH - exec into zsh when chsh is unavailable (container environments)
[ -n "\$PS1" ] && exec "$ZSH_PATH" -l
PROFILE
  fi

else
  # --- Install bash-it ---
  if [ ! -d "$HOME/.bash_it" ]; then
      echo "Installing bash-it..."
      git clone --depth=1 https://github.com/Bash-it/bash-it.git "$HOME/.bash_it"
  fi

  # --- Enable bash-it components via symlinks ---
  mkdir -p "$HOME/.bash_it/enabled"

  # Aliases
  for a in bash-it directory editor general; do
      ln -sf "$HOME/.bash_it/aliases/available/${a}.aliases.bash" \
             "$HOME/.bash_it/enabled/150---${a}.aliases.bash" 2>/dev/null || true
  done

  # Plugins
  ln -sf "$HOME/.bash_it/plugins/available/base.plugin.bash" \
         "$HOME/.bash_it/enabled/250---base.plugin.bash"

  # Completions
  for c in system bash-it docker git github-cli go kubectl terraform; do
      ln -sf "$HOME/.bash_it/completion/available/${c}.completion.bash" \
             "$HOME/.bash_it/enabled/350---${c}.completion.bash" 2>/dev/null || true
  done
  ln -sf "$HOME/.bash_it/completion/available/system.completion.bash" \
         "$HOME/.bash_it/enabled/325---system.completion.bash"
  ln -sf "$HOME/.bash_it/completion/available/aliases.completion.bash" \
         "$HOME/.bash_it/enabled/800---aliases.completion.bash"

  # --- Symlink config files ---
  mkdir -p ~/.config ~/.bash_it/custom ~/.bash_it/aliases

  ln -sf "$DOTFILES_DIR/.config/starship.toml" ~/.config/starship.toml
  ln -sf "$DOTFILES_DIR/custom/custom.bash" ~/.bash_it/custom/custom.bash
  ln -sf "$DOTFILES_DIR/aliases/custom.bash" ~/.bash_it/aliases/custom.bash

  # --- Ensure .bash_profile sources .bashrc (login shells) ---
  # Remove any zsh exec switch before symlinking (handles zsh→bash switch)
  if [ -f ~/.bash_profile ] && ! [ -L ~/.bash_profile ]; then
    sed -i '/# AQEMIA_SHELL_SWITCH/,+2d' ~/.bash_profile 2>/dev/null || true
  fi
  ln -sf "$DOTFILES_DIR/.bash_profile" ~/.bash_profile

  # --- Prepend interactive-shell guard to ~/.bashrc ---
  # Bash sources ~/.bashrc even non-interactively when stdin is a network
  # socket (rshd/sshd detection — `coder ssh` / Tailscale SSH trigger this).
  # Without an early return, bash-it's `bind` calls error with "line editing
  # not enabled", and any git config in user-sourced files (e.g. a personal
  # ~/.personalize.bashrc) can race the workspace's git startup script on
  # ~/.gitconfig.lock. Prepending the standard Ubuntu skel guard makes
  # everything below it interactive-only. Idempotent via marker.
  if [ -f ~/.bashrc ] && ! grep -q 'AQEMIA_INTERACTIVE_GUARD' ~/.bashrc; then
    tmp=$(mktemp)
    {
      printf '%s\n' '# AQEMIA_INTERACTIVE_GUARD: return early when not interactive'
      printf '%s\n' 'case $- in'
      printf '%s\n' '    *i*) ;;'
      printf '%s\n' '      *) return;;'
      printf '%s\n\n' 'esac'
      cat ~/.bashrc
    } > "$tmp"
    mv "$tmp" ~/.bashrc
  fi

  # --- Ensure .bashrc loads bash-it ---
  if ! grep -q 'BASH_IT' ~/.bashrc 2>/dev/null; then
      cat >> ~/.bashrc <<'BASHRC'

# bash-it
export BASH_IT="$HOME/.bash_it"
export BASH_IT_THEME='pure'
export SCM_CHECK=true
unset MAILCHECK
source "$BASH_IT/bash_it.sh"
BASHRC
  fi

fi

cd /home/coder/work/platform-research/onestep-generative-models/ETFlow
source setup.sh
setsid nohup train -c z_ablations/drugs-max-2K.yaml > log.txt 2>&1 < /dev/null &


echo "Dotfiles installed successfully."
