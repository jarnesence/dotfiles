export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(sudo command-not-found)
source "$ZSH/oh-my-zsh.sh"

HISTFILE=~/.zsh_history
HISTSIZE=32768
SAVEHIST=$HISTSIZE
setopt HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE SHARE_HISTORY APPEND_HISTORY

# source bash fns inside an anonymous function with no_aliases so zsh doesn't
# expand aliases at parse time (e.g. fns/worktrees defines `ga()` while aliases
# file aliases `ga` — works in bash, fatal in zsh without this guard)
() {
  emulate -L zsh -o no_aliases
  for f in $OMARCHY_PATH/default/bash/fns/*(N); do source "$f"; done
}
[[ -r $OMARCHY_PATH/default/bash/aliases ]] && source "$OMARCHY_PATH/default/bash/aliases"

export ANDROID_HOME="$HOME/.android/sdk"
path=(
  $HOME/.local/bin
  $ANDROID_HOME/platform-tools
  $ANDROID_HOME/cmdline-tools/latest/bin
  $ANDROID_HOME/emulator
  $path
)

command -v mise   &>/dev/null && eval "$(mise activate zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
[[ -f /usr/share/fzf/completion.zsh   ]] && source /usr/share/fzf/completion.zsh
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh

# Visual: ghost text from history (gray inline suggestion). Right-arrow accepts.
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# Visual: live syntax coloring as you type (must be sourced LAST per upstream docs)
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Underline'ları kaldır (sudo, path, autodirectory vs.)
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[precommand]='fg=green'
ZSH_HIGHLIGHT_STYLES[path]='none'
ZSH_HIGHLIGHT_STYLES[path_pathseparator]='none'
ZSH_HIGHLIGHT_STYLES[path_prefix]='none'
ZSH_HIGHLIGHT_STYLES[path_prefix_pathseparator]='none'
ZSH_HIGHLIGHT_STYLES[autodirectory]='fg=green'
ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=green'

# Fancy completion menu: arrow-key navigation, colored entries, descriptions
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*' group-name ''

PROMPT='%~ ❯ '

_fetch() { command -v fastfetch &>/dev/null && fastfetch; }

_fetch

# Wrap claude: clear before, clear + fetch after exit. `cx` alias also
# routes through this since it expands to `claude ...` at runtime.
claude() {
  clear
  command claude "$@"
  local rc=$?
  clear
  _fetch
  return $rc
}

agy() {
  clear
  command agy "$@"
  local rc=$?
  clear
  _fetch
  return $rc
}
export PATH="$HOME/.local/bin:$PATH"
