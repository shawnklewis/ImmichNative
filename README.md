# ImmichNative

Runs Immich natively on Windows (no Docker/WSL). Prototype ports so it can sit beside a live Docker Immich:
Postgres 14 + pgvector on 5433, Redis on 6380, Immich on 2284, ML on 3004 (not yet set up).

- scripts/build-pgvector.cmd - compile pgvector against the portable Postgres (needs MSVC Build Tools)
- scripts/build-immich.ps1   - build Immich v3.3.3 server + web from vendor/immich
- scripts/start-server.ps1   - start the server with the prototype environment
- patches/                   - Windows fixes applied to vendor/immich (git apply from vendor/immich)

vendor/, tools/ (portable Postgres, Redis) and run/ (logs, secrets) are git-ignored.
Known: Redis 5.0.14 (Windows port) only triggers Immich's "recommended 6.2" warning.
