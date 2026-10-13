# claude-remote-container

Container image for a long-lived Claude Code agent host, driven over SSH with
[herdr](https://github.com/herdrdev/herdr) (`herdr --remote <host>`). It is meant
to run as a single Kubernetes pod with a persistent home volume.

## What is in it

- Ubuntu 26.04, `openssh-server` on port 2222, `tini` as PID 1.
- An unprivileged agent user `alekc` (uid 1000), with no sudo and no `adm`.
- Kubernetes and IaC tooling: `kubectl`, `helm` (with the diff, s3, unittest and
  values-schema plugins), `helmfile`, `helm-docs`, `kubeconform`, `vals`,
  `velero`, `tofu`, `terraform`, `ansible-core`, `ansible-lint`.
- General tooling: `gh`, `glab`, `infisical`, `rclone`, `trivy`, `yq`, `uv`,
  `go`, `node`, `pre-commit`, `herdr`, Homebrew.

Every downloaded binary is checked against the publisher's SHA-256 before it is
installed. herdr publishes no checksums file, so its hash comes from the GitHub
release API's asset digest.

## Runtime contract

The entrypoint refuses to start unless both of these are mounted and non-empty:

| Path | Content |
| --- | --- |
| `/mnt/claude-remote/hostkey/ssh_host_ed25519_key` | The SSH host key. The image ships none. |
| `/mnt/claude-remote/authorized-keys/authorized_keys` | Keys allowed to log in as `alekc`. |

Both are copied to root-owned paths before `sshd` starts, so the agent user
cannot change who may log in. `/home/alekc` is expected to be a volume; anything
the image needs lives outside it (`/opt`, `/usr/local`, `/home/linuxbrew`).

Homebrew is the scratch tier: the agent user owns it, so `brew install` needs no
root, and it is outside the home volume, so it resets on every restart. Tools
that must survive a restart belong in this image.

## Building

```bash
docker buildx build --platform linux/amd64 --load -t claude-remote:local .
docker run --rm --entrypoint /usr/local/libexec/claude-remote/smoke-test claude-remote:local
```

The smoke test runs every tool's version command, checks that no host key and no
sudo shipped, and validates the sshd config.

## CI and tags

`.github/workflows/image.yml` builds, smoke-tests, and only then pushes to
`ghcr.io/alekc/claude-remote-container`:

| Event | Tags |
| --- | --- |
| Push to `main` | `latest`, `sha-<short>` |
| Pull request from this repo | `pr-<number>`, deleted when the PR closes |
| Pull request from a fork | built and tested, not pushed |

## Updates

Renovate tracks the base image digest, every tool version (a `# renovate:`
comment above each `ARG`) and the pinned action digests. Minor, patch and digest
bumps merge themselves once CI passes, after a 3-day release age. Never
automerged: the base image, `gh`, `glab`, `infisical`, and `tofu` / `terraform`,
because a newer binary than the one on the workstation rewrites state
irreversibly. `kubectl` stays on the cluster's minor (1.36).

## Not done yet

- Guard the agent from acting on production by default (preflight checks, managed
  Claude Code settings).
- A herdr binary left in `~/.local/bin` on the home volume shadows the image's
  copy; decide whether the image or the user owns it.
- Confirm the GHCR package is public after the first push.
