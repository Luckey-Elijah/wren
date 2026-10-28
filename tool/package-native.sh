#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dart_bin=${DART_BIN:-dart}
export DASH__SUPPRESS_ANALYTICS=true
configured_version=$(sed -n 's/^version: *//p' "$repo_root/pubspec.yaml" | head -n 1)
release_version=${1:-$configured_version}

if [ -z "$configured_version" ] || [ "$release_version" != "$configured_version" ]; then
  printf 'Release version %s must match pubspec.yaml version %s.\n' \
    "$release_version" "${configured_version:-<missing>}" >&2
  exit 2
fi

os=$(uname -s)
architecture=$(uname -m)
case "$os:$architecture" in
  Linux:x86_64) host=linux-x64 ;;
  Darwin:arm64|Darwin:aarch64) host=macos-arm64 ;;
  *)
    printf 'Unsupported native build host: %s/%s. Supported hosts are Linux x86_64 and macOS arm64.\n' \
      "$os" "$architecture" >&2
    exit 2
    ;;
esac

stage=$(mktemp -d "${TMPDIR:-/tmp}/wren-package.XXXXXX")
cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT HUP INT TERM

package_dir="$stage/wren-$release_version-$host"
mkdir -p "$package_dir"
cd "$repo_root"
"$dart_bin" compile exe --define=WREN_VERSION="$release_version" \
  bin/wren.dart -o "$package_dir/wren"
chmod 755 "$package_dir/wren"
cp packaging/INSTALL.md "$package_dir/INSTALL.md"

# Smoke the executable and an ordinary offline command before and after packing.
"$package_dir/wren" --help >/dev/null
"$package_dir/wren" list >/dev/null

archive="wren-$release_version-$host.tar.gz"
mkdir -p "$repo_root/dist"
tar -C "$stage" -czf "$repo_root/dist/$archive" "wren-$release_version-$host"
mkdir "$stage/archive-smoke"
tar -xzf "$repo_root/dist/$archive" -C "$stage/archive-smoke"
"$stage/archive-smoke/wren-$release_version-$host/wren" --help >/dev/null
"$stage/archive-smoke/wren-$release_version-$host/wren" list >/dev/null
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$repo_root/dist" && sha256sum "$archive" > "$archive.sha256")
else
  (cd "$repo_root/dist" && shasum -a 256 "$archive" > "$archive.sha256")
fi
printf 'Created dist/%s and its SHA-256 checksum.\n' "$archive"
