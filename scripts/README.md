---
uid: SCR1PT
description: >-
  Owns Moria-specific container support scripts and routes lifecycle helpers
  without acquiring generic SteamCMD base-runtime responsibilities.
---

# Scripts

This directory contains executable support owned by the Moria derivative image.

Generic SteamCMD, Wine, process supervision, logging, and scheduling behavior
belongs in `docker-steamcmd-server`. Moria-specific container runtime behavior
routes through [`container/README.md`](container/README.md).
