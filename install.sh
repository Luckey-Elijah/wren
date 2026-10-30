#!/usr/bin/env bash
set -Eeuo pipefail

repo='Luckey-Elijah/wren'
api="https://api.github.com/repos/$repo/releases"
downloads="https://github.com/$repo/releases/download"

fail() {
  printf 'Wren installer: %s\n' "$*" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail 'curl is required.'
command -v tar >/dev/null 2>&1 || fail 'tar is required.'

os=$(uname -s)
arch=$(uname -m)
case "$os:$arch" in
  Linux:x86_64|Linux:amd64) host=linux-x64 ;;
  Darwin:arm64|Darwin:aarch64) host=macos-arm64 ;;
  *) fail "unsupported host $os/$arch; Wren supports Linux x86_64 and macOS arm64." ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
  hash_command=sha256sum
elif command -v shasum >/dev/null 2>&1; then
  hash_command='shasum -a 256'
else
  fail 'sha256sum or shasum is required to verify the download.'
fi

newer_version() {
  local candidate=$1 current=$2 a b c x y z
  IFS=. read -r a b c <<< "$candidate"
  IFS=. read -r x y z <<< "$current"
  if ((10#$a > 10#$x)); then return 0; fi
  if ((10#$a < 10#$x)); then return 1; fi
  if ((10#$b > 10#$y)); then return 0; fi
  if ((10#$b < 10#$y)); then return 1; fi
  ((10#$c > 10#$z))
}

printf 'Finding the highest stable Wren release...\n'
latest=''
for page in {1..20}; do
  response=$(curl -fsSL -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' "$api?per_page=100&page=$page") \
    || fail 'could not read Wren releases from GitHub.'
  tags=$(printf '%s\n' "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"wren-v\([^"]*\)".*/\1/p')
  [[ -n $tags ]] || break
  while IFS= read -r version; do
    [[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || continue
    if [[ -z $latest ]] || newer_version "$version" "$latest"; then latest=$version; fi
  done <<< "$tags"
done
[[ -n $latest ]] || fail 'no stable Wren releases were found.'

archive="wren-$latest-$host.tar.gz"
checksum="$archive.sha256"
release_url="$downloads/wren-v$latest"
home_dir=${HOME:?HOME must be set}
bin_dir="$home_dir/.local/bin"
target="$bin_dir/wren"
mkdir -p "$bin_dir" || fail "could not create $bin_dir."

stage=$(mktemp -d "$bin_dir/.wren-install.XXXXXX") || fail "could not create a staging directory in $bin_dir."
backup="$stage/previous-wren"
replaced=0
installed=0
cleanup() {
  status=$?
  preserve_stage=0
  if ((installed)); then
    if ((replaced)) && [[ -f $backup ]]; then
      if ! mv -f "$backup" "$target"; then
        printf 'Wren installer: could not restore the previous executable; it remains at %s\n' "$backup" >&2
        preserve_stage=1
      fi
    else
      rm -f "$target"
    fi
  fi
  if ((preserve_stage)); then
    printf 'Wren installer: staged recovery files remain at %s\n' "$stage" >&2
  else
    rm -rf "$stage"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Downloading Wren %s for %s...\n' "$latest" "$host"
curl -fsSL "$release_url/$archive" -o "$stage/$archive" || fail 'archive download failed.'
curl -fsSL "$release_url/$checksum" -o "$stage/$checksum" || fail 'SHA-256 manifest download failed.'

expected=$(awk -v filename="$archive" '$2 == filename || $2 == "*" filename {print $1; exit}' "$stage/$checksum")
[[ $expected =~ ^[a-fA-F0-9]{64}$ ]] || fail 'SHA-256 manifest is invalid or names a different archive.'
if [[ $hash_command == sha256sum ]]; then
  actual=$(sha256sum "$stage/$archive" | awk '{print $1}')
else
  actual=$(shasum -a 256 "$stage/$archive" | awk '{print $1}')
fi
actual=$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')
expected=$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')
[[ $actual == "$expected" ]] || fail 'archive SHA-256 verification failed.'
printf 'Archive checksum verified.\n'

listing=$(tar -tzf "$stage/$archive") || fail 'downloaded archive is not a valid gzip tar archive.'
while IFS= read -r member; do
  [[ $member != /* && $member != *'../'* && $member != ../* ]] || fail 'archive contains an unsafe path.'
  case "$member" in
    "wren-$latest-$host/"|"wren-$latest-$host/wren"|"wren-$latest-$host/INSTALL.md") ;;
    *) fail 'archive contains an unexpected file.' ;;
  esac
done <<< "$listing"
tar -xzf "$stage/$archive" -C "$stage" || fail 'could not extract the verified archive.'
staged="$stage/wren-$latest-$host/wren"
[[ -f $staged && ! -L $staged ]] || fail 'archive does not contain the expected Wren executable.'
chmod 755 "$staged"
version_output=$("$staged" --version 2>/dev/null) || fail 'staged Wren executable did not run.'
[[ $version_output == "wren $latest" ]] || fail "staged executable reported an unexpected version: $version_output"
"$staged" --help >/dev/null 2>&1 || fail 'staged Wren executable failed its --help check.'

if [[ -L $target ]]; then
  fail "$target is a symbolic link; move it aside and retry."
elif [[ -e $target ]]; then
  [[ -f $target ]] || fail "$target is not a regular file; move it aside and retry."
  old_version=$($target --version 2>/dev/null || true)
  [[ $old_version =~ ^wren\ [0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    fail "$target is not a recognized Wren executable; move it aside and retry."
  [[ -w $target && -w $bin_dir ]] || fail "$target cannot be safely replaced by this user."
  cp -p "$target" "$backup" || fail 'could not preserve the existing Wren executable.'
  replaced=1
fi

installed=1
mv -f "$staged" "$target" || fail "could not install Wren to $target."
if [[ $("$target" --version 2>/dev/null || true) != "wren $latest" ]] || \
  ! "$target" --help >/dev/null 2>&1; then
  fail 'installed executable validation failed; restoring the previous executable.'
fi
replaced=0
installed=0
rm -f "$backup"
printf 'Wren %s installed at %s\n' "$latest" "$target"
if ! command -v git >/dev/null 2>&1; then
  printf 'Warning: Git is not installed. Install Git before using Wren to install Flutter releases.\n'
fi
case ":${PATH:-}:" in
  *":$bin_dir:"*) ;;
  *) printf 'Add this directory to your PATH: %s\n' "$bin_dir" ;;
esac
