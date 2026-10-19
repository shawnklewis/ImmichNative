# ImmichNative

Runs Immich natively on Windows (no Docker/WSL). Prototype ports so it can sit beside a live Docker Immich:
Postgres 14 + pgvector on 5433, Redis on 6380, Immich on 2284, ML on 3004 (not yet set up).

- scripts/build-pgvector.cmd - compile pgvector against the portable Postgres (needs MSVC Build Tools)
- scripts/build-immich.ps1   - build Immich v3.3.3 server + web from vendor/immich
- scripts/start-server.ps1   - start the server with the prototype environment
- patches/                   - Windows fixes applied to vendor/immich (git apply from vendor/immich)

vendor/, tools/ (portable Postgres, Redis) and run/ (logs, secrets) are git-ignored.
Known: Redis 5.0.14 (Windows port) only triggers Immich's "recommended 6.2" warning.

## Data layout (everything to back up is on D:)
- D:\ImmichNative\pgdata   live Postgres cluster (don't copy while running; use the dumps)
- D:\ImmichNative\media    photos/videos (back this up)
- D:\ImmichNative\redis    Redis snapshots (dump.rdb; queues only, safe to lose)
- D:\ImmichNative\backups  pg_dump archives from scripts/backup-db.ps1 (keeps 14, verified on write)
- D:\ImmichNative\build    geodata, plugins, web build (rebuildable)
C: holds only programs and source (tools/, vendor/) and the secrets file run/pg.env, which is deliberately not backed up with the data.
Restore: create a database, then pg_restore --no-owner -d <db> <file>.dump.

## Known gaps
- HEIC/HEIF (HEVC) images get no thumbnail: sharp's bundled libvips on Windows has no HEVC decoder (Docker's image builds its own with libde265).
  Only 2 of 5,441 library photos are HEIC; parked on 2026-10-19 to revisit around 2026-10-26.
  Plan when revisited: patch Immich thumbnail generation to fall back to ffmpeg (verified: ffmpeg decodes both files to full 4032x3024 JPEG).
  A native HEVC build is not worth it: sharp has no global-libvips option on Windows, so it would mean rebuilding the sharp-libvips package.

## Supervisor (src/ImmichSupervisor, .NET 10 worker service)
Starts Postgres, Redis and the Immich server in dependency order, waits for each health check, restarts crashed
components with exponential backoff, adopts components that are already running, stops them in reverse order
(Postgres fast-shutdown, Redis save, Node killed), and takes a verified pg_dump nightly at 03:00 (keeps 14).
Config: src/ImmichSupervisor/appsettings.json (Components, Backup). Secrets come from run/pg.env, never from config.
- dotnet test                                   unit tests (restart backoff, start order, secrets, backup plan)
- ImmichSupervisor.exe --check-config           validate config and print start order
- ImmichSupervisor.exe --backup-now             one verified backup
- ImmichSupervisor.exe --run-for <seconds>      run, then shut down gracefully (testing)
- scripts/install-service.ps1 [-Start]          publish + install the Windows service (UAC)
- scripts/uninstall-service.ps1                 remove the service (data untouched)
The service runs as NT AUTHORITY\NetworkService because PostgreSQL refuses to run under an administrative account.
The machine-learning service is intentionally not set up (IMMICH_MACHINE_LEARNING_ENABLED=false).

## Operations
- Redeploy after changing supervisor code or appsettings.json: scripts/redeploy.ps1 (one UAC prompt; logs to C:\ProgramData\ImmichNative\redeploy.log).
  Editing the deployed appsettings.json alone does nothing until the service restarts; a supervisor restart that finds components still
  healthy ADOPTS them with their old environment, so config changes to a component need that component stopped first (redeploy.ps1 does this).
- Logs: D:\ImmichNative\logs (supervisor.log, immich-server.log, redis.log, pg\postgresql.log). Postgres has no console under a service, hence logging_collector.
- Server builds: relocate-runtime.ps1 stages a copy-mode pnpm deploy into C:\ProgramData\ImmichNative\server-<stamp>; redeploy.ps1 (via swap-server.ps1)
  repoints the 'server' junction at it while the service is stopped. Never rename a deploy folder: pnpm writes absolute junction targets.
  Copy mode keeps the files independent of the user's pnpm store (hard links would share permissions with profile files).

## Cutover record (2026-10-19) and rollback
Docker Immich was stopped and its data copied here: database immich_live, library D:\ImmichNative\library, served on 0.0.0.0:2283
(photos.kurtnelle.com reaches it through the Windows cloudflared service, which targets localhost:2283). ML is off.
- Docker Desktop, its WSL distro and its volumes were removed on 2026-10-19, and D:\Immich (the Docker-era library copy, compose files,
  .env and scripts) was deleted after the native library was verified byte-identical and the offsite backup was repointed. The only Docker-era
  artifact kept is D:\ImmichNative\migration\docker-immich-cutover-*.dump. scripts\migrate-from-docker.ps1 is historical and can no longer run.
- The only database is immich_live. Back up D:\ImmichNative\library and D:\ImmichNative\backups; see the offsite backup below.
- Firewall rule 'Immich (native) LAN 2283': inbound TCP 2283, remote LocalSubnet only, node.exe only, all profiles
  (Windows classifies this PC's Ethernet as Public).

## Offsite backup (scripts/offsite-backup.ps1)
Scheduled task 'Immich Offsite Backup' (daily 03:00, runs as the user via S4U) syncs D:\ImmichNative\library (without thumbs/, encoded-video/,
backups/) to gdrive-crypt:current and D:\ImmichNative\backups to gdrive-crypt:current/db-backups. Deleted files are moved to
gdrive-crypt:deleted/<date> and pruned after 91 days. It aborts if the source looks missing/empty and refuses to delete more than 1000 files per run.
Logs: D:\ImmichNative\logs\offsite. Use -DryRun to preview. register-offsite-task.ps1 recreates the task, repoint-offsite-task.ps1 repoints it,
setup-rclone.ps1 creates the crypt remote (the crypt password and salt must be kept in a password manager: without them the backup cannot be decrypted).
