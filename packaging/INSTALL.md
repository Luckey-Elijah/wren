# Install Wren

Wren is distributed as a standalone native executable. A separately installed
Dart SDK is not required. Wren does require the system `git` command for
installing Flutter releases.

Choose the archive matching your host:

- `wren-<version>-linux-x64.tar.gz` for Linux x86_64.
- `wren-<version>-macos-arm64.tar.gz` for Apple Silicon macOS.

Verify the archive against the matching `.sha256` file or the `SHA256SUMS`
release manifest before extracting it. For example, on Linux:

```sh
sha256sum --check wren-<version>-linux-x64.tar.gz.sha256
```

On macOS:

```sh
shasum -a 256 --check wren-<version>-macos-arm64.tar.gz.sha256
```

Extract the archive and copy `wren` to a directory on your `PATH` that you can
write to, such as `~/.local/bin` on Linux or `~/bin` on macOS:

```sh
tar -xzf wren-<version>-<host>.tar.gz
mkdir -p "$HOME/.local/bin"
install -m 755 "wren-<version>-<host>/wren" "$HOME/.local/bin/wren"
```

Use your own PATH directory in place of `~/.local/bin` if needed. Add that
directory to your shell's PATH, then check the installation with `wren --help`.
Install Git through your operating system's package manager or developer tools
before using Wren to install Flutter.

## First launch on macOS

The initial macOS executable may be unsigned. After the first blocked launch,
open **System Settings > Privacy & Security**, scroll to **Security**, and
choose **Open Anyway** for Wren. Confirm the prompt, then run Wren again. The
approval is needed only once for that executable.

Wren currently supports Linux x86_64 and macOS arm64 only. Windows, Linux arm64,
and Intel macOS are not supported.
