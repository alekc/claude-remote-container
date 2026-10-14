# Sourced by each download stage: fetch over HTTPS, verify a SHA-256.
set -eu

fetch() { curl -fsSL --retry 3 --proto '=https' -o "$2" "$1"; }

# sum_of LIST NAME: the hash on the line naming NAME in a "hash  name" list,
# where NAME may carry a binary-mode "*" or a "./" prefix.
sum_of() { awk -v n="$2" '{ f = $NF; sub(/^(\*|\.\/)/, "", f) } f == n { print $1; exit }' "$1"; }

verify() {
  [ -n "$1" ] || { echo "no checksum found for $2" >&2; exit 1; }
  printf '%s  %s\n' "$1" "$2" | sha256sum -c --strict --quiet -
}
