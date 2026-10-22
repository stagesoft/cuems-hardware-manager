<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# `cuems-hardware-manager` — planning folder

**Opened 2026-10-22.** Design ahead of implementation: nothing here is built. Every file carries a
dated status banner under its title. When a feature lands, mark the file that briefed it as record
and keep it in place, because sibling repositories may link to it by path.

## Reading order

| File | Status | Read it when |
|---|---|---|
| [`01-architecture.md`](01-architecture.md) | **Proposal, for agreement** | First. The six-stage chain, the two services, the data model, the contracts, the safety rules |
| [`02-hardware-classes.md`](02-hardware-classes.md) | Proposal | Designing or reviewing any probe: sources, identity keys, twin vs agreement vs setup, per class |
| [`03-ecosystem-seams.md`](03-ecosystem-seams.md) | Proposal | Touching anything a sibling owns: the ownership table, absorption candidates from `cuems-common`, gates |
| [`04-open-decisions.md`](04-open-decisions.md) | **Partly decided** (D-1, D-2, D-13, stage boundary, twin writer — 2026-10-22) | Before a `/speckit.specify`: the decided table, D-3…D-13 with recommendations, and the proposed feature split |
| [`06-machinery-inventory.md`](06-machinery-inventory.md) | **Measured** 2026-10-22 | Before any setup feature or absorption: every hardware piece in the siblings (shipped or not), headline defects, and the single-source-of-truth table |
| [`00-runnable-flow.md`](00-runnable-flow.md) | **Ready to run §2** | Running `/speckit.constitution`, and for the context block every spec and plan pastes |
| [`05-ownership-notice-draft.md`](05-ownership-notice-draft.md) | Draft, not sent | Once the maintainer confirms ownership: the notice to `cuems-utils` that closes `cuems-nodeconf`'s open withdrawal |

## Where this came from

- `cuems-utils` `specs/planning/hardware-outputs-capability-layer.md` and
  `etc-cuems-first-install.md` §7–§8 — the design argument for the layer.
- `cuems-nodeconf` `specs/upstream-reports/hardware-outputs-obligation-withdrawn.md` — the 2026-10-21
  withdrawal that left the work without an owner.
- `cuems-videocomposer` `docs/contract-v1.md` (branch `feat/contract-report`) — written for this
  repository's team.
- `cuems-common` `README.md` (`rc_1`) and its audio, display and OLA machinery.

## Standing lessons, inherited from the siblings

- **Re-measure before relying on any coordinate.** Line numbers and commits in this folder are dated;
  check them against the branch that is releasing before you cite them.
- **Name a document or a behaviour, never a feature number**, in comments and cross-references.
  Numbers get reassigned; `cuems-utils` paid for this twice on this very work.
- **A proposal is not a decision.** Names marked *proposal* (services, paths, ports, documents) stay
  that way until `04-open-decisions.md` records the maintainer's ruling.
