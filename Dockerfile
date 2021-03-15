# Based on python:alpine as of February 2021
FROM github/super-linter:v3.15.2

# Required for the github/super-linter log (cannot be disabled)
RUN mkdir -p /tmp/lint/

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
RUN pipenv install --deploy --ignore-pipfile \
 && apk --no-cache add npm=14.16.0-r0 \
 && npm install --no-cache -g dockerfile_lint@0.3.4 \
                              cspell@5.3.8 \
                              markdown-link-check@3.8.6

WORKDIR /goat/

# LINTER_RULES_PATH is a path relative to GITHUB_WORKSPACE
ENV LINTER_RULES_PATH=../../../../../etc/opt/goat
COPY etc/ /etc/opt/goat/
COPY entrypoint.sh /opt/goat/bin/entrypoint.sh

ENTRYPOINT ["/opt/goat/bin/entrypoint.sh"]
