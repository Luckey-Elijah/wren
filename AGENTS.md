# Agent guidance

## Implementation specs

Resolve Wren implementation ticket references from `.scratch/wren-build/issues/` and state the local ticket title. Those files are the issue tracker for Wren implementation work.

For implementation work, first check `.scratch/` for the initiative's `spec.md`. The Wren version-manager specification is `.scratch/wren-version-manager/spec.md`; its source decisions and research remain alongside it in that directory. Treat the spec as the implementation contract, and consult the source tickets when a rationale or unresolved condition needs detail.

When a user invokes `to-spec`, synthesize the supplied decisions into `.scratch/<initiative>/spec.md` and keep it local unless the user explicitly requests publication. When a user invokes `implement`, locate and follow the relevant local `spec.md` before changing product code. Update the spec only when the user changes a decision or asks for specification maintenance.

## Code task completion

For tasks that change code, run `dart analyze` and `dart test` before reporting completion. If an environment issue prevents either check, report it and state that verification is incomplete.

After completing and committing a Wren implementation ticket, verify each acceptance criterion, check off the criteria met, and change its status to `complete`. Leave unmet criteria unchecked and describe the remaining work.

## CLI implementation

Follow `.scratch/wren-version-manager/spec.md` for CLI behavior. Implement CLI commands as `WrenCommand` subclasses, register them through `WrenCommandRunner`, and obtain shared invocation values and services from the single per-invocation `WrenContext`. Keep package `args` runner and parser details behind the Wren composition wrapper. Verify command behavior through `runWren` and observable output, status, filesystem, or process effects; do not couple tests to base-class internals.

## Code reviews

For reviews of Wren implementation changes, check `.scratch/wren-build/issues/` for existing tickets that match each actionable finding. Report matching findings as already tracked and include the ticket title; still describe the defect and impact. Distinguish these from findings that need new tickets, and do not omit a valid finding just because it is already tracked.
