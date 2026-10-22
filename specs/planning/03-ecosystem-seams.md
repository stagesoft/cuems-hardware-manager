<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Ecosystem seams — who owns what, and what moves

**Status (2026-10-22): PROPOSAL.** The ownership table each sibling would have to agree to, the
machinery that could move into this repository and in what order, and the cross-repository gates.
Nothing here binds a sibling until that sibling records it on its side.

---

## 1. Ownership after this repository exists

| Thing | Owner | Change from today |
|---|---|---|
| Probing hardware, the per-node twin, `hardware_outputs.xml` content | **`cuems-hardware-node`**, the sole writer (decided 2026-10-22) | Was assigned to a `cuems-hardware-discovery` role with no repository, then to `cuems-nodeconf` (2026-10-12), withdrawn 2026-10-21. Now here |
| `display.conf` **geometry** | **`cuems-hardware-manager`** renders it from the agreement | Was to be *transcribed* by nodeconf into a discovered document. Geometry is authored intent (01 §2) |
| Cluster capability catalogue, operator agreement, setup | **`cuems-hardware-manager`** (controller service) | New. Today: hand-edited `default_mappings.xml` and `/etc/cuems/display.conf`, `cuems-display-setup`, `cuems-ola-profile`, hard-coded unit arguments |
| `hardware_outputs.xsd`, the setup schema, models, registry bindings, `ConfigManager` accessor | **`cuems-utils`** | Unchanged in principle. The schema's `cms:writer` annotations must change (§4) |
| `cuems-generate-display-conf` (VC `ExecStartPre`) | **`cuems-hardware-manager`** (decided 2026-10-22) | Moves here from `cuems-common`. It stays the generator at VC start, through a drop-in this package ships, and its input changes from `default_mappings.xml` to the applied agreement. This reverses the upstream assumption that `cuems-common` keeps generation (`cuems-utils` capability-layer §3) |
| `/run/cuems/display.conf` at run time | `cuems-videocomposer` | Unchanged |
| The VC management contract (v1 read, v2 write) | `cuems-videocomposer` | Unchanged. This repository is its intended client — "the team building the CUEMS hardware-configuration manager" |
| Network, node discovery, adoption, identity, `network_map.xml` | `cuems-nodeconf` | Unchanged. This repository reads the map; never writes it. nodeconf reads and writes no hardware data at all |
| Projector power and brightness, cluster power-off | `cuems-power-bridge` | Unchanged for control. Projector **configuration** source is D-8 |
| Mappings authoring, project documents | `cuems-editor` (writer) / `cuems-frontend` (UI) | Gains the agreement UI and, later, an output picker that references agreement outputs by id |
| Consuming mappings and display geometry | `cuems-engine` | Later reads hardware through the `cuems-utils` accessor instead of `node_hw_outputs` from mappings |
| This repository's systemd units (`cuems-hardware-node`, `cuems-hardware-controller`) and their scoped restart rule | **`cuems-hardware-manager`** (decided 2026-10-22, D-1) | Never in `cuems-common`, which is being stripped of non-essential responsibilities. The units attach themselves to its targets with `PartOf=`/`WantedBy=` |
| Targets (`cuems-node.target`, `cuems-controller.target`), boot/recovery enablement | `cuems-common` | Unchanged. Output-specific quirks are absorption candidates ([`06`](06-machinery-inventory.md) C13–C14) |
| Measured `output_latency_ms` | twin (this repository) | Override stays in `settings.xml` (writer `cuems-init-node`); a reader prefers override → measured → `auto` (`etc-cuems-first-install.md` §8.2) |

## 2. The seams worth stating, because they look like overlaps

**`cuems-hardware-manager` ↔ `cuems-videocomposer`.** v1 is read-only on both sides: the VC reports,
this repository observes. Until v2, the only way to change what the VC drives is a `display.conf`
rendering plus a restart. When v2 lands, the VC enforces `show_loaded` on its side too — two locks
that agree is the intended state, not redundancy.

**`cuems-hardware-manager` ↔ `cuems-power-bridge`.** The bridge controls displays it is configured
to know about; this repository knows which output feeds which display. Neither should duplicate the
other: the bridge keeps PJLink/ESC-VP control and its HTTP contract; this repository never sends a
power command.

**`cuems-hardware-manager` ↔ `cuems-nodeconf`.** Topology in, nothing out. The join key is the node
`uuid`; `project_mappings`/hardware data never ride on `NodeIndex`'s node (nodeconf's own recorded
constraint). nodeconf is enabled on very few hosts today, so this repository must work with a
hand-maintained `network_map.xml` — it reads whatever the map says is adopted.

**`cuems-hardware-manager` ↔ `cuems-engine`.** The engine is a consumer and never a dependency in the
other direction: hardware discovery must not need a running engine (which is why the node API does
not ride the engine's NNG bus).

## 3. Machinery that could move here — absorption candidates

The pattern is `cuems-power-bridge`'s `specs/planning/cuems-common-machinery-to-absorb.md`: name
each piece, say why it moves or stays, and move it only as part of a feature that replaces it.
`cuems-common` is being stripped of non-essential responsibilities (maintainer, 2026-10-22), so the
pieces below marked *stays* are worth re-checking with it as the setup features approach. Hardware
machinery that `cuems-common` sheds should land here, not be scattered.

**Superseded 2026-10-22 by [`06-machinery-inventory.md`](06-machinery-inventory.md)**, which is the
full measured inventory: every hardware piece across the siblings, whether it is shipped, and a
fact-by-fact single-source-of-truth table. Summary:

| Piece (in `cuems-common` today) | Proposal | 06 row |
|---|---|---|
| `cuems-generate-display-conf` + VC drop-in | **Absorb — decided 2026-10-22.** Still the VC's `ExecStartPre`, via a drop-in this package ships. Carries a live defect (06 finding 3) | C1 |
| `cuems-ola-profile` | **Absorb — decided 2026-10-22.** The DMX renderer's backend | C3 |
| `jack-alsa-bridges.service` | **Absorb — decided 2026-10-22**, parameterised from the applied setup | C4 |
| `cuems-display-setup` (in the tree, **not shipped**) | Prior art for the video probe, then retire | C2 |
| `cuems-hdmi-audio-map` + unit | Absorb (resolves D-9 toward absorbing) | C5 |
| `jackd-cuems.service`, `/etc/default/jack`, JACK tmpfiles, pipewire masks | Absorb with audio setup | C6, C7, C10 |
| static `etc/asound.conf`, `alsa-card-order.conf` (**not shipped**) | Retire | C8, C9 |
| `olad.service` + OLA postinst defences + flock test | Absorb with DMX setup | C11 |
| `cuems-extract-video-latency` | Absorb later | C12 |
| `cuems-wake-monitors.sh`, `cuems-i915-rebind.sh` | Absorb later, as twin-driven quirks | C13 |
| `cuems-gpu-pin` | **Absorb — decided 2026-10-22.** The GPU-policy module; thermalmon's i915 gpucap proposed to join it | C14, T1 |

## 4. Upstream references that become wrong, and must be corrected

| Site | Says | Should say |
|---|---|---|
| `cuems-utils` `hardware_outputs.xsd` annotation | `cms:writer scope="inventory"` `cuems-hardware-discovery`; `scope="geometry"` `cuems-nodeconf` | one writer, `cuems-hardware-node`; geometry is not in this document (01 §2) |
| `cuems-utils` `settings.xsd:16`, `../cuems-common/docs/latency-tuning.md:15` | `cuems-hardware-discovery` / `hardware-discovery` | the role survives; the repository is `cuems-hardware-manager` |
| `cuems-utils` `hardware-outputs-capability-layer.md` §3, §5 gate, §7 item 3 | nodeconf as owner; *"`cuems-nodeconf` acquiring the obligation"* as the hard gate | this repository as owner; the gate re-opens here. Draft notice: [`05-ownership-notice-draft.md`](05-ownership-notice-draft.md) |
| this repository's `CLAUDE.md` | `cuems_hwdiscovery`, *"Support/tooling repo"* | `cuems-hardware-manager`, the role in [`README.md`](../../README.md) |
| `cuems-RELATIONS` `CLAUDE.md` component index | row `cuems_hwdiscovery` — *"Hardware discovery / setup"*, under Ops/provisioning | row `cuems-hardware-manager`, under Core components (it runs on every host); its port, once registered |

The lesson the siblings paid for twice: **name a document or a behaviour, never a feature number**,
in code comments and in cross-repository references.

## 5. Gates, in the order they bind

| Gate | Kind | Blocks |
|---|---|---|
| `cuems-utils` records this repository as the owner (closes nodeconf's open notice) | **hard** for anything that writes `hardware_outputs.xml` | stage 2 persistence |
| `cuems-utils` structure pass on `hardware_outputs.xsd` + public accessor (the refusal of `HARDWARE_OUTPUTS` flipped) | **hard** for persistence | stage 2 persistence. **Not** for probing: a probe feature can land first with a JSON/CLI output and no file |
| The node-API port field in `settings.xsd` + its default, seeded by `cuems-init-node` (D-2); its row in the `cuems-RELATIONS` port table | hard for the TCP node API | stage 3 |
| Setup schema in `cuems-utils` (D-4) | hard | stage 5 |
| Editor relay + frontend UI | hard for operator use | stage 5 in the UI (a CLI can precede it) |
| VC contract v2 | soft — `display.conf` rendering works without it | stage 6 video, live reconfiguration |
| `default_mappings.xml` retires | coordinated, `cuems-utils` §8.5 step 5 | the end state |

`cuems-utils`' own ordering advice still applies: the capability layer is the largest remaining
breaking change of the `xml-refactor` arc and should not be landed inside a coordinated tag that is
already converging seven repositories.
