#!/usr/bin/env bash
# Arms --with-style-menu. Pass --yes to skip prompts.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$here/install.sh" --with-style-menu "$@"
