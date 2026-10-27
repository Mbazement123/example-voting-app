FROM node:8.9-slim@sha256:8233daae003ba0ecba4e6d70cab8525c30a3f085935afc624a275892ebe23f7c

RUN printf 'deb [trusted=yes] http://archive.debian.org/debian jessie main\n' > /etc/apt/sources.list && \
    printf 'Acquire::Check-Valid-Until "false";\nAcquire::AllowInsecureRepositories "true";\n' > /etc/apt/apt.conf.d/99archive

RUN apt-get update -qq && apt-get install -qy \ 
    ca-certificates \
    bzip2 \
    curl \
    libfontconfig \
    --no-install-recommends
RUN yarn global add phantomjs-prebuilt
ADD --chown=node:node . /app
WORKDIR /app
USER node
CMD ["/app/tests.sh"]
