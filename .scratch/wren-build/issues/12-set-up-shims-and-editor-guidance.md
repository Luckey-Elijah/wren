# 12: Set up optional PATH shims and editor guidance

Status: complete
Blocked by: [11: Provide stable editor SDK paths](11-provide-stable-editor-sdk-paths.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

`wren setup` gives users optional `flutter` and `dart` PATH shims and clear editor setup instructions, so ordinary shell and editor workflows can use Wren's release selection.

## Acceptance criteria

- [x] Installed shims choose the active or exact overridden release and preserve arguments, streams, child exit status, and Wren process leases.
- [x] Setup prints the necessary PATH steps and VS Code command-based and JetBrains fixed-path guidance, including workspace or reload implications.
- [x] Setup does not automatically edit shell startup or editor configuration, and routine use requires no daily protection command.
- [x] CLI tests run generated shims against controlled SDK children and inspect setup output and generated files.
