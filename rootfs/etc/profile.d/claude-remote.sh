# Every shell on the host: ssh logins read it via /etc/profile, herdr panes
# (interactive, non-login) via /etc/bash.bashrc.
export HOMEBREW_NO_ANALYTICS=1 HELM_PLUGINS=/opt/helm/plugins CHECKPOINT_DISABLE=1
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
