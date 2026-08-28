#!/usr/bin/env bash
set -euo pipefail

export MIX_ENV=e2e

mix deps.get
mix do ecto.create, ecto.migrate
pnpm --dir playwright install
pnpm --dir playwright exec playwright install chromium
