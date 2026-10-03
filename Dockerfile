ARG BASE_IMAGE=ghcr.io/teriyakidactyl/docker-steamcmd-server
ARG BASE_TAG=trixie_wine-staging

FROM ${BASE_IMAGE}:${BASE_TAG}

LABEL org.opencontainers.image.title="Return to Moria Dedicated Server" \
      org.opencontainers.image.description="Return to Moria dedicated server based on docker-steamcmd-server" \
      org.opencontainers.image.vendor="TeriyakiDactyl" \
      org.opencontainers.image.source="https://github.com/Teriyakidactyl/docker-moria"

ENV APP_NAME="moria" \
    APP_EXE="MoriaServer-Win64-Shipping.exe" \
    APP_EXECUTABLE="/app/Moria/Binaries/Win64/MoriaServer-Win64-Shipping.exe" \
    APP_PROCESS_NAME="MoriaServer-Win64-Shipping.exe" \
    APP_LOG_NAME="moria-server" \
    APP_ARGS_FILE="/usr/local/share/moria/moria.args" \
    APP_STOP_SIGNAL="INT" \
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

RUN mkdir -p /usr/local/share/moria "${HOOK_DIRECTORIES}/pre-startup" && \
    chown root:root /usr/local/share/moria "${HOOK_DIRECTORIES}/pre-startup" && \
    chmod 0755 /usr/local/share/moria "${HOOK_DIRECTORIES}/pre-startup"

COPY scripts/container/moria.args /usr/local/share/moria/moria.args
COPY scripts/container/moria-healthcheck.sh /usr/local/bin/moria-healthcheck
COPY scripts/container/hooks/pre-startup/30_moria.sh ${HOOK_DIRECTORIES}/pre-startup/30_moria.sh

RUN chown root:root \
        /usr/local/share/moria/moria.args \
        /usr/local/bin/moria-healthcheck \
        "${HOOK_DIRECTORIES}/pre-startup/30_moria.sh" && \
    chmod 0644 /usr/local/share/moria/moria.args && \
    chmod 0755 \
        /usr/local/bin/moria-healthcheck \
        "${HOOK_DIRECTORIES}/pre-startup/30_moria.sh"

USER ${CONTAINER_USER}

EXPOSE 7777/udp

HEALTHCHECK --interval=1m --timeout=10s --start-period=10m --retries=3 \
    CMD ["/usr/local/bin/moria-healthcheck"]
