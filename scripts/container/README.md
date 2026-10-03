---
uid: CNT4NR
description: >-
  Owns Moria container-runtime support artifacts, including launch arguments,
  health probing, and routing to game-specific lifecycle hooks.
---

# Container runtime support

`moria.args` defines safe one-argument-per-line launch arguments consumed by
the shared base runtime.

`moria-healthcheck.sh` verifies the supervised process and Moria's local UDP
protocol response.

Game-specific lifecycle mutation routes through
[`hooks/README.md`](hooks/README.md).
