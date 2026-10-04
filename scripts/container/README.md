---
uid: CNT4NR
description: >-
  Owns Moria container-runtime support artifacts, including launch arguments,
  Wine architecture adaptation, health probing, and routing to game-specific
  lifecycle hooks.
---

# Container runtime support

`moria.args` defines safe one-argument-per-line launch arguments consumed by
the shared base runtime.

`moria-server-config.owned.ini.in` is the image-owned `envsubst` template for
the complete known Moria INI API. Its comments link the upstream settings and
DLC sources used to establish the native schema/defaults. The pre-start hook
merges only those owned keys into the persistent native file so future
game-added settings remain intact.

`moria-wine-wrapper.sh` provides Moria's Winetricks-compatible Wine and
wineserver entry points. It invokes Wine directly on amd64 and composes the
shared `ARCH_COMMAND_PREFIX` on architectures such as arm64.

`moria-healthcheck.sh` verifies the supervised process and Moria's local UDP
protocol response.

Game-specific lifecycle mutation routes through
[`hooks/README.md`](hooks/README.md).
