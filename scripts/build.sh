#!/usr/bin/env sh
#
# build.sh <checkout-dir> [<version>]
#
# Produces:
#   - Python wheel + sdist under <checkout-dir>/dist/ via `uv build`
#   - (optional) Docker image tagged litellm-libre:<version> if $BUILD_DOCKER=1
#
# The version, if passed, is written into pyproject.toml so the artifact carries
# the libre suffix (e.g. 1.92.0+libre.1). If omitted, uv build uses whatever the
# checkout already declares.
#
set -eu

root="${1:?usage: build.sh <checkout-dir> [<version>]}"
version="${2:-}"

cd "$root"

if [ -n "$version" ]; then
    # In-place edit of the two version strings pyproject uses (project.version
    # and tool.commitizen.version). We match on the exact " " padding to avoid
    # touching version references inside dependency specs.
    python - "$version" <<'PY'
import pathlib
import re
import sys

version = sys.argv[1]
path = pathlib.Path("pyproject.toml")
text = path.read_text()
text = re.sub(r'^version = "[^"]+"$', f'version = "{version}"', text, count=1, flags=re.M)
# tool.commitizen.version is the second occurrence; the previous sub already
# handled project.version, so this one still lands on the commitizen entry.
text = re.sub(r'^version = "[^"]+"$', f'version = "{version}"', text, count=1, flags=re.M)
path.write_text(text)
PY
fi

uv build

if [ "${BUILD_DOCKER:-0}" = "1" ]; then
    image_version="${version:-libre-local}"
    docker build \
        -t "litellm-libre:${image_version}" \
        -t "litellm-libre:latest" \
        -f Dockerfile \
        .
fi

printf 'build: artifacts in %s/dist/\n' "$root"
ls -la "$root/dist" || true
