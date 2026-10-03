---
uid: H00K5S
description: >-
  Owns Moria lifecycle-hook grouping and routes hook behavior by base-runtime
  lifecycle phase.
---

# Container hooks

Hooks in this directory are sourced by `docker-steamcmd-server` lifecycle
phases. They may specialize Moria behavior but must not duplicate generic base
update, Wine, logging, or process-supervision responsibilities.

Pre-start behavior routes through
[`pre-startup/README.md`](pre-startup/README.md).
