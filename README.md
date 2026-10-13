# claude-remote-container

Container image for a long-lived Claude Code agent host, driven over SSH with
[herdr](https://github.com/herdrdev/herdr) (`herdr --remote <host>`). It is meant
to run as a single Kubernetes pod with a persistent home volume.

## What is in it

- Ubuntu 26.04, `openssh-server` on port 2222, `tini` as PID 1.
- An unprivileged agent account (uid 1000, no sudo, no `adm`), named at start
  from `$USER`.
- Kubernetes and IaC tooling: `kubectl`, `helm` (with the diff, s3, unittest and
  values-schema plugins), `helmfile`, `helm-docs`, `kubeconform`, `vals`,
  `velero`, `tofu`, `terraform`, `ansible-core`, `ansible-lint`.
- General tooling: `gh`, `glab`, `infisical`, `rclone`, `trivy`, `yq`, `uv`,
  `go`, `node`, `pre-commit`, `herdr`, Homebrew.

Every downloaded binary is checked against the publisher's SHA-256 before it is
installed. herdr publishes no checksums file, so its hash comes from the GitHub
release API's asset digest.

## Runtime contract

The entrypoint refuses to start unless all of these are set:

| Input | Content |
| --- | --- |
| `USER` env var | The agent's login name. The uid 1000 account is renamed to it, and it is the only user `sshd` admits. Not `root`, not an existing system account. |
| `/mnt/claude-remote/hostkey/ssh_host_ed25519_key` | The SSH host key. The image ships none. |
| `/mnt/claude-remote/authorized-keys/authorized_keys` | Keys allowed to log in as `$USER`. |

The keys are copied to root-owned paths before `sshd` starts, so the agent user
cannot change who may log in. `/home/$USER` is expected to be a volume, mounted
at the path matching `USER`; anything the image needs lives outside `/home`
(`/opt`, `/usr/local`), except Homebrew in `/home/linuxbrew`.

```bash
docker run -d -p 2222:2222 -e USER=jane \
  -v ./hostkey:/mnt/claude-remote/hostkey:ro \
  -v ./keys:/mnt/claude-remote/authorized-keys:ro \
  -v jane-home:/home/jane \
  ghcr.io/alekc/claude-remote-container:latest
```

Homebrew is the scratch tier: the agent user owns it, so `brew install` needs no
root, and it is outside the home volume, so it resets on every restart. Tools
that must survive a restart belong in this image.

## Building

```bash
docker buildx build --platform linux/amd64 --load -t claude-remote:local .
docker run --rm --entrypoint /usr/local/libexec/claude-remote/smoke-test claude-remote:local
```

The smoke test runs every tool's version command, checks that `set-user` rejects
bad names and renames idempotently, that no host key and no sudo shipped, and
validates the sshd config.

On an Apple Silicon machine whose Docker runtime emulates amd64 with Rosetta,
the final stage fails: Ubuntu 26.04's `tar` needs the `openat2` syscall, which
Rosetta lacks, and the helm plugin hooks and the Homebrew installer run `tar`.
The download stages run natively and are unaffected; CI builds the whole image
on native amd64.

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
