# Based on python:alpine as of February 2021
FROM github/super-linter:v3.14.5

LABEL org.opencontainers.image.authors="Jon Zeolla"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="Seiso"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.title="goat"
LABEL org.opencontainers.image.description="The Grand Opinionated AutoTester (GOAT) automatically applies Seiso's standard testing"
LABEL org.opencontainers.image.url="https://seisollc.com"
LABEL org.opencontainers.image.source="https://github.com/SeisoLLC/goat"
LABEL org.opencontainers.image.revision="${COMMIT_HASH}"

WORKDIR /tmp/lint/

ENV PIP_NO_CACHE_DIR=1
COPY Pipfile.lock Pipfile.lock
RUN pipenv install --system --deploy --ignore-pipfile

COPY etc/ /etc/opt/goat/
COPY entrypoint.sh /opt/goat/bin/entrypoint.sh

ENTRYPOINT ["/opt/goat/bin/entrypoint.sh"]
