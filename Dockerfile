FROM ghcr.io/yannh/kubeconform:v0.6.1 as kubeconform
FROM hadolint/hadolint:v2.12.0-alpine as hadolint
FROM koalaman/shellcheck:v0.9.0 as shellcheck
FROM mvdan/shfmt:v3.6.0 as shfmt
FROM rhysd/actionlint:1.6.24 as actionlint

FROM python:3.10-alpine3.17 as base_image

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
COPY Pipfile Pipfile.lock ./
COPY --from=kubeconform /kubeconform /usr/bin/
COPY --from=hadolint /bin/hadolint /usr/bin/
COPY --from=shellcheck /bin/shellcheck /usr/bin/
COPY --from=shfmt /bin/shfmt /usr/bin/
COPY --from=actionlint /usr/local/bin/actionlint /usr/bin/

# hadolint ignore=DL3016,DL3018,DL3013
RUN pip install pipenv \
    && pipenv install --system --deploy --ignore-pipfile \
    && apk upgrade \
    && apk --no-cache add go \
    jq \
    npm \
    tini \
    ruby \
    bash \
    && npm install --save-dev --no-cache -g dockerfile_lint \
    markdownlint-cli \
    textlint \
    textlint-filter-rule-allowlist \
    textlint-filter-rule-comments \
    textlint-rule-terminology \
    textlint-plugin-rst \
    cspell \
    jscpd \
    markdown-link-check \
    && mkdir -p /opt/goat/log

WORKDIR /goat/

# LINTER_RULES_PATH is a path relative to GITHUB_WORKSPACE
ENV LINTER_RULES_PATH=../../../../../etc/opt/goat
COPY etc/ /etc/opt/goat/
COPY entrypoint.sh /opt/goat/bin/entrypoint.sh

ENTRYPOINT ["tini", "-g", "--", "/opt/goat/bin/entrypoint.sh"]
