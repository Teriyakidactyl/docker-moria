# trixie_wine-staging is intentionally a floating *supported* base alias. The
# shared base only moves that alias after its architecture/runtime publication
# gates pass, so rebuilding Moria adopts a validated Wine/runtime repair without
# copying Wine version policy into this derivative. Override BASE_TAG with a
# versioned tag only when an intentionally pinned derivative release is needed.
ARG BASE_IMAGE=ghcr.io/teriyakidactyl/docker-steamcmd-server
ARG BASE_TAG=trixie_wine-staging

FROM ${BASE_IMAGE}:${BASE_TAG}

# Re-declare pre-FROM args so they are available to image metadata below.
ARG BASE_IMAGE
ARG BASE_TAG
ARG WINETRICKS_REF=f3890f670867b5ffbc3938726db45c0f7d16c8ba

LABEL org.opencontainers.image.title="Return to Moria Dedicated Server" \
      org.opencontainers.image.description="Return to Moria dedicated server based on docker-steamcmd-server" \
      org.opencontainers.image.vendor="TeriyakiDactyl" \
      org.opencontainers.image.source="https://github.com/Teriyakidactyl/docker-moria" \
      org.opencontainers.image.base.name="${BASE_IMAGE}:${BASE_TAG}"

ENV APP_NAME="moria" \
    APP_EXE="MoriaServer-Win64-Shipping.exe" \
    APP_EXECUTABLE="/app/Moria/Binaries/Win64/MoriaServer-Win64-Shipping.exe" \
    APP_PROCESS_NAME="MoriaServer-Win64-Shipping.exe" \
    APP_LOG_NAME="moria-server" \
    APP_ARGS_FILE="/usr/local/share/moria/moria.args" \
    APP_STOP_SIGNAL="INT" \
    SHUTDOWN_TIMEOUT="25" \
    STEAM_SERVER_APPID="3349480" \
    STEAM_PLATFORM_TYPE="windows" \
    SERVER_LISTEN_ADDRESS="0.0.0.0" \
    SERVER_PORT="7777" \
    SERVER_ADVERTISE_ADDRESS="" \
    SERVER_ADVERTISE_PORT="7777" \
    SERVER_PASS="" \
    WORLD_NAME="Moria Docker World" \
    WORLD_FILE="" \
    SERVER_WORKER_THREADS="4"

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends cabextract; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /usr/local/share/moria "${HOOK_DIRECTORIES}/pre-startup"; \
    curl --fail --show-error --silent --location \
        --retry 5 --retry-all-errors --connect-timeout 15 \
        "https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_REF}/src/winetricks" \
        --output /usr/local/bin/winetricks; \
    chmod 0755 /usr/local/bin/winetricks; \
    chown root:root /usr/local/bin/winetricks /usr/local/share/moria "${HOOK_DIRECTORIES}/pre-startup"; \
    chmod 0755 /usr/local/share/moria "${HOOK_DIRECTORIES}/pre-startup"

COPY scripts/container/moria.args /usr/local/share/moria/moria.args
COPY scripts/container/moria-healthcheck.sh /usr/local/bin/moria-healthcheck
COPY scripts/container/moria-wine-wrapper.sh /usr/local/bin/moria-wine
COPY scripts/container/hooks/pre-startup/30_moria.sh ${HOOK_DIRECTORIES}/pre-startup/30_moria.sh

RUN ln -sf /usr/local/bin/moria-wine /usr/local/bin/moria-wine64 && \
    ln -sf /usr/local/bin/moria-wine /usr/local/bin/moria-wineserver && \
    chown root:root \
        /usr/local/share/moria/moria.args \
        /usr/local/bin/moria-healthcheck \
        /usr/local/bin/moria-wine \
        "${HOOK_DIRECTORIES}/pre-startup/30_moria.sh" && \
    chmod 0644 /usr/local/share/moria/moria.args && \
    chmod 0755 \
        /usr/local/bin/moria-healthcheck \
        /usr/local/bin/moria-wine \
        "${HOOK_DIRECTORIES}/pre-startup/30_moria.sh"

USER ${CONTAINER_USER}

EXPOSE 7777/udp

HEALTHCHECK --interval=1m --timeout=10s --start-period=10m --retries=3 \
    CMD ["/usr/local/bin/moria-healthcheck"]
