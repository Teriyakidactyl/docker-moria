---
uid: M4R7A2
description: >-
  Owns the Docker image, operator guidance, and repository routing for running
  The Lord of the Rings: Return to Moria dedicated server on the shared
  SteamCMD/Wine base without owning upstream game or dedicated-server behavior.
---

# Return to Moria Dedicated Server

This repository packages **The Lord of the Rings: Return to Moria** dedicated
server as a non-root Docker container built on
[`docker-steamcmd-server`](https://github.com/Teriyakidactyl/docker-steamcmd-server).

The image deliberately keeps generic SteamCMD, Wine, update, logging, health,
process-lifecycle, and architecture behavior in the shared base. This repository
contains only Moria-specific startup, persistence, configuration, and
health-check behavior.

## Quick start

```bash
docker compose up -d
docker compose logs -f moria-server
```

The first start downloads the dedicated server through SteamCMD. Application
files live in `/app`; durable game state lives in `/world`.

The default game port is UDP `7777`.

## Configuration

The container exposes a small set of common settings and keeps
`MoriaServerConfig.ini` as the complete native configuration surface.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SERVER_PORT` | `7777` | Internal listen and advertised UDP port |
| `SERVER_PASS` | empty | Optional join password |
| `WORLD_NAME` | `Moria Docker World` | World/session name |
| `WORLD_FILE` | empty | Optional existing `.sav` filename |
| `SERVER_WORKER_THREADS` | `4` | Dedicated-server worker thread count, from 1 through 4 |
| `STEAM_VALIDATE` | `false` | Run SteamCMD validation during startup update |
| `UPDATE_ON_START` | `true` | Update the server through SteamCMD before launch |

The Moria-specific pre-start hook creates or updates the common values above
without replacing settings that are not owned by these environment variables.
For advanced settings, stop the container and edit
`/world/MoriaServerConfig.ini` directly.

The permissions and join-message files are also durable:

```text
/world/MoriaServerPermissions.txt
/world/MoriaServerRules.txt
```

## Persistence

The image uses the shared game-server persistence contract:

| Path | Role |
| --- | --- |
| `/app` | Steam-installed application files, Steam state, and persistent Wine prefix |
| `/world` | Moria configuration, saves, logs, status, and other game-owned state |

Moria's `Moria/Saved` directory is linked into `/world/Saved`. The top-level
server configuration, permissions, and rules files are linked individually into
`/world`.

A typical Compose deployment uses named volumes for both paths.

## Networking

Moria listens on UDP `7777` by default. If the externally published port is
changed, set `SERVER_PORT` consistently so Moria advertises the same port that
clients use.

Direct joins require the host/network path to permit the configured UDP port.
Invite-code joins still depend on the upstream online services used by the
dedicated server.

## Lifecycle and health

The server executable is installed from Steam AppID `3349480` for the Windows
platform and runs under the Wine variant of `docker-steamcmd-server`.

Moria's shipping executable is patched after SteamCMD updates so its Windows PE
subsystem exposes a console. The container then sends `SIGINT` during normal
shutdown, allowing Moria to save and close its online session before the shared
base escalates to a forced stop.

The image health check verifies both that the supervised application process is
alive and that the local Moria UDP endpoint responds to the dedicated-server
probe.

## Upstream references

Current Moria server behavior should be checked against the official
[dedicated-server guide](https://www.returntomoria.com/news-updates/dedicated-server)
and
[North Beach Games support documentation](https://northbeachgames.freshdesk.com/support/solutions/folders/154000021108).

This project is an independent containerization and is not an official Return
to Moria image.

## Repository scope

This root README is the repository's semantic entry point. It describes the
operator-facing image contract and routes repository-specific implementation
concerns. Generic SteamCMD/Wine/runtime changes belong in
[`docker-steamcmd-server`](https://github.com/Teriyakidactyl/docker-steamcmd-server),
not here.

Implementation directories carry their own README boundary when they introduce a
separate repository concept. Tool-owned locations such as `.github/` retain
their native control format.

## ✍ Contributing

This repository follows the semantic-routing conventions defined by
[`Repo-Manager`](https://github.com/Teriyakidactyl/Repo-Manager). When changing
canonical source, begin at this README, follow any README ancestry to the target,
and keep generic runtime behavior in the shared SteamCMD base rather than
duplicating it in the Moria image.

Changes should preserve these boundaries:

- the Dockerfile describes Moria-specific image/runtime defaults;
- the pre-start hook owns Moria persistence, native configuration, and the
  console-subsystem patch;
- the health-check script owns Moria protocol readiness;
- CI validates the derivative image without reimplementing the base image's
  generic lifecycle; and
- operator-facing behavior is documented here before release.
