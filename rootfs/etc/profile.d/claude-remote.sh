# Every shell on the host: ssh logins read it via /etc/profile, herdr panes
# and `ssh host cmd` via the top of /etc/bash.bashrc. Must print nothing.
export HOMEBREW_NO_ANALYTICS=1 HELM_PLUGINS=/opt/helm/plugins CHECKPOINT_DISABLE=1
# The image pins opencode; its self-update cannot write /usr/local/bin anyway.
export OPENCODE_DISABLE_AUTOUPDATE=1
# A client locale missing here (macOS sends LC_CTYPE=UTF-8) or none at all
# leaves libc in ASCII, and zsh then mangles non-Latin input.
if [ -n "$(locale 2>&1 >/dev/null)" ] || [ "$(locale charmap)" != UTF-8 ]; then
  export LC_ALL=C.UTF-8
fi
export NPM_CONFIG_PREFIX="$HOME/.local" GOBIN="$HOME/.local/bin"
# Caches live off the home volume, so a restart empties them. Go's module
# cache and npm's do not follow XDG_CACHE_HOME and are pointed there too.
export XDG_CACHE_HOME=/var/cache/claude-remote
export GOMODCACHE="$XDG_CACHE_HOME/go/mod" npm_config_cache="$XDG_CACHE_HOME/npm"
# Only the agent user: brew is agent-owned, so root must never run its output.
if [ "$(id -u)" = 1000 ] && [ -x /home/linuxbrew/.linuxbrew/bin/brew ] \
  && [ -z "${HOMEBREW_PREFIX:-}" ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
# Prepended last-first, so the order is: own bin, mise shims (own versions,
# then the image's defaults), Homebrew, system.
for d in /usr/local/share/mise/shims "$HOME/.local/share/mise/shims" "$HOME/.local/bin"; do
  case ":$PATH:" in
    *":$d:"*) ;;
    *) PATH="$d:$PATH" ;;
  esac
done
unset d
export PATH
