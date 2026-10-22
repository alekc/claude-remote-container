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
- Language runtimes through [mise](https://mise.jdx.dev): `go`, `node`, `python`.
- General tooling: `gh`, `glab`, `infisical`, `rclone`, `trivy`, `yq`, `uv`,
  `pre-commit`, `herdr`, Homebrew.
- [ccstatusline](https://github.com/sirmalloc/ccstatusline) as the Claude Code
  status line, seeded with a default layout.
- zsh as the agent's login shell, with [starship](https://starship.rs) and
  `bat`; see [Shell](#shell).

Every downloaded binary is checked against the publisher's SHA-256 before it is
installed. herdr publishes no checksums file, so its hash comes from the GitHub
release API's asset digest. mise verifies the runtimes itself: go against its
`.sha256`, node against GPG-signed `SHASUMS256`, python by GitHub attestation.

## Shell

The agent logs in to zsh. `/etc/zsh/zshenv` sources the same profile as bash,
so `ssh host cmd` gets the same `PATH` in either shell. Interactive shells, zsh
and bash alike, get the image defaults from `/usr/local/share/claude-remote/`:

- aliases `ll` (`ls -la`), `la` (`ls -A`), `k` (`kubectl`, with completion) and
  `cat` (`bat --paging=never`, which prints the file unchanged off a terminal);
- the starship prompt, and in zsh a 50,000-line shared history.

They load before `~/.zshrc` and `~/.bashrc`, so anything personal goes there,
on the home volume, along with `~/.config/starship.toml`. A one-line `~/.zshrc`
is seeded on first start, which keeps zsh's new-user wizard away.

sshd accepts the client's `LANG` and `LC_*`. The image builds `en_GB.UTF-8` and
`en_US.UTF-8`; for any other client locale, or none, the profile sets
`LC_ALL=C.UTF-8`, because libc otherwise falls back to ASCII and zsh garbles
non-Latin input such as Cyrillic.

## Language runtimes

mise works like tfenv for go, node and python. The image installs one default
version of each into `/usr/local/share/mise` and puts its shims on `PATH`. A
project picks another with `.go-version`, `.nvmrc` / `.node-version`,
`.python-version` or a `mise.toml`; the shim installs it on first use into
`~/.local/share/mise`, on the home volume, so it survives a restart.

```bash
cd ~/project && echo 24 > .nvmrc && node --version   # v24.x, installed on demand
mise use -g python@3.13                             # change the default for this user
mise ls                                             # (system) = image default
```

A `mise.toml` must be trusted once with `mise trust`. Ubuntu's own `python3`
stays at `/usr/bin/python3`; ansible, ansible-lint and pre-commit run on it.

## Runtime contract

The entrypoint refuses to start unless all of these are set:

| Input | Content |
| --- | --- |
| `USER` env var | The agent's login name. The uid 1000 account is renamed to it, and it is the only user `sshd` admits. Not `root`, not `linuxbrew`, not an existing system account or group. |
| `/mnt/claude-remote/hostkey/ssh_host_ed25519_key` | The SSH host key, unreadable by uid 1000. The image ships none. |
| `/mnt/claude-remote/authorized-keys/authorized_keys` | Keys allowed to log in as `$USER`. |

The keys are copied to root-owned paths before `sshd` starts, so the agent user
cannot change who may log in. The host key must not be readable by uid 1000, or
the entrypoint refuses to start: in Kubernetes mount its Secret with
`defaultMode: 0400` and do not set the pod's `fsGroup` to 1000, which makes it
group-readable; for a bind mount, make the file root-owned and 0400.

`/home/$USER` is expected to be a volume, mounted at the path matching `USER`;
anything the image needs lives outside `/home` (`/opt`, `/usr/local`), except
Homebrew in `/home/linuxbrew`. It is the only place that survives a restart, so
projects belong under it, conventionally `~/dev/<project>`. A project that needs
its own volume (size, backup policy) can be mounted below the home: on every
start the agent is given each root-owned mount root there, never the files in
it, which is what `fsGroup` would otherwise be needed for.

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

On every start, `seed-home` copies defaults into the home volume where the file
is missing, and never over an existing one: the ccstatusline layout to
`~/.config/ccstatusline/settings.json`, and a `statusLine` entry into
`~/.claude/settings.json` when it has none. It runs as the agent user, and a
failure is logged without blocking `sshd`. The defaults live in
`/usr/local/share/claude-remote`.

In Kubernetes, `sshd` starts each login without the pod's environment, so
kubectl would miss the in-cluster `KUBERNETES_SERVICE_HOST` and `PORT` and fall
back to `localhost:8080`. The entrypoint copies both into `/etc/environment`,
which `pam_env` loads for every SSH session. When a service account token is
mounted, `seed-home` also writes `~/.kube/config` with an `in-cluster` context
that reads the token through `tokenFile`, so rotation keeps working. kubectl
ignores in-cluster config once any kubeconfig exists, so add other contexts to
that file beside `in-cluster` rather than replacing it.

Caches are kept off the home volume so they cannot fill it:
`XDG_CACHE_HOME=/var/cache/claude-remote` covers Go's build cache, uv, pip,
mise downloads, trivy, helm and Homebrew, and `GOMODCACHE` and npm's cache are
pointed under it. Without a volume it lives in the container's writable layer,
which a new container starts without. In Kubernetes mount an `emptyDir` with a
`sizeLimit` there: it bounds the growth, survives container restarts, and is
emptied when the Pod is deleted. `go install` and `npm install -g` write to `~/.local/bin`,
which persists.

## Building

```bash
docker buildx build --platform linux/amd64 --load -t claude-remote:local .
docker run --rm --entrypoint /usr/local/libexec/claude-remote/smoke-test claude-remote:local
```

The smoke test runs every tool's version command, checks that `set-user` rejects
bad names and renames idempotently, that no host key and no sudo shipped, and
validates the sshd config. CI then starts the real entrypoint twice: with a host
key uid 1000 can read, which must refuse, and with a root-only one, which must
accept an SSH key login as `$USER` with the home seeded, the profile loaded for
a non-interactive command, and a fresh volume below the home writable.

On an Apple Silicon machine whose Docker runtime emulates amd64 with Rosetta,
the final stage fails: Ubuntu 26.04's `tar` needs the `openat2` syscall, which
Rosetta lacks, and the Homebrew installer runs `tar`.
The download stages run natively and are unaffected; CI builds the whole image
on native amd64.

## CI and tags

`.github/workflows/image.yml` builds once, tests, and only then pushes that same
image, never a rebuild, to `ghcr.io/alekc/claude-remote-container`:

| Event | Tags |
| --- | --- |
| Push to `main` | `latest`, `sha-<short>` |
| Pull request from this repo | `pr-<number>`, deleted when the PR closes |
| Pull request from a fork | built and tested, not pushed |
| Manual run on another branch | built and tested, not pushed |

## Updates

Renovate tracks the base image digest, every tool version (a `# renovate:`
comment above each `ARG`), the Homebrew installer's pinned commit and the
pinned action digests, after a 3-day release age. The installer commit has no
release timestamp to age, so its bumps skip that wait.

| PR | Contents | Merges itself |
| --- | --- | --- |
| `tooling` | Every tool and runtime minor or patch bump | Only if every bump in it may: a `gh`, `glab`, `infisical` bump or a go / node / python minor holds it for review |
| `tooling` (major) | Major bumps, in a separate PR | No |
| `tofu and terraform` | Both binaries | Never: a binary newer than the workstation's rewrites state irreversibly |
| base image, actions | Separate PRs | Actions yes, base image no |

`kubectl` stays on the cluster's minor (1.36).

## Not done yet

- Guard the agent from acting on production by default (preflight checks, managed
  Claude Code settings).
- A herdr binary left in `~/.local/bin` on the home volume shadows the image's
  copy; decide whether the image or the user owns it.
