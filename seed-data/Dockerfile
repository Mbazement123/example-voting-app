FROM python:3.9-slim@sha256:2d97f6910b16bd338d3060f261f53f144965f755599aab1acda1e13cf1731b1b

# add apache bench (ab) tool
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    apache2-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /seed

COPY --chown=10001:10001 . .

# create POST data files with ab friendly formats
RUN python make-data.py

USER 10001:10001
CMD ["/seed/generate-votes.sh"]
