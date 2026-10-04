---
uid: T35T5M
description: >-
  Owns fast verification of Moria-specific image contracts that can be exercised
  without downloading or launching the upstream dedicated server.
---

# Tests

Tests here verify the Moria derivative's own behavior. They do not duplicate the
shared SteamCMD base image's lifecycle tests.

`test_moria_hook.sh` exercises the one-time `vcrun2022` initialization,
persistence migration, repair of a correct-but-dangling Saved symlink, native
INI projection, unknown-setting preservation, idempotence, and the PE
console-subsystem patch using synthetic dependencies and an executable header.

`test_moria_wine_wrapper.sh` verifies that the Moria Wine adapter invokes Wine
directly when no architecture prefix is required and composes Box64-style
architecture prefixes for Wine and wineserver when required.
