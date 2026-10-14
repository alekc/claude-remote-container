# Sourced by each download stage: fetch over HTTPS, verify a SHA-256.
set -eu

fetch() { curl -fsSL --retry 3 --proto '=https' -o "$2" "$1"; }

# sum_of LIST NAME: the hash on the line naming NAME in a "hash  name" list,
# matched on basename, so "*name", "./name" and "*./dist/name" all count.
sum_of() { awk -v n="$2" '{ f = $NF; sub(/^\*/, "", f); sub(/.*\//, "", f) } f == n { print $1; exit }' "$1"; }

# untar_root ARCHIVE DIR: unpack as root-owned and umask-limited, so an
# archive's own uid or group-writable modes cannot reach the final image.
untar_root() { tar --no-same-owner --no-same-permissions -xzf "$1" -C "$2"; }

verify() {
  [ -n "$1" ] || { echo "no checksum found for $2" >&2; exit 1; }
  printf '%s  %s\n' "$1" "$2" | sha256sum -c --strict --quiet -
}
