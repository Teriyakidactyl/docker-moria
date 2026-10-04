---
uid: M4R7A2
description: >-
  Owns the Docker image, operator guidance, and repository routing for running
  The Lord of the Rings: Return to Moria dedicated server on the shared
  SteamCMD/Wine base without owning upstream game or dedicated-server behavior.
---

# Return to Moria Dedicated Server

![Teriyakidactyl Delivers!™](/images/teriyakidactyl_moria.png)

**_Teriyakidactyl Delivers!™_**

This repository packages **The Lord of the Rings: Return to Moria** dedicated
server as a non-root Docker container built on
[`docker-steamcmd-server`](https://github.com/Teriyakidactyl/docker-steamcmd-server).

The image deliberately keeps generic SteamCMD, Wine, update, logging, health,
process-lifecycle, and architecture behavior in the shared base. This repository
contains only Moria-specific startup, persistence, configuration, dependency,
and health-check behavior.

## Quick start

```bash
docker compose up -d
docker compose logs -f moria-server
```

The first start downloads the dedicated server through SteamCMD and installs
Moria's required Microsoft Visual C++ 2015–2022 runtime into the persistent Wine
prefix. Application files and compatibility state live in `/app`; durable game
state lives in `/world`. Later starts reuse the initialized prefix.

The default game port is UDP `7777`.

## Configuration

The container exposes every currently known `MoriaServerConfig.ini` setting as
a Docker environment-variable API. The authoritative behavior reference is the
official
[dedicated-server guide](https://www.returntomoria.com/news-updates/dedicated-server)
and
[North Beach Games customization guide](https://northbeachgames.freshdesk.com/support/solutions/articles/154000217143-customizing-your-server).
Durin's Folk upgrade behavior is additionally documented in the official
[DLC migration article](https://northbeachgames.freshdesk.com/support/solutions/articles/154000244719-how-to-update-existing-dedicated-server-saves-for-durin-s-folk).

The image renders these API values into an image-owned desired-state fragment
with `envsubst`, then reconciles only the corresponding section/key pairs into
the persistent `/world/MoriaServerConfig.ini`. Unknown or future native settings
are preserved. When the API values already match, the persistent file is not
replaced.

| Variable | Container default | Native setting | Purpose |
| --- | --- | --- | --- |
| `SERVER_PASS` | empty | `[Main] OptionalPassword` | Optional case-sensitive join password |
| `WORLD_NAME` | `Moria Docker World` | `[World] Name` | World/session name to load or create |
| `WORLD_FILE` | empty | `[World] OptionalWorldFilename` | Select an existing `.sav` explicitly |
| `WORLD_TYPE` | `campaign` | `[World.Create] Type` | New-world type: `campaign` or `sandbox` |
| `WORLD_SEED` | `random` | `[World.Create] Seed` | New-world seed: `random` or an integer |
| `WORLD_DIFFICULTY_PRESET` | `normal` | `[World.Create] Difficulty.Preset` | `story`, `solo`, `normal`, `hard`, or `custom` |
| `WORLD_DIFFICULTY_COMBAT` | `default` | `Difficulty.Custom.CombatDifficulty` | Custom combat difficulty |
| `WORLD_DIFFICULTY_ENEMY_AGGRESSION` | `high` | `Difficulty.Custom.EnemyAggression` | Custom enemy aggression |
| `WORLD_DIFFICULTY_SURVIVAL` | `default` | `Difficulty.Custom.SurvivalDifficulty` | Custom survival difficulty |
| `WORLD_DIFFICULTY_MINING_DROPS` | `default` | `Difficulty.Custom.MiningDrops` | Custom ore drop volume |
| `WORLD_DIFFICULTY_WORLD_DROPS` | `default` | `Difficulty.Custom.WorldDrops` | Custom enemy/world reward drops |
| `WORLD_DIFFICULTY_HORDE_FREQUENCY` | `default` | `Difficulty.Custom.HordeFrequency` | Custom horde frequency |
| `WORLD_DIFFICULTY_SIEGE_FREQUENCY` | `default` | `Difficulty.Custom.SiegeFrequency` | Custom siege frequency |
| `WORLD_DIFFICULTY_PATROL_FREQUENCY` | `default` | `Difficulty.Custom.PatrolFrequency` | Custom patrol frequency |
| `WORLD_OPTIONAL_DLC` | empty | `[World.Create] OptionalDLC.Array` | Optional DLC applied when creating a new world; expansion content is opt-in |
| `WORLD_UPGRADE_OPTIONAL_DLC` | empty | `[World.Create] UpgradeOptionalDLC.Array` | DLC applied to an existing world during upgrade |
| `SERVER_LISTEN_ADDRESS` | `0.0.0.0` | `[Host] ListenAddress` | Address bound inside the container |
| `SERVER_PORT` | `7777` | `[Host] ListenPort` | Internal game port |
| `SERVER_ADVERTISE_ADDRESS` | `auto` | `[Host] AdvertiseAddress` | Address clients are told to connect to; `local` is also supported upstream |
| `SERVER_ADVERTISE_PORT` | `7777` | `[Host] AdvertisePort` | Port clients are told to connect to; `-1` means use `ListenPort` |
| `SERVER_INITIAL_CONNECTION_RETRY_TIME` | `60` | `[Host] InitialConnectionRetryTime` | Seconds to retry initial hosting |
| `SERVER_AFTER_DISCONNECTION_RETRY_TIME` | `600` | `[Host] AfterDisconnectionRetryTime` | Seconds to retry after a hosted session drops |
| `SERVER_CONSOLE_ENABLED` | `true` | `[Console] Enabled` | Enable Moria's native console |
| `SERVER_FPS` | `60` | `[Performance] ServerFPS` | Dedicated-server tick/FPS target |
| `SERVER_LOADED_AREA_LIMIT` | `12` | `[Performance] LoadedAreaLimit` | Loaded-area cap, from 4 through 32 |
| `SERVER_WORKER_THREADS` | `4` | command line `-NumServerWorkerThreads` | Worker thread count, from 1 through 4 |
| `SERVER_PUBLISHED_PORT` | `7777` | Docker port publishing only | Host UDP port used by the supplied Compose file |
| `STEAM_VALIDATE` | `false` | SteamCMD behavior | Validate installed depot during startup update |
| `UPDATE_ON_START` | `true` | SteamCMD behavior | Check/update the dedicated server before launch |

The custom difficulty fields accept `verylow`, `low`, `default`, `high`,
or `veryhigh`; upstream may clamp unsupported extremes for individual
categories. `WORLD_OPTIONAL_DLC` is deliberately empty by default so a new
server remains joinable by base-game players. Set it explicitly only when the
new world is intended to require that expansion.

Container defaults are the Docker-facing contract and are called out separately
from upstream defaults where they intentionally differ. In particular, the
container retains `SERVER_LISTEN_ADDRESS=0.0.0.0` and
`SERVER_ADVERTISE_PORT=7777` for backward compatibility even though current
native examples use the bind-all empty address and may use `-1` for
`AdvertisePort`; both native forms are supported by the hook.

> [!CAUTION]
> Optional DLC is opt-in. Enabling `WORLD_OPTIONAL_DLC` on creation makes the
> resulting world require that expansion, and North Beach Games documents
> existing-world DLC upgrades as irreversible. `WORLD_UPGRADE_OPTIONAL_DLC`
> therefore also remains empty by default. Back up an existing world before
> deliberately upgrading it.

> [!WARNING]
> `SERVER_CONSOLE_ENABLED=false` disables the console path Moria uses to
> process the container's graceful `SIGINT` shutdown. The image accepts the
> upstream setting for API completeness, but container stop may then escalate to
> `SIGKILL` without a graceful save.

The permissions and join-message files remain durable and outside the INI API:

```text
/world/MoriaServerPermissions.txt
/world/MoriaServerRules.txt
```

## Persistence

The image uses the shared game-server persistence contract:

| Path | Role |
| --- | --- |
| `/app` | Steam-installed application files, Steam state, persistent Wine prefix, and Moria compatibility dependencies |
| `/world` | Moria configuration, saves, logs, status, and other game-owned state |

Moria's `Moria/Saved` directory is linked into `/world/Saved`. The top-level
server configuration, permissions, and rules files are linked individually into
`/world`.

A typical Compose deployment uses named volumes for both paths.

## Networking

Moria listens on UDP `7777` by default. `SERVER_PORT` controls the internal
container listen port, `SERVER_PUBLISHED_PORT` controls the host-side UDP port
in the supplied Compose file, and `SERVER_ADVERTISE_PORT` is the native value
reported to clients. Keep the published and advertised values aligned when
using NAT or a non-default external port. `SERVER_ADVERTISE_ADDRESS=auto`
retains upstream public-address discovery; `local` requests local-address
discovery for LAN-only play.

Direct joins require the host/network path to permit the configured UDP port.
Invite-code joins still depend on the upstream online services used by the
dedicated server.

## Lifecycle and health

The server executable is installed from Steam AppID `3349480` for the Windows
platform and runs under the Wine variant of `docker-steamcmd-server`.

After the shared base initializes the persistent Wine prefix, the Moria pre-start
hook installs `vcrun2022` with a commit-pinned Winetricks script. The install is
Moria-specific and idempotent; the shared Wine base remains game-agnostic.

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

When changing canonical source, begin at this README, follow any README ancestry
to the target, and keep generic runtime behavior in the shared SteamCMD base
rather than duplicating it in the Moria image.

Changes should preserve these boundaries:

- the Dockerfile describes Moria-specific image/runtime defaults and packaged
  prerequisites;
- the pre-start hook owns Moria compatibility initialization, persistence,
  native configuration, and the console-subsystem patch;
- the health-check script owns Moria protocol readiness;
- CI validates the derivative image without reimplementing the base image's
  generic lifecycle; and
- operator-facing behavior is documented here before release.
