#!/usr/bin/env bash
# Spec 02 check 4, first half: the service's build output and container image hold no recording.
# Usage: no-recordings-in-build.sh <recordings-dir> <publish-dir> <image>
# Fails if either the publish folder or the image's file system contains
#   - a file named like a recording file (*.body, *.meta, _index.tsv, manifest.json, requests.txt), or
#   - a file whose SHA-256 equals that of any recording file of 32 bytes or more (smaller bodies,
#     such as "[]", could match unrelated files by chance), or
#   - the text of any of the ten largest recorded JSON bodies (one line each), anywhere inside a file
#     (an embedded resource).
set -euo pipefail
recordings=$1 publish=$2 image=$3
work=$(mktemp -d)
mkdir "$work/image"
container=$(docker create "$image")
docker export "$container" | tar -x -C "$work/image" 2>/dev/null || true
docker rm "$container" >/dev/null

find "$recordings" -type f -size +31c -exec sha256sum {} + | awk '{print $1}' | sort -u > "$work/recorded.sha"
problems=0
for dir in "$publish" "$work/image"; do
  names=$(find "$dir" -type f \( -name '*.body' -o -name '*.meta' -o -name '_index.tsv' -o -name manifest.json -o -name requests.txt \) | head)
  if [ -n "$names" ]; then echo "recording file names in $dir: $names"; problems=1; fi
  find "$dir" -type f -exec sha256sum {} + 2>/dev/null | awk '{print $1}' | sort -u > "$work/built.sha"
  same=$(comm -12 "$work/recorded.sha" "$work/built.sha" | wc -l)
  if [ "$same" -ne 0 ]; then echo "$same recording files found by hash in $dir"; problems=1; fi
  for body in $(grep -l '^\[' -r "$recordings" --include='*.body' | xargs ls -S | head -10); do
    if grep -rqF -f "$body" "$dir" 2>/dev/null; then echo "the text of $body is inside $dir"; problems=1; fi
  done
  echo "checked $(find "$dir" -type f | wc -l) files in $dir"
done
rm -rf "$work"
exit $problems
