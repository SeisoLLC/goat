# syntax=docker/dockerfile:1

# TARGETPLATFORM is special cased by docker and doesn't need the initial ARG
# https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
FROM --platform=$TARGETPLATFORM ghcr.io/yannh/kubeconform:v0.6.7-alpine as kubeconform
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM hadolint/hadolint:v2.12.0-alpine as hadolint
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM koalaman/shellcheck:v0.10.0 as shellcheck
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM rhysd/actionlint:1.7.1 as actionlint

ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM python:3.11-alpine3.20 as base_image

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

ARG COMMIT_HASH

LABEL org.opencontainers.image.title="goat"
LABEL org.opencontainers.image.description="The Grand Opinionated AutoTester (GOAT) automatically applies Seiso's policy as code"
LABEL org.opencontainers.image.version="${COMMIT_HASH}"
LABEL org.opencontainers.image.vendor="Seiso"
LABEL org.opencontainers.image.url="https://seisollc.com"
LABEL org.opencontainers.image.source="https://github.com/SeisoLLC/goat"
LABEL org.opencontainers.image.revision="${COMMIT_HASH}"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /etc/opt/goat/
ENV PIP_NO_CACHE_DIR=1
ENV WORKON_HOME=/tmp
ENV PYENV_ROOT="/root/.pyenv"
ENV PATH="$PYENV_ROOT/bin:$PATH"
COPY Pipfile Pipfile.lock ./
COPY --from=kubeconform /kubeconform /usr/bin/
COPY --from=hadolint /bin/hadolint /usr/bin/
COPY --from=shellcheck /bin/shellcheck /usr/bin/
COPY --from=actionlint /usr/local/bin/actionlint /usr/bin/

# hadolint ignore=DL3016,DL3018,DL3013
RUN pip install pipenv \
    && apk upgrade \
    && apk --no-cache add jq \
                          npm \
                          tini \
                          bash \
                          git \
                          # Added to build supporting binaries
                          libffi-dev \
                          build-base \
                          # The following apk package is necessary for pyenv functionality
                          tk-dev \
    && pipenv install --system --deploy --ignore-pipfile \
    && npm install --save-dev --no-cache -g dockerfile_lint \
                                            markdownlint-cli \
                                            textlint \
                                            textlint-filter-rule-allowlist \
                                            textlint-filter-rule-comments \
                                            textlint-rule-terminology \
                                            cspell \
                                            jscpd \
                                            markdown-link-check@v3.13.4 \
    && git clone https://github.com/pyenv/pyenv.git --depth=1 "${PYENV_ROOT}" \
    && echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.profile \
    && echo 'eval "$(pyenv init -)"' >> ~/.profile \
    # This will cleanup the pyenv .git folder as well as any plugin .git folders
    && find "${PYENV_ROOT}" -type d -name ".git" -exec rm -rf {} + \
    && mkdir -p /opt/goat/log \
    #####################################################################################################
    # The following commands are necessary because pre-commit adds -u os.uid():os.gid() to the docker run
    && chmod o+w /opt/goat/log \
    && mkdir -p /.local \
    && chmod o+w /.local \
    #####################################################################################################
    # Remove unnecessary packages
    && apk del libffi-dev \
                  build-base

WORKDIR /goat/

COPY etc/ /etc/opt/goat/
COPY entrypoint.sh /opt/goat/bin/entrypoint.sh
COPY code_review.py /opt/goat/bin/code_review.py
COPY code_reviews/ /opt/goat/bin/code_reviews/

ENTRYPOINT ["tini", "-g", "--", "/opt/goat/bin/entrypoint.sh"]
