FROM ghcr.io/yannh/kubeconform:v0.6.1 as kubeconform
FROM hadolint/hadolint:v2.12.0-alpine as hadolint
FROM koalaman/shellcheck:v0.9.0 as shellcheck
FROM rhysd/actionlint:1.6.24 as actionlint

FROM python:3.10-alpine3.18 as base_image

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

ARG COMMIT_HASH

LABEL org.opencontainers.image.title="goat"
LABEL org.opencontainers.image.description="The Grand Opinionated AutoTester (GOAT) automatically applies Seiso's standard testing"
LABEL org.opencontainers.image.version="${COMMIT_HASH}"
LABEL org.opencontainers.image.vendor="Seiso"
LABEL org.opencontainers.image.url="https://seisollc.com"
LABEL org.opencontainers.image.source="https://github.com/SeisoLLC/goat"
LABEL org.opencontainers.image.revision="${COMMIT_HASH}"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /etc/opt/goat/
ENV PIP_NO_CACHE_DIR=1
ENV WORKON_HOME=/tmp
ENV PATH="$HOME/.pyenv/bin:$PATH"
COPY Pipfile Pipfile.lock ./
COPY --from=kubeconform /kubeconform /usr/bin/
COPY --from=hadolint /bin/hadolint /usr/bin/
COPY --from=shellcheck /bin/shellcheck /usr/bin/
COPY --from=actionlint /usr/local/bin/actionlint /usr/bin/

# hadolint ignore=DL3016,DL3018,DL3013
RUN pip install pipenv \
    && pipenv install --system --deploy --ignore-pipfile \
    && apk upgrade \
    && apk --no-cache add go \
    jq \
    npm \
    tini \
    bash \
    git \
    && npm install --save-dev --no-cache -g dockerfile_lint \
    markdownlint-cli \
    textlint \
    textlint-filter-rule-allowlist \
    textlint-filter-rule-comments \
    textlint-rule-terminology \
    cspell \
    jscpd \
    markdown-link-check \
    && mkdir -p /opt/goat/log \
    # The following commands are necessary because pre-commit adds -u os.uid():os.gid() to the docker run
    && chmod o+w /opt/goat/log \
    && mkdir -p /.local \
    && chmod o+w /.local \
    && git clone https://github.com/pyenv/pyenv.git --depth=1 ~/.pyenv \
    && echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.profile \
    && echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.profile \
    && echo 'eval "$(pyenv init -)"' >> ~/.profile \
    && find $PYENV_ROOT -type d -name ".git" -exec rm -rf {} +

WORKDIR /goat/

COPY etc/ /etc/opt/goat/
COPY entrypoint.sh /opt/goat/bin/entrypoint.sh

ENTRYPOINT ["tini", "-g", "--", "/opt/goat/bin/entrypoint.sh"]
