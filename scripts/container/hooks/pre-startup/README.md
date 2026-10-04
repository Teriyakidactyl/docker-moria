---
uid: PR3ST4
description: >-
  Owns Moria mutations that must occur after the shared SteamCMD and Wine
  initialization and before server launch, including compatibility dependency
  installation, persistence links, native config projection, validation, and
  console-subsystem preparation.
---

# Moria pre-start

`30_moria.sh` runs after the base SteamCMD update and Wine-prefix hooks. It
installs Moria's `vcrun2022` prerequisite into the persistent Wine prefix on
first use, establishes the `/world` persistence boundary, applies the small
environment-variable configuration projection, and patches the server
executable's PE subsystem so `SIGINT` can reach Moria's console shutdown path.

The Visual C++ install is marked inside the Wine prefix after Winetricks
succeeds, so later starts reuse it while a fresh `/app` volume receives the
dependency automatically.

Persistence convergence validates both sides of the Saved-directory mapping.
An existing `/app/Moria/Saved -> /world/Saved` symlink is not sufficient by
itself: the hook also materializes `/world/Saved` so a retained application
volume cannot leave Moria with a dangling save path when the world volume is
fresh, restored, or incomplete.

The INI projection is intentionally declarative and bounded. The image-owned
`moria-server-config.owned.ini.in` template links the upstream settings sources,
`envsubst` renders an explicit allow-list of validated internal values, and the
hook reconciles only those section/key pairs into the persistent file. Unknown
settings survive game updates, dotted keys are matched literally, and a
converged file is not replaced on every boot.
