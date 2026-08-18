FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    TMUX_TMPDIR=/run

ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        curl \
        docker.io \
        git \
        grep \
        gawk \
        iproute2 \
        jq \
        ncurses-bin \
        openssl \
        procps \
        python3 \
        sed \
        tmux \
        util-linux \
        wget \
        whiptail \
        zip \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && case "$TARGETARCH" in \
        amd64) \
            TTYD_ASSET="x86_64"; \
            TTYD_SHA256="8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55" \
            ;; \
        arm64) \
            TTYD_ASSET="aarch64"; \
            TTYD_SHA256="b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165" \
            ;; \
        *) \
            echo "Arquitetura não suportada: $TARGETARCH" >&2; \
            exit 1 \
            ;; \
    esac \
    && curl -fsSL \
        "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD_ASSET}" \
        -o /usr/local/bin/ttyd \
    && echo "${TTYD_SHA256}  /usr/local/bin/ttyd" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/ttyd

COPY web/terminal-bridge.js /usr/local/share/ttyd/terminal-bridge.js
COPY prepare-ttyd-index.sh /usr/local/bin/prepare-ttyd-index
COPY terminal-menu.sh /usr/local/bin/setupmno-terminal-menu
COPY configure-control.sh /usr/local/bin/setupmno-control-configure

RUN chmod 0755 \
        /usr/local/bin/prepare-ttyd-index \
        /usr/local/bin/setupmno-terminal-menu \
        /usr/local/bin/setupmno-control-configure \
    && /usr/local/bin/prepare-ttyd-index \
        /usr/local/share/ttyd/terminal-bridge.js \
        /usr/local/share/ttyd/index.html \
    && rm \
        /usr/local/bin/prepare-ttyd-index \
        /usr/local/share/ttyd/terminal-bridge.js

EXPOSE 7681

ENTRYPOINT ["ttyd", "-I", "/usr/local/share/ttyd/index.html"]
