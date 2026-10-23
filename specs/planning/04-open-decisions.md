<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Open decisions

**Status (2026-10-22): OPEN.** Each decision carries a recommendation. When the maintainer decides
one, record the date and outcome in its row and leave the row in place so citations still resolve
(`D-n` numbers are never reused). Architecture: [`01-architecture.md`](01-architecture.md).

## Decided

| Date | Decision | Outcome |
|---|---|---|
| 2026-10-22 | **D-1** | Two units: `cuems-hardware-node` (every host) and `cuems-hardware-controller` (controller). **Both systemd units ship in this repository's package**, not in `cuems-common`, because `cuems-common` is being stripped of its non-essential responsibilities |
| 2026-10-22 | **D-2** | Own transport, on a new port whose value **lands in `settings.xml`** (see the D-2 row for what follows from that) |
| 2026-10-22 | Stage boundary | Stages 1–5 only observe and record. Stage 6 is the only one that changes a box, and it applies the operator's agreement |
| 2026-10-22 | Twin writer | `cuems-hardware-node` is the **sole writer** of `/etc/cuems/hardware_outputs.xml`, which is the per-node digital twin |
| 2026-10-22 | Hardware machinery | `cuems-generate-display-conf`, `cuems-ola-profile`, `jack-alsa-bridges.service` and `cuems-gpu-pin` **belong in this repository**. Every other hardware piece found in the siblings is inventoried, with a proposal, in [`06-machinery-inventory.md`](06-machinery-inventory.md) |
| 2026-10-23 | **D-14** | Privilege split. Both daemons run as `cuems`. Setup's privileged effects run in root oneshot units shipped here, which take fixed inputs, run at boot, and are started by the daemon only through a sudoers rule naming the exact units. `cuems-admin` stays human-only. Constitution amended to 1.1.0 (Principle VIII) |
| 2026-10-22 | **D-13** | First feature: a CLI, `cuems-hw-mgr probe --json`, that builds the **complete digital twin** as a `CuemsHardwareNode` object from reading and discovering the system. Nothing is sent to the controller, and the twin is promoted to XSD/XML later |

## All decisions

| # | Decision | Options | Recommendation | Needed by |
|---|---|---|---|---|
| **D-1** | Service split and unit ownership | (a) one role-aware daemon; (b) two services, node + controller, one package | **Decided 2026-10-22: (b)**, `cuems-hardware-node.service` (`PartOf=cuems-node.target`) and `cuems-hardware-controller.service` (`PartOf=cuems-controller.target`). **Unit ownership decided 2026-10-22: this package ships both units** (as `cuems-power-bridge` has shipped its own since `bb69a9e`), because `cuems-common` is being stripped of non-essential responsibilities. The units declare their own `PartOf=`/`WantedBy=` against the targets `cuems-common` provides, so `cuems-common` needs no change to carry them. The same applies to the scoped restart rule stage 6 needs (sudoers/polkit drop-in): it ships here too | first runnable feature |
| **D-2** | Promotion transport (stage 3) | (a) own NNG Req/Rep + Pub/Sub over TCP; (b) the engine's NNG bus `:9093`; (c) files pulled by rsync | **Decided 2026-10-22: (a)**, with the port value **in `settings.xml`**. This has consequences: (1) `settings.xsd` gains the field. That is a `cuems-utils` change, seeded by `cuems-init-node` (the sole writer of `settings.xml`) from the system defaults, and goes on the upstream ask list. (2) Both services read it; neither writes it. (3) The controller dials each node on **its own** configured value, so the value has to be the same on every host. A per-node override would need the port published somewhere the controller can read before connecting, which `settings.xml` cannot do. *Still open:* the default value (`9094` is unused in the measured map) and its row in the `cuems-RELATIONS` port table | node API feature |
| **D-3** | Where the agreement lives | (a) one cluster-scoped document on the controller + each node keeps its applied slice; (b) one node-scoped authored document per node | **(a)**: the operator agrees once, for the system; each node keeps the slice it last applied so it plays standalone. Paths to be fixed with `cuems-utils` | agreement feature |
| **D-4** | The agreement's schema | (a) a seventh `cuems-utils` schema; (b) private to this repository | **(a)**. Every other CUEMS document is a `cuems-utils` schema with one declared writer; the editor and engine will read it | agreement feature |
| **D-5** | UI path for the operator | (a) frontend → editor (WS) → controller service (NNG IPC relay); (b) frontend talks to the controller service directly | **(a)**. The browser only ever reaches apache `:80`; the editor already relays to the engine over IPC. A CLI comes first either way. **New input (06 finding 2):** a `hw_discovery` chain already exists, editor → controller engine → `/tmp/hwdiscovery.ipc` (`cuems-utils` `IpcAddress.HWDISCOVERY`), with nobody listening. Options: (a1) `cuems-hardware-controller` answers that socket and the engine hop stays; (a2) the editor talks to the controller service directly and the engine hop is retired. Recommendation: **(a2)**, since hardware management should not depend on a running engine. Whichever is chosen, the dead chain is reused or retired, never duplicated | agreement UI |
| **D-6** | Retention of absent ports | (a) never forget automatically; (b) forget after N days absent; (c) forget unless referenced by the agreement | **(c)**, with an explicit operator "forget" for referenced ones. Unreferenced churn (a USB audio dongle plugged in once) should not pile up | twin feature |
| **D-7** | Inputs in a schema named `hardware_outputs` | (a) keep the name, add `direction`; (b) rename at the next version step | **(a)** now; raise (b) with `cuems-utils` when the structure pass needs a version step anyway. Renaming twice is worse than a slightly wrong name | structure pass (upstream) |
| **D-8** | Projector configuration source | (a) stays in `power-bridge.conf`, this repository reads it; (b) moves into the agreement, the bridge reads it | **(a)** first, (b) as a joint decision with `cuems-power-bridge` once the agreement exists | network-displays work |
| **D-9** | `cuems-hdmi-audio-map` | (a) stays in `cuems-common`, this repository re-implements the mapping read-only; (b) moves here as a library + boot oneshot | **(b)**, later: one implementation of the pipe → device mapping, used by the boot oneshot and by the audio probe. Its run-before-`jackd` ordering is non-negotiable. Reinforced by 06 finding 5 (the same knowledge is held three times) and by `cuems-common` being stripped | audio setup feature |
| **D-10** | Measured `output_latency_ms` | (a) this repository measures and records it in the twin; (b) not in scope | **(a)**, later. The field already has its two-provenance design (`etc-cuems-first-install.md` §8.2) | after setup |
| **D-11** | How the audio probe reads JACK | (a) a registered JACK client (`python-jack`, as the prototype did); (b) `jack_lsp`-style one-shot; (c) ALSA only, JACK view from the engine | **Pending (2026-10-22): research and agreement with the team.** Two questions are open. First, the earlier recommendation, (b), a `jack_lsp`-style one-shot. Note that `jack_lsp` itself registers a short-lived JACK client. Second, the proposed ban on any JACK client registration by the probe. Neither is decided. Whatever is agreed must keep Principle I: nothing joins the JACK graph while a show is loaded. Until then, the twin reports JACK exposure as `unknown` (feature 001) | audio probe; audio setup |
| **D-12** | The repository's name everywhere | `cuems-hardware-manager` (repo) / `cuemshardwaremanager` (import) vs `cuems_hwdiscovery` in `CLAUDE.md` and the `cuems-RELATIONS` index | **`cuems-hardware-manager`**, corrected in both places in one change | now (cheap) |
| **D-13** | First feature's scope | (a) probes only, read-only, JSON/CLI output, no file; (b) probes + persistence | **Decided 2026-10-22: (a), widened to the complete twin.** `cuems-hw-mgr probe --json` over a `CuemsHardwareNode` object class that holds the whole digital twin. No transmission to the controller, no file. This also **reverses the order with `cuems-utils`**: the twin's model is worked out here as code and JSON, then promoted to XSD/XML, so the upstream structure pass starts from a model already proven on real hosts | `/speckit.specify` 001 |

| **D-14** | Privilege model for setup (stage 6) | (a) the daemon runs as root; (b) the daemons run as `cuems`, with root oneshot apply units started through a sudoers rule naming the exact units; (c) polkit instead of sudoers for (b) | **Decided 2026-10-23: (b).** It matches how `cuems-common` runs a host (measured on `feat/xml-refactor`): services `User=cuems`; root boot oneshots `cuems-hdmi-audio-map` and `cuems-gpu-pin`; narrow `NOPASSWD` rules for exact commands (`99-cuems-avahi`, `99-cuems-poweroff`); `cuems-admin` with password sudo, for humans. (a) is rejected because the daemons face the network. Sketch: `cuems-hardware-apply@<class>.service`, root, reading the node's applied slice. It renders `/etc/asound.conf`, `/etc/default/jack`, `/etc/ola/*` and `display.conf`, restarts in order, refuses under the show lock, and also runs at boot. The absorbed `cuems-hdmi-audio-map` and `cuems-gpu-pin` become its steps or siblings. **Open for the persistence feature:** `/etc/cuems` is `root:root 0755`, so `cuems` writing `hardware_outputs.xml` needs a deliberate ownership decision (a postinst-created file or subdirectory). It is measured as **not uniform** in the field: `root:root` on 10.16.10.2, `stagelab:stagelab` (a legacy user) on 10.16.10.3 (2026-10-23). The decision has to normalise it, not assume either owner | units feature; setup features |

## Proposed feature split

Numbers are **proposals**; spec-kit assigns them when `/speckit.specify` creates the folder, and if
the order changes, the numbers follow the order, not this table.

| # | Feature | Stage | Hard dependencies |
|---|---|---|---|
| 001 | `node-twin-discovery`: the `CuemsHardwareNode` class (the complete twin, in memory), per-class probes, the identity resolver, `cuems-hw-mgr probe --json`; recorded fixtures for every class. **Decided scope (D-13)** | 1 + 2 (in memory) | — |
| 002 | `node-twin-persistence`: the twin promoted to XSD/XML, written by `cuems-hardware-node` only; presence across runs, retention, revision | 2 | 001's model; `cuems-utils` ownership + structure pass + accessor |
| — | `gpu-policy`: `cuems-gpu-pin` moved here (decided), keyed on the twin's GPU identity, shipped inert; thermalmon's i915 gpucap if agreed (06 C14, T1). Needs no agreement, so it can be scheduled at any point after 001 | node | 001 |
| 003 | `node-api`: node API v1, local and TCP | 3 | 002; registered port |
| 004 | `cluster-catalogue`: controller service, aggregation, freshness | 4 | 003 |
| 005 | `operator-agreement`: setup document, CLI, editor relay | 5 | 004; setup schema in `cuems-utils` |
| 006 | `setup-video`: render `display.conf`, ordered restarts, refusal under show lock; retire `cuems-display-setup` | 6 | 005 |
| 007 | `setup-audio`: every audio kind selectable from the agreement (HDMI, USB DSP/interface, multichannel card, main L/R; scope ruling 2026-10-22 in 02 §2); ALSA/JACK renderings, bridges parameterised, ordered service restart; D-9, D-11 | 6 | 005; JACK relations agreed with the team |
| 008 | `setup-dmx`: OLA patch and profile | 6 | 005 |
| — | `default_mappings.xml` retirement | end state | 006–008 and `cuems-utils` §8.5 step 5, coordinated |
