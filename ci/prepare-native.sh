#!/usr/bin/env bash
# Execute only inside an isolated checkout of Antares v0.4.0 on a trusted Linux builder.
set -Eeuo pipefail
export LC_ALL=C
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_dir=$(cd -- "$script_dir/.." && pwd -P)
engine_dir=$(pwd -P)
[[ "$engine_dir" == "$project_dir/native-engine" ]] || { echo 'ERROR: expected dedicated native-engine checkout' >&2; exit 2; }
[[ -f "$engine_dir/Cargo.lock" && -f "$engine_dir/Cargo.toml" && -f "$engine_dir/mach" ]] || { echo 'ERROR: not an Antares root' >&2; exit 2; }
[[ $(git rev-parse HEAD) == 0dd9e2ab9f8250ba65622c9a9ee3cc926f37c2a0 ]] || { echo 'ERROR: Antares ref mismatch' >&2; exit 3; }
patch_file="$project_dir/patches/mozjs-android-tagged-private-pointer.patch"
echo '7e3f092118644aebaff24814faf4f1156860407900a7235171b392b6911f41ca  '"$patch_file" | sha256sum --check --status
# Exact Rust crate and checksum come from the immutable Antares v0.4.0 Cargo.lock.
crate_url=https://static.crates.io/crates/mozjs_sys/mozjs_sys-153.0.0-1.crate
crate_checksum=04127e43d8b292e7d5739963d9787e30ecac27e054c75f153f553b5c4c2d3ede
[[ ! -e native ]] || { echo 'ERROR: native override path exists' >&2; exit 4; }
mkdir -p native/mozjs-sys
tmp_file=$(mktemp)
trap 'rm -f -- "$tmp_file"' EXIT
curl --fail --location --show-error --silent --retry 3 --connect-timeout 30 --max-time 900 "$crate_url" -o "$tmp_file"
printf '%s  %s\n' "$crate_checksum" "$tmp_file" | sha256sum --check --status || { echo 'ERROR: mozjs crate SHA mismatch' >&2; exit 5; }
tar -xzf "$tmp_file" --strip-components=1 --directory native/mozjs-sys --no-same-owner --no-same-permissions
[[ -f native/mozjs-sys/src/jsval.rs ]] || { echo 'ERROR: missing expected jsval.rs' >&2; exit 5; }
patch --dry-run --fuzz=0 -p1 -d native < "$patch_file"
patch --fuzz=0 -p1 -d native < "$patch_file"
python3 - <<'PY'
from pathlib import Path
p = Path('Cargo.toml')
s = p.read_text()
header = '[patch.crates-io]\n'
assert s.count(header) == 1, 'Unexpected Cargo.toml patch table'
assert '\nmozjs_sys = { path = "native/mozjs-sys" }\n' not in s
p.write_text(s.replace(header, header + 'mozjs_sys = { path = "native/mozjs-sys" }\n', 1))
PY
# This changes only the temporary worktree lockfile to pin the local patched crate.
cargo update -p mozjs_sys
cargo metadata --locked --format-version=1 --no-deps > /dev/null
printf 'Validated pinned mozjs_sys override.\n'
