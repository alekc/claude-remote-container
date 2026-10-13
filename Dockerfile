# syntax=docker/dockerfile:1
# Agent host for remote Claude Code sessions driven through `herdr --remote`.
# One download stage per tool, so a version bump rebuilds only its own layer.

# Downloads run natively: every asset is named amd64 explicitly, and tar needs
# openat2, which Rosetta's amd64 emulation lacks on an arm64 builder.
FROM --platform=$BUILDPLATFORM ubuntu:26.04@sha256:f144425ff09be612d6d9ad965196e9cdc23dae1f42110a8a11a3e9a8198759f7 AS dl
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl jq unzip xz-utils \
  && rm -rf /var/lib/apt/lists/*
COPY build/fetch.sh /usr/local/lib/fetch.sh
WORKDIR /w

FROM dl AS helm
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=4.3.0
RUN . /usr/local/lib/fetch.sh; f=helm-v${HELM_VERSION}-linux-amd64.tar.gz; \
  fetch https://get.helm.sh/$f $f; fetch https://get.helm.sh/$f.sha256sum sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 linux-amd64/helm /out/helm

FROM dl AS yq
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=4.54.1
# yq's checksums file lists many hashes per asset; SHA-256 is column 19.
RUN . /usr/local/lib/fetch.sh; u=https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}; \
  f=yq_linux_amd64; fetch $u/$f $f; fetch $u/checksums sums; \
  verify "$(awk -v n=$f '$1 == n { print $19 }' sums)" $f; install -D -m 0755 $f /out/yq

FROM dl AS kubeconform
# renovate: datasource=github-releases depName=yannh/kubeconform
ARG KUBECONFORM_VERSION=0.8.0
RUN . /usr/local/lib/fetch.sh; u=https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}; \
  f=kubeconform-linux-amd64.tar.gz; fetch $u/$f $f; fetch $u/CHECKSUMS sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 kubeconform /out/kubeconform

FROM dl AS helm-docs
# renovate: datasource=github-releases depName=norwoodj/helm-docs
ARG HELM_DOCS_VERSION=1.14.2
RUN . /usr/local/lib/fetch.sh; u=https://github.com/norwoodj/helm-docs/releases/download/v${HELM_DOCS_VERSION}; \
  f=helm-docs_${HELM_DOCS_VERSION}_Linux_x86_64.tar.gz; fetch $u/$f $f; fetch $u/checksums.txt sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 helm-docs /out/helm-docs

FROM dl AS velero
# renovate: datasource=github-releases depName=vmware-tanzu/velero
ARG VELERO_VERSION=1.18.4
RUN . /usr/local/lib/fetch.sh; u=https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}; \
  d=velero-v${VELERO_VERSION}-linux-amd64; f=$d.tar.gz; fetch $u/$f $f; fetch $u/CHECKSUM sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 $d/velero /out/velero

FROM dl AS vals
# renovate: datasource=github-releases depName=helmfile/vals
ARG VALS_VERSION=0.47.0
RUN . /usr/local/lib/fetch.sh; u=https://github.com/helmfile/vals/releases/download/v${VALS_VERSION}; \
  f=vals_${VALS_VERSION}_linux_amd64.tar.gz; fetch $u/$f $f; fetch $u/vals_${VALS_VERSION}_checksums.txt sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 vals /out/vals

FROM dl AS helmfile
# renovate: datasource=github-releases depName=helmfile/helmfile
ARG HELMFILE_VERSION=1.8.1
RUN . /usr/local/lib/fetch.sh; u=https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}; \
  f=helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz; fetch $u/$f $f; fetch $u/helmfile_${HELMFILE_VERSION}_checksums.txt sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 helmfile /out/helmfile

FROM dl AS trivy
# renovate: datasource=github-releases depName=aquasecurity/trivy
ARG TRIVY_VERSION=0.75.0
RUN . /usr/local/lib/fetch.sh; u=https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}; \
  f=trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz; fetch $u/$f $f; fetch $u/trivy_${TRIVY_VERSION}_checksums.txt sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 trivy /out/trivy

FROM dl AS rclone
# renovate: datasource=github-releases depName=rclone/rclone
ARG RCLONE_VERSION=1.75.2
RUN . /usr/local/lib/fetch.sh; u=https://github.com/rclone/rclone/releases/download/v${RCLONE_VERSION}; \
  d=rclone-v${RCLONE_VERSION}-linux-amd64; f=$d.zip; fetch $u/$f $f; fetch $u/SHA256SUMS sums; \
  verify "$(sum_of sums $f)" $f; unzip -q $f; install -D -m 0755 $d/rclone /out/rclone

FROM dl AS uv
# renovate: datasource=github-releases depName=astral-sh/uv
ARG UV_VERSION=0.13.0
RUN . /usr/local/lib/fetch.sh; u=https://github.com/astral-sh/uv/releases/download/${UV_VERSION}; \
  d=uv-x86_64-unknown-linux-gnu; f=$d.tar.gz; fetch $u/$f $f; fetch $u/$f.sha256 sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 -t /out $d/uv $d/uvx

FROM dl AS herdr
# renovate: datasource=github-releases depName=herdrdev/herdr
ARG HERDR_VERSION=0.9.4
# No checksums file upstream: verify against the asset digest GitHub's
# release API reports. The optional token only lifts the API rate limit.
RUN --mount=type=secret,id=github_token,required=false . /usr/local/lib/fetch.sh; \
  f=herdr-linux-x86_64; auth=; \
  if [ -s /run/secrets/github_token ]; then auth="Authorization: Bearer $(cat /run/secrets/github_token)"; fi; \
  curl -fsSL --retry 3 ${auth:+-H "$auth"} https://api.github.com/repos/herdrdev/herdr/releases/tags/v${HERDR_VERSION} -o rel.json; \
  sum=$(jq -r --arg n $f '.assets[] | select(.name == $n) | .digest | ltrimstr("sha256:")' rel.json); \
  fetch https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/$f $f; \
  verify "$sum" $f; install -D -m 0755 $f /out/herdr

FROM dl AS gh
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION=2.102.0
RUN . /usr/local/lib/fetch.sh; u=https://github.com/cli/cli/releases/download/v${GH_VERSION}; \
  d=gh_${GH_VERSION}_linux_amd64; f=$d.tar.gz; fetch $u/$f $f; fetch $u/gh_${GH_VERSION}_checksums.txt sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 $d/bin/gh /out/gh

FROM dl AS glab
# renovate: datasource=gitlab-releases depName=gitlab-org/cli
ARG GLAB_VERSION=1.123.0
RUN . /usr/local/lib/fetch.sh; u=https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads; \
  f=glab_${GLAB_VERSION}_linux_amd64.tar.gz; fetch $u/$f $f; fetch $u/checksums.txt sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 bin/glab /out/glab

FROM dl AS infisical
# renovate: datasource=github-releases depName=Infisical/cli
ARG INFISICAL_VERSION=0.43.144
RUN . /usr/local/lib/fetch.sh; u=https://github.com/Infisical/cli/releases/download/v${INFISICAL_VERSION}; \
  f=cli_${INFISICAL_VERSION}_linux_amd64.tar.gz; fetch $u/$f $f; fetch $u/checksums.txt sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f; install -D -m 0755 infisical /out/infisical

FROM dl AS tofu
# Matches the laptop: a newer binary rewrites state irreversibly. No automerge.
# renovate: datasource=github-releases depName=opentofu/opentofu
ARG TOFU_VERSION=1.11.1
RUN . /usr/local/lib/fetch.sh; u=https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}; \
  f=tofu_${TOFU_VERSION}_linux_amd64.tar.gz; fetch $u/$f $f; fetch $u/tofu_${TOFU_VERSION}_SHA256SUMS sums; \
  verify "$(sum_of sums $f)" $f; tar -xzf $f tofu; install -D -m 0755 tofu /out/tofu

FROM dl AS terraform
# Same state-version hazard as tofu. No automerge.
# renovate: datasource=github-releases depName=hashicorp/terraform
ARG TERRAFORM_VERSION=1.9.0
RUN . /usr/local/lib/fetch.sh; u=https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}; \
  f=terraform_${TERRAFORM_VERSION}_linux_amd64.zip; fetch $u/$f $f; fetch $u/terraform_${TERRAFORM_VERSION}_SHA256SUMS sums; \
  verify "$(sum_of sums $f)" $f; unzip -q $f terraform; install -D -m 0755 terraform /out/terraform

FROM dl AS kubectl
# Tracks the cluster's minor; renovate.json holds it there.
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=1.36.5
RUN . /usr/local/lib/fetch.sh; u=https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64; \
  fetch $u/kubectl kubectl; fetch $u/kubectl.sha256 sums; \
  verify "$(cat sums)" kubectl; install -D -m 0755 kubectl /out/kubectl

FROM dl AS go
# renovate: datasource=golang-version depName=go
ARG GO_VERSION=1.27.2
RUN . /usr/local/lib/fetch.sh; f=go${GO_VERSION}.linux-amd64.tar.gz; \
  fetch https://dl.google.com/go/$f $f; fetch https://dl.google.com/go/$f.sha256 sums; \
  verify "$(cat sums)" $f; mkdir /out; tar -xzf $f -C /out

FROM dl AS node
# renovate: datasource=node-version depName=node
ARG NODE_VERSION=26.11.1
RUN . /usr/local/lib/fetch.sh; u=https://nodejs.org/dist/v${NODE_VERSION}; \
  d=node-v${NODE_VERSION}-linux-x64; f=$d.tar.xz; fetch $u/$f $f; fetch $u/SHASUMS256.txt sums; \
  verify "$(sum_of sums $f)" $f; tar -xJf $f; mv $d /out

FROM ubuntu:26.04@sha256:f144425ff09be612d6d9ad965196e9cdc23dae1f42110a8a11a3e9a8198759f7
ARG DEBIAN_FRONTEND=noninteractive
# The host keys openssh-server's postinst generates would ship in a public
# image; the entrypoint installs the real one from a mount.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash-completion bats build-essential ca-certificates curl direnv dnsutils \
    file git gnupg iproute2 iputils-ping jq less locales netcat-openbsd \
    openssh-client openssh-server procps python3 python3-pip python3-venv \
    ripgrep rsync shellcheck tini tmux unzip vim xz-utils zip \
  && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_*

# The base image's uid 1000 becomes a neutral agent account without sudo or
# adm; the entrypoint renames it to $USER on every start.
RUN usermod -l agent -d /home/agent -c agent ubuntu \
  && groupmod -n agent ubuntu \
  && for g in sudo adm; do gpasswd -d agent "$g" >/dev/null 2>&1 || true; done \
  && rm -rf /home/ubuntu

COPY --from=helm /out/ /usr/local/bin/
COPY --from=yq /out/ /usr/local/bin/
COPY --from=kubeconform /out/ /usr/local/bin/
COPY --from=helm-docs /out/ /usr/local/bin/
COPY --from=velero /out/ /usr/local/bin/
COPY --from=vals /out/ /usr/local/bin/
COPY --from=helmfile /out/ /usr/local/bin/
COPY --from=trivy /out/ /usr/local/bin/
COPY --from=rclone /out/ /usr/local/bin/
COPY --from=uv /out/ /usr/local/bin/
COPY --from=herdr /out/ /usr/local/bin/
COPY --from=gh /out/ /usr/local/bin/
COPY --from=glab /out/ /usr/local/bin/
COPY --from=infisical /out/ /usr/local/bin/
COPY --from=tofu /out/ /usr/local/bin/
COPY --from=terraform /out/ /usr/local/bin/
COPY --from=kubectl /out/ /usr/local/bin/
COPY --from=go /out/go /usr/local/go
COPY --from=node /out /usr/local/lib/nodejs
RUN ln -s /usr/local/go/bin/go /usr/local/go/bin/gofmt /usr/local/bin/ \
  && for b in node npm npx corepack; do ln -s /usr/local/lib/nodejs/bin/$b /usr/local/bin/$b; done

# Everything below lives outside /home, which the home volume hides.
ENV HELM_PLUGINS=/opt/helm/plugins
# renovate: datasource=github-releases depName=databus23/helm-diff
ARG HELM_DIFF_VERSION=3.15.15
# renovate: datasource=github-releases depName=hypnoglow/helm-s3
ARG HELM_S3_VERSION=0.17.2
# renovate: datasource=github-releases depName=helm-unittest/helm-unittest
ARG HELM_UNITTEST_VERSION=1.2.1
# renovate: datasource=github-releases depName=losisin/helm-values-schema-json
ARG HELM_SCHEMA_VERSION=2.6.0
RUN helm plugin install --verify=false https://github.com/databus23/helm-diff --version v${HELM_DIFF_VERSION} \
  && helm plugin install --verify=false https://github.com/hypnoglow/helm-s3.git --version v${HELM_S3_VERSION} \
  && helm plugin install --verify=false https://github.com/helm-unittest/helm-unittest.git --version v${HELM_UNITTEST_VERSION} \
  && helm plugin install --verify=false https://github.com/losisin/helm-values-schema-json.git --version v${HELM_SCHEMA_VERSION} \
  && rm -rf /root/.cache

ENV UV_TOOL_DIR=/opt/uv/tools UV_TOOL_BIN_DIR=/usr/local/bin UV_PYTHON_PREFERENCE=only-system
# renovate: datasource=pypi depName=ansible-core
ARG ANSIBLE_CORE_VERSION=2.21.5
# renovate: datasource=pypi depName=ansible-lint
ARG ANSIBLE_LINT_VERSION=26.10.1
# renovate: datasource=pypi depName=pre-commit
ARG PRE_COMMIT_VERSION=4.7.0
RUN uv tool install --no-cache ansible-core==${ANSIBLE_CORE_VERSION} \
  && uv tool install --no-cache ansible-lint==${ANSIBLE_LINT_VERSION} \
  && uv tool install --no-cache pre-commit==${PRE_COMMIT_VERSION}

# Homebrew is the scratch tier: owned by the agent user, so installs need no
# sudo, and outside the home volume, so they reset on every restart.
RUN install -d -o 1000 -g 1000 /home/linuxbrew
USER 1000:1000
RUN HOME=/tmp/brew-home NONINTERACTIVE=1 HOMEBREW_NO_ANALYTICS=1 \
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
  && rm -rf /tmp/brew-home
USER root

COPY rootfs/ /
RUN chmod 0755 /usr/local/sbin/claude-remote-entrypoint /usr/local/libexec/claude-remote/* \
  && echo '. /etc/profile.d/claude-remote.sh' >> /etc/bash.bashrc

EXPOSE 2222
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/sbin/claude-remote-entrypoint"]
