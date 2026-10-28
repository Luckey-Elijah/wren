Type: research
Status: resolved

## Question

How does Puro actually implement concurrent framework checkout and engine download, shared git objects, and shared engine versions? Identify reusable principles, platform assumptions, failure modes, and where its model does or does not fit Wren's version-based installs.

## Answer

Puro starts engine precaching before framework checkout, uses a shared Git object repository with per-environment checkouts, and shares engine cache entries keyed by engine commit. Wren can adopt these principles for version-based installs, while choosing its own shared-cache locking, partial-extraction recovery, and mutable-versus-immutable artifact boundary. Full findings and citations: [puro-cache.md](../research/puro-cache.md).
