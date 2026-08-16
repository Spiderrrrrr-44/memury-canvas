# Release metadata

- Release: `2026-08-16-qgraph-apple-r3`
- Source branch: `feat/final-product-integration`
- Source baseline: release candidate on `feat/final-product-integration`; the final commit is recorded by the GitHub pull request.
- Canvas patch base: `44bfdc26` (`origin/stable/2026-04-22` lineage)
- Target host: `canvas.memury.net`
- Target architecture: Canvas Docker Compose with persistent PostgreSQL and file volumes
- UI policy: inherit native Canvas chrome; Apple-style Q Graph system; no global dark-theme mutation
- Data policy: additive `memury_*` tables only
- Language policy: follow the signed-in Canvas user locale (`zh-CN` or English)
- Verification: Ruby syntax, shell syntax, patch dry-run, 13 frontend tests, preview bundle compilation
