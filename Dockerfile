FROM ubuntu:22.04

ARG RAILWAY_GIT_COMMIT_SHA
ENV SOURCE_MANIFEST_REVISION=${RAILWAY_GIT_COMMIT_SHA}
ENV DEBIAN_FRONTEND=noninteractive \
    REPO_URL=https://gerrit.googlesource.com/git-repo \
    REPO_REV=refs/tags/v2.71 \
    PATH=/usr/local/bin:/usr/bin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    bc bison build-essential ca-certificates ccache curl flex gcc-multilib g++-multilib \
    git git-lfs gnupg gperf \
    imagemagick lib32gcc-s1 lib32ncurses5-dev lib32readline-dev lib32stdc++6 \
    libc6-dev-i386 lib32z1-dev libelf-dev liblz4-tool libncurses5-dev libssl-dev libxml2 \
    libxml2-utils lz4 lzop make openjdk-17-jdk pngcrush \
    python3 python-is-python3 python3-setuptools rsync schedtool squashfs-tools \
    unzip xsltproc zip zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

ARG REPO_COMMIT=338ddb7d83ea35d5aef94d3c5d95c74fa3845780
RUN git clone --depth=1 --branch v2.71 https://gerrit.googlesource.com/git-repo /tmp/git-repo \
    && test "$(git -C /tmp/git-repo rev-parse HEAD)" = "$REPO_COMMIT" \
    && install -m 0755 /tmp/git-repo/repo /usr/local/bin/repo \
    && rm -rf /tmp/git-repo

ARG GH_VERSION=2.103.3
ARG GH_DEB_SHA256=e3bafef96328d1a67de3a968bdfe1cc2ffd58cf6aba8b5e201356897ed06bb3d
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.deb" -o /tmp/gh.deb \
    && echo "${GH_DEB_SHA256}  /tmp/gh.deb" | sha256sum -c - \
    && dpkg -i /tmp/gh.deb \
    && rm -f /tmp/gh.deb

WORKDIR /opt/manifest
COPY . /opt/manifest
RUN chmod 0755 /opt/manifest/scripts/railway-build.sh /opt/manifest/scripts/prepare-kernel.sh

ENTRYPOINT ["/opt/manifest/scripts/railway-build.sh"]
