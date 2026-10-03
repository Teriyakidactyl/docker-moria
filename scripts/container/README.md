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

`moria-wine-wrapper.sh` provides Moria's Winetricks-compatible Wine and
wineserver entry points. It invokes Wine directly on amd64 and composes the
shared `ARCH_COMMAND_PREFIX` on architectures such as arm64.

`moria-healthcheck.sh` verifies the supervised process and Moria's local UDP
protocol response.

Game-specific lifecycle mutation routes through
[`hooks/README.md`](hooks/README.md).
