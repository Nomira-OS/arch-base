#!/bin/sh
# Prints the build arguments of the image, one KEY=VALUE per line:
# versions.env plus what follows from the date in the tag of ARCH_IMAGE,
#   SNAPSHOT           the Arch Linux Archive date, YYYY/MM/DD
#   SOURCE_DATE_EPOCH  midnight UTC of that day, for reproducible builds
# Usage: sh hack/build-args.sh [versions.env]
set -eu
env_file="${1:-versions.env}"
# shellcheck source=/dev/null
. "./$env_file"
day="$(printf '%s\n' "$ARCH_IMAGE" | sed -n 's/.*:base-\([0-9]\{8\}\)\..*/\1/p')"
[ -n "$day" ] || { echo "ARCH_IMAGE has no base-YYYYMMDD tag: $ARCH_IMAGE" >&2; exit 1; }
y=${day%????}; md=${day#????}; m=${md%??}; d=${md#??}
grep -E '^[A-Z_]+=' "$env_file"
echo "SNAPSHOT=$y/$m/$d"
echo "SOURCE_DATE_EPOCH=$(date -u -d "$y-$m-$d" +%s)"
