# Every shell on the host: ssh logins read it via /etc/profile, herdr panes
# (interactive, non-login) via /etc/bash.bashrc.
export HOMEBREW_NO_ANALYTICS=1 HELM_PLUGINS=/opt/helm/plugins CHECKPOINT_DISABLE=1
export NPM_CONFIG_PREFIX="$HOME/.local"
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && [ -z "${HOMEBREW_PREFIX:-}" ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH
