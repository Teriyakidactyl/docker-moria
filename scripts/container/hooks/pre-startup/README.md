---
uid: PR3ST4
description: >-
  Owns Moria mutations that must occur after the shared SteamCMD update and
  before server launch, including persistence links, native config projection,
  validation, and console-subsystem preparation.
---

# Moria pre-start

`30_moria.sh` runs after the base SteamCMD update hook. It establishes the
`/world` persistence boundary, applies the small environment-variable
configuration projection, and patches the server executable's PE subsystem so
SIGINT can reach Moria's console shutdown path.
