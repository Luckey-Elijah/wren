# Agent guidance

## Implementation specs

For implementation work, first check `.scratch/` for the initiative's `spec.md`. The Wren version-manager specification is `.scratch/wren-version-manager/spec.md`; its source decisions and research remain alongside it in that directory. Treat the spec as the implementation contract, and consult the source tickets when a rationale or unresolved condition needs detail.

When a user invokes `to-spec`, synthesize the supplied decisions into `.scratch/<initiative>/spec.md` and keep it local unless the user explicitly requests publication. When a user invokes `implement`, locate and follow the relevant local `spec.md` before changing product code. Update the spec only when the user changes a decision or asks for specification maintenance.

## CLI implementation

Follow `.scratch/wren-version-manager/spec.md` for CLI behavior. Implement CLI commands as `WrenCommand` subclasses, register them through `WrenCommandRunner`, and obtain shared invocation values and services from the single per-invocation `WrenContext`. Keep package `args` runner and parser details behind the Wren composition wrapper. Verify command behavior through `runWren` and observable output, status, filesystem, or process effects; do not couple tests to base-class internals.
