# Vendored Streamdown Compatibility Subset

- Upstream: https://github.com/euforicio/streamdown-swift
- Revision: `ba84b548d9b07bad00b90795990f4825a6fa8f4c`
- Imported: 2026-07-28
- License: FSL-1.1-MIT; the upstream license first appeared on 2026-03-16,
  making its future MIT grant effective on 2028-03-16.

AgentDock vendors only the `Streamdown` and `StreamdownUI` products and their
tests. The unused `EuforicAI` product and upstream repository automation are
excluded.

The local manifest lowers the tools version to Swift 5.9 and declares iOS 17
and macOS 13 compatibility. The source revision already includes the
ObservableObject compatibility, theme propagation, control gating, link-sheet,
and UI-state fixes required by AgentDock.
