#!/usr/bin/env bash
# Regenerate the committed `lib/domain.reflection.dart` for this sample.
#
# Only needed when the *shape* of the reflected classes changes (members,
# types, capabilities, annotations) — not when you edit method bodies. After
# running, commit the regenerated file alongside the source change so the
# committed reflection data stays in lockstep.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .dart_tool ]; then
  echo "Fetching dependencies (first run)..." >&2
  dart pub get
fi

dart run build_runner build --delete-conflicting-outputs
