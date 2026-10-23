<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# `cuems-hardware-manager` — architecture proposal

**Status (2026-10-22): PROPOSAL, partly agreed.** Nothing here is implemented. **Decided
2026-10-22**: two units, `cuems-hardware-node` and `cuems-hardware-controller` (D-1); the node API
uses its own transport, on a port configured in `settings.xml` (D-2); stages 1–5 only observe and
stage 6 applies the operator's agreement; `cuems-hardware-node` is the sole writer of
`hardware_outputs.xml`, the per-node digital twin. Any other name of a file, document or default
value is a **proposal**. The open ones are listed in
[`04-open-decisions.md`](04-open-decisions.md), each with a recommendation.

**Measured against**: `cuems-utils` `feat/xml-refactor` `b592a57`, `cuems-common` `feat/xml-refactor`
`ba19317` (and `origin/rc_1` for its README), `cuems-nodeconf` `feat/xml-refactor` `6e9be84`,
`cuems-engine` `3ada95d`, `cuems-power-bridge` `feat/xml-refactor` `666cb25`, and
`cuems-videocomposer` `feat/contract-report` `docs/contract-v1.md`.

---

## 1. What this repository is

The CUEMS system has never had a split between **hardware** (per node, discovered, stable across
projects, not human-authored) and **mappings** (per project, authored, referencing hardware). Today
they are fused inside `project_mappings`, which is why a *project* document carries a node's physical
port inventory and why `default_mappings.xml` exists at all
(`cuems-utils` `etc-cuems-first-install.md` §7.3). The layer was designed in `cuems-utils`, given to
`cuems-nodeconf` on 2026-10-12, and withdrawn from it on 2026-10-21
(`cuems-nodeconf` `specs/upstream-reports/hardware-outputs-obligation-withdrawn.md`). The middle
owner is unassigned. **This repository is that owner.**

It is one product with six stages, the chain the maintainer set out:

```
 Real hardware        Digital         Node           System total      Operator          System
 availability   ───▶  twin      ───▶  promotion ───▶ capabilities ───▶ agreement   ───▶  setup
 (probe)              (per node)      (node→ctrl)    (catalogue)       (selection +      (apply to
                                                                        configuration)    the box)
 └──────────── read-only: never changes what is on screen, speaker or fixture ────────┘ └ writes ┘
```

| # | Stage | Question it answers | Runs on | Cell in the §8.1 basis¹ | Artifact | Sole writer |
|---|---|---|---|---|---|---|
| 1 | **Availability** | What is physically attached right now? | every host | node · runtime | probe results, in memory | the node agent's probes |
| 2 | **Digital twin** | What can this node do, under stable names? | every host | node · **discovered** | `/etc/cuems/hardware_outputs.xml` | **`cuems-hardware-node`**, the only writer (decided) |
| 3 | **Promotion** | How does the controller learn each node's twin? | node → controller | — (transport) | node API v1 (§5.2) | `cuems-hardware-node` serves; `cuems-hardware-controller` dials |
| 4 | **System capabilities** | What can the whole cluster do? | controller | cluster · discovered (a **copy**) | catalogue cache — never authoritative | controller service |
| 5 | **Operator agreement** | Which of it does the show system use, and configured how? | controller, operator via UI | cluster · **authored** | the *setup document* (name open, D-3) | controller service, on the operator's behalf |
| 6 | **System setup** | Make each box match the agreement | every host | node · runtime | `display.conf`, ALSA/JACK config, OLA patch; later VC v2 writes | node agent |

¹ `cuems-utils` `etc-cuems-first-install.md` §8.1: every stored fact has a **scope** and a
**provenance**, and a document is the container for exactly one cell.

**The structural rule the whole design rests on**: stages 1–5 are *observation and intent*; only
stage 6 touches the box, only from an agreement an operator made, and only when no show is loaded.
This is the videocomposer's own v1 stance (*"nothing in v1 changes what is on screen"*) generalised to
every hardware class.

## 2. Why one owner for all six stages

(Since 2026-10-22 the generator moves here too: `cuems-generate-display-conf` belongs to this
repository; see [`06-machinery-inventory.md`](06-machinery-inventory.md).)

`cuems-utils` §3 split the work across three writers — `cuems-common` generates `display.conf`,
*someone* probes, *someone* transcribes — and had to argue that `hardware_outputs.xml` *"looks like two
writers and is not"*. With this repository as the owner the argument goes away, and a design error
underneath it surfaces:

- **Geometry is not discovered.** Regions, blends, the canvas, the chosen mode are *operator intent*.
  Transcribing `display.conf` into a *discovered* document would have put authored facts into a
  discovered document — exactly the F4 violation (one provenance per document) that rc16 removed from
  the same schema when it dropped `default_video_output`. In this design, what the hardware **can do**
  (connectors, modes, EDID) lives in the twin (stage 2); what the operator **chose** (mode, region,
  blend) lives in the agreement (stage 5); what is **running** is read back from the videocomposer's
  `get_state` (runtime, never stored). `display.conf` becomes a **rendering** of the agreement
  (stage 6), not a source to transcribe.
- **F1 becomes trivial.** Each document has exactly one writer and it is a process of this
  repository: the node agent writes the twin, the controller service writes the agreement.

## 3. Process topology

Two services from one Python package (`cuemshardwaremanager`), mirroring the engine's
`cuems-node-engine` / `cuems-controller-engine` split. **Decided 2026-10-22 (D-1)**, including
that both systemd units ship in this package, not in `cuems-common`. In this
document, "node agent" means `cuems-hardware-node` and "controller service" means
`cuems-hardware-controller`.

```
 CONTROLLER host                                         NODE host (also runs on the controller)
 ┌────────────────────────────────────────────┐          ┌──────────────────────────────────────────┐
 │ cuems-hardware-controller.service          │          │ cuems-hardware-node.service              │
 │  PartOf=cuems-controller.target            │          │  PartOf=cuems-node.target                │
 │                                            │          │                                          │
 │  aggregator ── reads network_map.xml       │  node    │  probes/   video · audio · dmx · netdev  │
 │     │          (read-only, NodeIndex)      │  API v1  │     │  (event-driven, show-aware)        │
 │     ├─ dials each adopted node ───────────────────────▶ api/  Rep: hello·get_caps·get_inventory │
 │     │                                      │ ◀──────────     Pub: inventory_changed · presence   │
 │  catalogue   (cluster capabilities,        │          │  twin/  identity · merge · presence      │
 │               cached copies + freshness)   │          │     └─▶ /etc/cuems/hardware_outputs.xml  │
 │  agreement   (setup document, authored)    │  apply   │  apply/ renderers per class ─┐           │
 │     └─ sends each node its slice ─────────────────────▶ guard/  show lock, quiescence │          │
 │  ui-api      ◀── cuems-editor relay (D-5)  │          │                              ▼           │
 └────────────────────────────────────────────┘          │  display.conf · asound/JACK · OLA patch  │
                                                         │  later: VC contract v2 writes            │
                                                         └──────────────────────────────────────────┘
              reads, never writes:  VC contract v1 (ipc), ALSA/sysfs, DRM sysfs, JACK, OLA (:9010), udev
```

**Why two processes, not one role-aware daemon.** Different failure domains and different lifetimes:
the node agent must keep working when the controller is absent, and the controller service must be
able to crash or restart without touching any node's twin. It also matches how role is expressed in
`cuems-common` (`cuems-controller.target` requires `cuems-node.target`; a controller is always also a
node), so a role flip needs no logic in this repository.

**Neither service is a dependency of the show.** No playback unit `Requires=` either of them. A node
whose agent is dead boots and plays its **last applied setup**, exactly as it does today without any
manager. Ordering edges into the playback stack are `Wants=`/`After=` only, and only where stage 6
needs them (§6.3).

### 3.1 The node agent, inside

| Module | Responsibility | Notes |
|---|---|---|
| `probes/<class>` | One probe per hardware class, each a plug-in returning observations. Video, audio, DMX, network displays first | F6: a class is data — the agent iterates registered probes, never a hard-coded triple. Detail in [`02-hardware-classes.md`](02-hardware-classes.md) |
| `twin/` | The **`CuemsHardwareNode`** class, the twin itself. Resolves each observation to a **stable identity**, merges with the previous twin, keeps presence and revision | Identity rules §4.2; the twin never forgets a port on its own (§4.3). Built first, read-only, behind `cuems-hw-mgr probe --json` (D-13) |
| `store/` | Persist the twin through `cuems-utils`' public `ConfigManager` accessor for `hardware_outputs` | The schema, model and accessor are `cuems-utils`'. Today the accessor refuses `HARDWARE_OUTPUTS` by design — upstream gate (§7) |
| `api/` | Serve node API v1 to the controller (§5.2) | Same request/reply/event shape as the VC contract, on purpose |
| `apply/<class>` | Render the node's slice of the agreement into each subsystem's own config, restart in a defined order | Only stage that writes to the box. Refuses while a show is loaded |
| `guard/` | Show-lock and quiescence policy shared by probes and apply | `/tmp/cuems.show.lock` is the same signal the VC reports as `show_loaded` |

### 3.2 The controller service, inside

| Module | Responsibility |
|---|---|
| `aggregator/` | Reads `network_map.xml` through `cuemsutils` (read-only) for the **adopted** nodes, dials each node API, follows its events, re-reads on `pid`/`seq` gaps |
| `catalogue/` | The cluster's capabilities: every node's twin, keyed by node `uuid`, with `revision`, `fetched_at` and reachability. A **cache with provenance**, never a second authority — a node's own file wins |
| `agreement/` | The authored setup document: selection and configuration, referencing discovered ports by `(node uuid, port id)` only |
| `ui-api/` | What the editor relays for the frontend: catalogue reads, agreement edits, apply requests and their refusals |
| `dispatch/` | Sends each node its slice of an accepted agreement, collects per-node results |

## 4. Data model (conceptual)

The XML shape is `cuems-utils`' to define; this is the model it must be able to carry. The
current `hardware_outputs.xsd` is two flat string lists per class and cannot carry it — the
"structure pass" in `hardware-outputs-capability-layer.md` §4 is the upstream work that unblocks
stage 2's persistence.

### 4.1 Entities

```
Node (uuid) ── the join key with network_map.xml; nothing else about the node is restated here
 └─ Device  class · device_key · transport (pci | usb | network | virtual) · vendor/model/serial
     └─ Port  port_id · direction (output | input) · channels · class-specific capabilities
              presence (present | absent | unknown) · first_seen · last_seen · source probe
         └─ Sink (optional) what is plugged in: a monitor (EDID make/model/serial), a projector
```

Agreement, authored, referencing the above and never the reverse (F5: references point from
volatile to stable):

```
Setup ── per node slice
 ├─ Selection     (node uuid, port_id) → enabled · alias · offered to projects
 └─ Configuration per class
      video : mode id · region · blend · pacing        (v2 later: colour, warp)
      audio : which devices join JACK · channel order and naming · bridges
      dmx   : universe ↔ port patch · OLA profile
```

Projects then reference **agreement outputs by id** instead of restating the inventory — the move
that finally retires `default_mappings.xml` and the node section of `project_mappings`
(`etc-cuems-first-install.md` §8.5 step 5).

### 4.2 Identity — physical and stable, never enumeration order

Each `port_id` derives from a physical key that survives reboots, re-enumeration and re-plugging into
the same socket. The per-class keys are in [`02-hardware-classes.md`](02-hardware-classes.md); the
field evidence for why enumeration order is never acceptable is already in this ecosystem:

- HDMI audio pipes are assigned to connectors **at boot**, so the same physical port lands on a
  different ALSA device — the whole reason `cuems-hdmi-audio-map` exists.
- The ALSA card is `PCH` on Intel N97/N100 and `Generic` on AMD; hard-coding the name crash-looped
  `jackd` and took the node engine down.
- Input and output ports sharing one `<id>` numbering made an audio cue route to `system:capture_1`
  and play silent (`cuems-engine` `35cbe78`). Port identity is unique **per node across directions**.
- The VC's mode `id` is stable per connector while the monitor stays the same, and **must never be
  parsed** — use the typed fields.

### 4.3 Presence and retention

- **Three-valued presence.** `unknown` (the kernel or a service could not tell) is never treated as
  `absent` — the VC contract's rule for `connection`, applied to every class.
- **The twin does not forget on its own.** A port seen once stays in the twin as `absent` when
  unplugged, because an agreement may reference it and a show must not silently lose an output
  because a cable was out at boot. Forgetting is an operator act (retention policy: D-6).
- **Revision.** Any change to the twin bumps a monotonic `revision`; promotion and the catalogue key
  freshness on it.

## 5. Contracts

### 5.1 Contracts this repository consumes (it owns none of them)

| Source | Contract | Use |
|---|---|---|
| `cuems-videocomposer` | `docs/contract-v1.md`: NNG Req/Rep `ipc:///tmp/cuems-videocomposer.ipc`, Pub/Sub `…-events.ipc`, JSON, `hello`/`get_caps`/`get_hardware`/`get_state` | Primary video probe while the VC runs. Subscribe first, then read; re-read on `state_changed`, `pid` change or `seq` gap; **never poll `get_hardware`** (it can hitch a loaded node); fall back to files when the socket is absent. "One manager per node" — this repository is that manager |
| Linux | DRM sysfs (`/sys/class/drm/*/status`, `edid`, `modes`), ALSA (`/proc/asound`, `/sys/class/sound`), udev events | Fallback and non-video probes. Read-only; the agent never becomes DRM master |
| JACK | port graph, read-only | Which physical ports JACK exposes. Must not disturb the real-time graph (D-11 on the client choice) |
| OLA | RPC on `localhost:9010` | DMX devices, ports, universes; later patching |
| `cuems-utils` | `ConfigManager` public accessor for `hardware_outputs`; `NodeIndex` for `network_map.xml` | Persistence and topology. Only public paths: `cuemsutils.xml` declares `__all__ == []` |
| `cuems-power-bridge` | `power-bridge.conf` `projector.N.*`, `GET /status` | Network displays (projectors) — described here, controlled there |

### 5.2 The contract this repository will own: node API v1

Modelled **deliberately** on the videocomposer contract so the ecosystem has one management-plane
idiom: `{"v", "id", "op"}` requests, `{"v", "id", "ok", "result" | "error"}` replies, `hello` answers
any version, `get_caps` tokens for optional features, events as `"<topic> <json>"` with per-process
`seq` and `pid`, and the same client rules (subscribe, then read; re-read on gap or new `pid`).

| Op / event | v1 | Meaning |
|---|---|---|
| `hello` | ✓ | `contract_versions`, package version, `pid`, node `uuid` (the controller needs it, unlike the VC's local client) |
| `get_caps` | ✓ | e.g. `inventory_v1`, `probe_video`, `probe_audio`, `probe_dmx` |
| `get_inventory` | ✓ | The twin and its `revision` |
| `get_state` | ✓ | Probe health per class, show-lock state, applied-setup revision |
| `inventory_changed` | ✓ | `{revision}` — re-read |
| `presence_changed` | ✓ | a port's presence flipped — cheap to act on without a full re-read |
| `apply_setup` | v2 | Hand the node its slice; refused with a reason while a show is loaded |

**Transport** (D-2, decided 2026-10-22): local `ipc://` for same-host clients, plus TCP for the
controller, on a port whose value **lives in `settings.xml`**. Both services read it and neither
writes it, because `cuems-init-node` is the sole writer of `settings.xml`. The field is an upstream
`settings.xsd` change in `cuems-utils`, with a default in the system defaults. The controller dials
every node on its own configured value, so the value must be the same on every host. The default is
still open (`9094` is unused in the measured map) and gets a row in `cuems-RELATIONS`' port table.
Socket files are `0660`, owner and group `cuems`, like the VC's, because EDID serials are
personal-ish data. **Not** the engine's NNG bus on `:9093`: that bus belongs to the engine, carries show traffic,
and would make hardware discovery depend on a running engine.

The prototype this repository inherited (`CuemsHwDiscovery.py`, last at `b09b8cc`) pickled a dict
over a raw TCP socket on the node's discovery port, with the master pulling each slave once.
**Rejected**: pickle is code execution on the receiver, there is no versioning, no change events and
no way to re-sync. It remains useful as prior art for *what* was probed (JACK physical ports,
Xinerama screens), not *how*.

## 6. Lifecycle and safety

### 6.1 Boot

1. Node agent starts with `cuems-node.target`, after the services it probes are *wanted*, never
   *required*: it must start and report `unknown` presence when the VC, JACK or OLA are down.
2. It loads the previous twin from disk, probes, merges, persists if changed, serves.
3. On the controller, the controller service starts with `cuems-controller.target`, reads the map,
   dials the adopted nodes, and builds the catalogue as they answer. Unreachable nodes stay in the
   catalogue with their last fetched twin, marked stale.

### 6.2 Probing cadence — event-driven, show-aware

- Triggers: udev (`drm`, `sound`, `usb`, `tty`), VC `state_changed`, JACK port registration, OLA
  device changes, and a slow reconcile timer as the safety net. No tight polling loop: the VC contract
  records a ~0.3 s presentation hitch on a loaded N97 from a sustained 10 Hz JSON job on the node.
- **While a show is loaded** (`/tmp/cuems.show.lock`), probes are restricted to cheap reads; nothing
  that opens DRM, registers into the JACK graph or reconfigures OLA.

### 6.3 Apply (stage 6)

- Only from an accepted agreement, only on an explicit operator request, **refused while a show is
  loaded** — the ecosystem rule *never auto-stop a running project* means apply rejects with a
  reason; it never stops playback to make room.
- Per class, render the subsystem's own config atomically (write temp, rename), keep the previous
  rendering for rollback, restart in a defined order (e.g. ALSA config → `jackd-cuems` →
  `jack-alsa-bridges` → node engine; `display.conf` → VC → node engine, because the engine reads
  `display.conf` only at node start).
- Report per-node, per-class results to the controller; a partial apply is reported as partial, not
  as success.

### 6.4 Degraded modes, each with a real trigger and a log line

| Condition | Behaviour |
|---|---|
| VC socket absent (stopped, older than v1, second instance) | video probe falls back to DRM sysfs and `/run/cuems/display.conf`; retries later |
| JACK down | audio probe reports ALSA devices with JACK exposure `unknown` |
| OLA down | DMX probe reports USB candidates only, OLA view `unknown` |
| Controller unreachable | node keeps its twin and its last applied setup; plays on |
| Node unreachable | catalogue keeps its last twin, marked stale with `fetched_at` |
| Show loaded | probes restricted; apply refused |

## 7. Persistence and privilege

| Path | Cell | Writer | Note |
|---|---|---|---|
| `/etc/cuems/hardware_outputs.xml` | node · discovered | **`cuems-hardware-node`, sole writer** (decided 2026-10-22) | The per-node digital twin. Path and schema decided upstream (`cuems-utils`). **Gate**: the schema's structure pass and a public accessor do not exist yet |
| `/etc/cuems/settings.xml` (the node-API port field) | node · authored | `cuems-init-node` (unchanged) | Read by both services (D-2). **Gate**: the field does not exist in `settings.xsd` yet |
| Setup document (path open, D-3) | cluster · authored | controller service | Probably a seventh `cuems-utils` schema (D-4) |
| Node's applied slice (path open, D-3) | node · authored (copy) | node agent | What the node re-applies standalone |
| `/run/cuems/hardware/` | node · runtime | node agent | Probe state, sockets if not in `/tmp/cuems` |
| Renderings: `display.conf`, ALSA/JACK config, OLA patch | node · runtime / config | node agent (stage 6) | Each one replaces a hand-authored or generated file today — see [`03-ecosystem-seams.md`](03-ecosystem-seams.md) §3 |

- Both daemons run as the **`cuems`** system user (groups `video`, `render`, `audio`, `cuems`), never
  root. `cuems-nodeconf` is the documented sole root daemon in the ecosystem; this repository does not
  become a second one.
- **Amended 2026-10-23 (D-14, constitution 1.1.0):** stage 6's privileged rendering and restarts run
  in root oneshot units shipped here (`cuems-hardware-apply@<class>.service`). They take fixed inputs,
  run at boot, and are started by the daemon only through a sudoers rule naming the exact units (the
  `99-cuems-avahi` pattern).
- Python 3.11 in the shared venv `/usr/lib/cuems/`. The shared venv makes packaging a correctness
  concern (`cuems-power-bridge` lesson: a package must not bundle anything another CUEMS package
  ships). `pynng` is already there.

## 8. What it deliberately does not do

| Not this | Whose |
|---|---|
| Cue-time control (load, play, opacity, volume, DMX frames) | `cuems-engine` and the players |
| Network configuration, discovery of nodes, adoption, node identity | `cuems-nodeconf` |
| Powering projectors or nodes, brightness | `cuems-power-bridge` — it is *described* here, *controlled* there |
| Writing `settings.xml` | `cuems-init-node` is its sole writer; a measured `output_latency_ms` goes into the twin, the operator override stays in `settings.xml` (`etc-cuems-first-install.md` §8.2) |
| Defining schemas, models, accessors | `cuems-utils` |
| Driving DRM while the VC runs | `cuems-videocomposer` holds DRM master; this repository reads sysfs and the contract |
| Host enablement (i915 force-probe in GRUB, recovery entry) | `cuems-common` / provisioning. The output-specific quirks (monitor DDC wake, i915 rebind) are absorb-later candidates here. **GPU policy does move here**: `cuems-gpu-pin` is decided (2026-10-22), and thermalmon's i915 cap is proposed to join it ([`06-machinery-inventory.md`](06-machinery-inventory.md) C13–C14, T1) |
