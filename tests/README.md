---
uid: T35T5M
description: >-
  Owns fast verification of Moria-specific image contracts that can be exercised
  without downloading or launching the upstream dedicated server.
---

# Tests

Tests here verify the Moria derivative's own behavior. They do not duplicate the
shared SteamCMD base image's lifecycle tests.

`test_moria_hook.sh` exercises persistence migration, native INI projection,
unknown-setting preservation, idempotence, and the PE console-subsystem patch
using a synthetic executable header.
