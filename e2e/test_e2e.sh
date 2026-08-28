#!/usr/bin/env bash
set -euo pipefail

export MIX_ENV=e2e

mix ecto.create --quiet
mix ecto.migrate
pnpm --dir playwright exec playwright test "$@"
