<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# DRAFT — Notice to `cuems-utils`: `cuems-hardware-manager` takes the hardware-outputs obligation

> **Status (2026-10-22): DRAFT, not sent.** Becomes a notice when the maintainer confirms the
> ownership. Once sent, it would move to `specs/upstream-reports/` here (the siblings' convention)
> and close `cuems-nodeconf`'s open notice
> `specs/upstream-reports/hardware-outputs-obligation-withdrawn.md`.

**From**: `cuems-hardware-manager`, branch `main`.
**For**: `cuems-utils`, `specs/planning/hardware-outputs-capability-layer.md`.

## 1. What changes

`cuems-nodeconf` withdrew the obligation on 2026-10-21 and named no new owner. **This repository is
the owner**: the probe, the per-node twin written to `hardware_outputs.xml`, and the machinery around
it — the cluster catalogue, the operator agreement and the setup that applies it. Architecture:
`specs/planning/01-architecture.md`.

## 2. What it changes upstream

| Upstream location | Proposed correction |
|---|---|
| §3 ownership | *"`cuems-hardware-manager` probes, agrees, renders and generates; `cuems-utils` describes and persists"*. `cuems-generate-display-conf` moves here from `cuems-common` (decided 2026-10-22), along with `cuems-ola-profile` and `jack-alsa-bridges.service` |
| §3, the transcription | **Withdrawn as a concept, not just re-owned.** `display.conf` geometry is authored intent (regions, blends, chosen mode); writing it into a discovered document would break F4. The twin carries capability (connectors, modes, EDID); the agreement carries geometry; `display.conf` is rendered from the agreement. `hardware_outputs.xml` then has **one** writer |
| `hardware_outputs.xsd` annotation | one `cms:writer`, `cuems-hardware-node` (decided 2026-10-22); drop the `geometry` scope |
| `settings.xsd:16`, `../cuems-common/docs/latency-tuning.md:15` | the role name stays; the repository is `cuems-hardware-manager` |
| §5, the hard gate | re-opens here; the remaining hard gate for persistence is the structure pass and the public accessor |
| §7 item 3 | moves here: how probe, agreement and setup split into features is `specs/planning/04-open-decisions.md` |

## 3. What this repository asks for

1. The **structure pass** on `hardware_outputs.xsd` able to carry the model in `01-architecture.md`
   §4 (devices, ports with direction and stable ids, presence, sinks, class as data per F6).
2. Flipping `ConfigManager`'s refusal of `SchemaName.HARDWARE_OUTPUTS` into a public accessor.
3. A **seventh schema** for the operator agreement (D-4), one writer, `cuems-hardware-controller`.
4. A **node-API port field in `settings.xsd`** (D-2, decided 2026-10-22), with a default in the
   system defaults that `cuems-init-node` seeds. Both of this repository's services read it; neither
   writes it.

None of this is needed for this repository's first feature, which only probes and reports.

## 4. What does not change

`cuems-videocomposer` owns `/run/cuems/display.conf` at run time and its format; `cuems-utils` owns schemas, models, bindings and accessors; `cuems-nodeconf` reads and
writes no hardware data.
