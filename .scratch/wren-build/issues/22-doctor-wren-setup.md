# 22: Diagnose Wren setup

Status: ready-for-agent
Blocked by: [12: Set up optional PATH shims and editor guidance](12-set-up-shims-and-editor-guidance.md), [19: Package standalone native Wren downloads](19-package-standalone-native-wren.md), [21: Diagnose releases and project selection quickly](21-doctor-quick-releases-and-project.md), [CLI architecture: Migrate existing Wren CLI commands](../../wren-cli-architecture/issues/01-migrate-existing-cli.md)
Contract: [Wren doctor spec](../../wren-doctor/spec.md), [Wren version manager spec](../../wren-version-manager/spec.md)

## What to build

Quick doctor also tells a developer whether Wren-owned setup and required system Git are usable, while treating optional shell and editor choices honestly.

## Acceptance criteria

- [ ] Doctor inspects its executable, registry, storage, configured fallback, installed shims, current-process PATH, and availability of system Git.
- [ ] Missing Git and confirmed broken Wren-owned setup are critical; missing optional shim paths or settings outside Wren's control are informational, and uninspectable components are incomplete.
- [ ] Doctor does not claim to verify persistent shell startup or editor settings and does not modify them.
- [ ] Short quick-check stalls time out with incomplete findings while other checks continue; human output includes setup summary and next steps.
- [ ] CLI tests cover broken registry or storage, missing Git, installed and absent shims, PATH, and incomplete setup checks.
