<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# `cuems-hardware-manager` — bootstrap and constitution

**Status (2026-10-22): §1 and §2 done; next is §4 (`/speckit.specify` for feature 001).** The
constitution is ratified at 1.0.0 and `CLAUDE.md` agrees with it. §3 is the context block for every
`/speckit.specify` and `/speckit.plan` in this repository. One item of §5 is still open: the
`cuems-RELATIONS` index row. Structure follows the siblings' runnable flows (`cuems-nodeconf`
`specs/planning/00-runnable-flow.md`).

**Repository:** `/disk/Projects/StageLab/cuems-hardware-manager`

---

## 0. State of this repository, measured 2026-10-22

| | |
|---|---|
| Branches | `main` @ `82efbd9` (spec-kit scaffold, re-signed; one commit ahead of `origin/main` `0e325ff`, not pushed). `docs/architecture-planning`, carrying this planning set (`b5ce86d`) and the constitution commit on top of it; not merged, not pushed |
| Git identity | `Adrià Masip <adria@stagelab.coop>`, GPG key `B25EB0EDCB9F13C2`, `commit.gpgsign true`, in the local config, the same as the siblings. Every commit on both branches since `0e325ff` is signed (`G`) |
| Spec-kit | **present**, 1.2.2, `--integration claude --script sh`, sequential numbering |
| Constitution | **ratified 1.0.0** (2026-10-22): eight principles, Operating Constraints, Direction of Travel, Testing Gate, Governance. Its Sync Impact Report was removed before committing; the one deliberate departure from the §2 prompt is recorded in §2 below |
| `CLAUDE.md` | **corrected** to agree with the constitution: name, role, two units, boundaries, absorption, working rules, field notes (D-12, this repository's half) |
| Existing features | none → the first becomes `001-…` |
| Code | **Corrected 2026-10-23:** `src/cuemshardwaremanager/CuemsHwDiscovery.py` was **not** empty. It was the full prototype (10,763 bytes, 296 lines), moved there intact by `82efbd9`. It imports the deleted `CuemsNode`/`XmlReaderWriter` and does not run on the refactor line. It was removed on 2026-10-23 (node twin feature, T004) and stays in history at `b09b8cc` and `82efbd9` |
| Tests, packaging, CI | none |
| Planning | `00`–`06` written. Decided: D-1 (two units, shipped here), D-2 (own transport, port in `settings.xml`), D-13 (first feature), the stage boundary, the twin's sole writer, and the machinery that belongs here. See `04-open-decisions.md` |
| Upstream | `cuems-nodeconf`'s notice withdrawing the obligation is **open**. The draft acceptance, `05-ownership-notice-draft.md`, is **not sent**. The `cuems-RELATIONS` index row still says `cuems_hwdiscovery` |

---

## 1. Bootstrap — done

`specify init --here --integration claude --script sh` was committed as `7b240a9`, re-signed on
2026-10-22 as `82efbd9` with the siblings' identity. Stay on a feature branch per feature; let
spec-kit name `specs/NNN-<name>/`.

---

## 2. Constitution — done (1.0.0, ratified 2026-10-22)

The prompt below was run as written. The ratified text is `.specify/memory/constitution.md`.

**One deliberate addition.** `cuems-gpu-pin` is listed in Direction of Travel, because it was
decided to belong here after this prompt was written. This is the only place that addition is
recorded: the constitution's Sync Impact Report was removed before committing.

Before ratifying, two cited facts were re-measured: `cuems-engine` `35cbe78` exists, and the VC
ships its mock and client in `tools/contract/` on `feat/contract-report`.

The prompt is kept as the record of what the constitution was derived from. **Do not re-run it to
amend the constitution.** Amendments go through the constitution's own Governance procedure.

```
/speckit.constitution

Establish the constitution for cuems-hardware-manager, grounded in what this repository is and
in failures the CUEMS ecosystem has already paid for. Read, in this order:
  specs/planning/01-architecture.md        the design this constitution governs
  specs/planning/02-hardware-classes.md    per-class evidence; every field note is a rule
  specs/planning/03-ecosystem-seams.md     who owns what
  ../cuems-relations/CLAUDE.md             ecosystem index; "Critical Rules" binds every repo
  ../cuems-nodeconf/.specify/memory/constitution.md and
  ../cuems-power-bridge/.specify/memory/constitution.md   sibling constitutions: match their
                                           structure (Core Principles, Operating Constraints,
                                           Direction of Travel, Testing Gate, Governance) and tone

WHAT THIS REPOSITORY IS: the CUEMS hardware manager. On every host a node agent probes the
physically attached hardware (video connectors and sinks, audio devices, DMX interfaces, network
displays), keeps a per-node digital twin under stable names, persists it as
/etc/cuems/hardware_outputs.xml (schema owned by cuems-utils) and serves it to the controller. On
the controller a second service aggregates every adopted node's twin into the cluster's
capabilities, holds the operator's agreement on which elements the system uses and how they are
configured, and dispatches the setup each node applies. Python 3.11, shared venv /usr/lib/cuems,
Debian bookworm, two systemd services PartOf cuems-node.target / cuems-controller.target, runs as
the cuems user. The chain is: real hardware availability -> digital twin -> node promotion ->
system total capabilities -> operator agreement -> system setup.

WHAT IT IS NOT: cue-time control (engine, players); network configuration, node discovery,
adoption or identity (cuems-nodeconf); power or brightness of projectors and nodes
(cuems-power-bridge); the writer of settings.xml (cuems-init-node); the owner of any schema
(cuems-utils); DRM master (cuems-videocomposer). State these as boundaries, so new code does not
quietly absorb a sibling's responsibility.

PRINCIPLES — derive each from the evidence named; do not soften any of them:

- IT RUNS BESIDE A LIVE SHOW, SO IT MUST NEVER DISTURB ONE. The videocomposer contract measured a
  ~0.3 s presentation hitch on a loaded N97 from a sustained 10 Hz JSON job on the node, and tells
  clients never to poll get_hardware. JACK is a real-time server. So: probing is event-driven with a
  slow reconcile, restricted to cheap reads while /tmp/cuems.show.lock exists; nothing that opens
  DRM, joins the JACK graph or reconfigures OLA runs during a show. Neither service is a dependency
  of playback: no playback unit Requires= them, and a node with a dead agent boots and plays its
  last applied setup. Applying a setup is REFUSED while a show is loaded — the ecosystem rule
  "never auto-stop a running project" means refuse with a reason, never stop playback to make room.

- OBSERVATION AND INTENT ARE DIFFERENT DOCUMENTS, AND ONLY ONE STAGE WRITES TO THE BOX. Stages 1-5
  (probe, twin, promotion, catalogue, agreement) never change what is on screen, speaker or fixture.
  Only setup does, only from an agreement an operator made. A discovered document carries no
  choices and an authored one carries no probe results (cuems-utils flag F4); each document has
  exactly one writer, declared in its schema (F1); derived facts such as counts are computed, never
  stored (F3). cuems-hardware-node is the sole writer of hardware_outputs.xml, the per-node digital
  twin; nothing else in this repository or outside it writes that file. The worked example:
  display.conf geometry is authored intent, so it is rendered from the agreement, never
  transcribed into the discovered twin.

- IDENTITY IS PHYSICAL AND STABLE, NEVER ENUMERATION ORDER. Field evidence: HDMI audio pipes are
  assigned to connectors at boot, so ALSA device numbers move (the reason cuems-hdmi-audio-map
  exists); the ALSA card is "PCH" on Intel and "Generic" on AMD and hard-coding it crash-looped
  jackd; input and output ports sharing one id numbering routed an audio cue to system:capture_1
  and played silent (cuems-engine 35cbe78). So: ports are keyed by physical attributes (GPU PCI path
  + connector, the video connector for HDMI audio, USB serial or port path, the DMX interface's own
  serial), unique per node across directions; nodes are keyed by uuid, the join key with
  network_map.xml, and nothing else about a node is restated. Presence is three-valued and
  "unknown" is never "absent". The twin does not forget a port on its own.

- IT CONSUMES CONTRACTS AND SCHEMAS IT DOES NOT OWN. The videocomposer contract v1 (read-only,
  versioned, "clients must ignore fields they do not know", fall back to files when the socket is
  absent), the cuems-utils schemas through public ConfigManager/NodeIndex paths only
  (cuemsutils.xml declares __all__ == []), network_map.xml read-only, power-bridge.conf read-only.
  A change needed in any of them is an upstream request in specs/upstream-reports/, never a local
  workaround or a private copy of the schema.

- ITS OWN NODE API IS A CONTRACT. It follows the videocomposer's idiom on purpose — {v, id, op}
  requests, hello answering any version, get_caps tokens, events with per-process seq and pid —
  so the ecosystem has one management-plane shape. Meaning changes bump v; additions are optional
  fields. Pickle or any format that executes code on the receiver is forbidden (the inherited
  prototype pickled dicts over raw TCP).

- A NEW HARDWARE CLASS IS DATA, NOT SCHEMA (cuems-utils F6). Probes are per-class plug-ins; nothing
  enumerates a hard-coded ('audio', 'video', 'dmx') triple. Adding a class must cost a probe and at
  most one xs:alternative line upstream; cuems-utils measured roughly twenty sites across four
  repositories per class today, and that cost is what this repository exists to remove.

- DEGRADED IS THE NORMAL CASE, AND EVERY DEGRADED PATH HAS A REAL TRIGGER AND A LOG LINE. The VC may
  be stopped or older than the contract, JACK or OLA may be down, the controller may be unreachable,
  nodeconf is disabled on most of the fleet so the map is often hand-maintained, nodes go offline.
  Each case has a designed behaviour (fallback source, stale-but-kept catalogue entry, standalone
  node) named in the spec — not an exception handler that happens to swallow it.

- LEAST PRIVILEGE. It runs as cuems, never root: cuems-nodeconf is the ecosystem's one documented
  root exception and this repository does not become a second. Restarts needed by setup go through
  a rule naming the exact units (the 99-cuems sudoers pattern). Socket files are 0660 cuems:cuems;
  EDID serials are personal-ish data. Anything it creates that another service touches is a
  permissions decision, and permissions decisions are correctness (nodeconf's worst recorded bug
  was a root-owned IPC socket crash-looping the engine).

OPERATING CONSTRAINTS to record: this package ships its own systemd units and their privilege
rules, attached to cuems-common's targets with PartOf=/WantedBy= (cuems-common is being stripped
of non-essential responsibilities, so nothing of this repository's goes there); the shared venv makes packaging a correctness concern — never
bundle what another CUEMS package ships (the power-bridge pythonosc incident); controller/node
naming only, no new master/slave identifiers; SPDX GPL-3.0-or-later headers; Conventional Commits
with DCO sign-off; files under /etc/cuems are never conffiles (cuems-utils D5); comments name a
document or a behaviour, never a feature number (two renumberings already cost the siblings).

DIRECTION OF TRAVEL to record: this repository absorbs hardware machinery from cuems-common
deliberately, one piece per feature that replaces it. Already decided to belong here:
cuems-generate-display-conf, cuems-ola-profile, jack-alsa-bridges.service. The full measured list,
and the single-source-of-truth target for every hardware fact, is
specs/planning/06-machinery-inventory.md. One source per fact: a hardware fact held in two
writable places is a defect to remove, not a convenience. As cuems-common is stripped of non-essential
responsibilities, hardware machinery it sheds lands here. It never absorbs control from cuems-power-bridge or
network duties from cuems-nodeconf.

TESTING GATE: a gate this repository can meet without hardware in CI. Every probe is tested against
RECORDED FIXTURES captured on real hosts (sysfs/procfs trees, VC contract replies — the VC ships a
mock and reference client in tools/contract/ — jack_lsp output, OLA RPC responses), one fixture set
per supported host model (Intel N97/N100, i3-1215U, AMD Picasso FP530). The identity rules get
property-style tests (re-enumeration, re-plugging, reboot order must not change a port id).
Behaviour on real hardware is recorded in a hardware-verification ledger per feature, as
cuems-nodeconf does — be explicit that what CI proves is parsing and identity, and what the ledger
proves is the host. Test-first for parsing and identity code.

Do NOT weaken any principle to make the first feature easier.
```

---

## 3. Context block — paste into every `/speckit.specify` and `/speckit.plan`

```
CONTEXT — read before writing anything.

IN THIS REPOSITORY:
  .specify/memory/constitution.md         v1.0.0 — the eight principles every spec and plan checks
  specs/planning/01-architecture.md       six stages, two services, data model, contracts, safety
  specs/planning/02-hardware-classes.md   per class: sources, identity keys, twin vs agreement vs setup
  specs/planning/03-ecosystem-seams.md    ownership, absorption candidates, gates
  specs/planning/04-open-decisions.md     D-1..D-13 with recommendations; the proposed feature split
  specs/planning/06-machinery-inventory.md   every hardware piece in the siblings, shipped or not;
                                          the fact-by-fact single-source-of-truth table
  git show b09b8cc:CuemsHwDiscovery.py    the prototype — prior art for WHAT was probed, not HOW

IN SIBLING CHECKOUTS (/disk/Projects/StageLab/):
  cuems-videocomposer, branch feat/contract-report, docs/contract-v1.md   THE video source; v1 is
      read-only. Client rules: subscribe then read; re-read on state_changed, pid change, seq gap;
      never poll get_hardware; fall back to /run/cuems/display.conf when the socket is absent.
  cuems-utils/specs/planning/hardware-outputs-capability-layer.md   the layer's history and gates
  cuems-utils/specs/planning/etc-cuems-first-install.md §7-§8       the design argument: the
      scope x provenance basis, flags F1-F6, the new-hardware-class test
  cuems-utils/src/cuemsutils/xml/schemas/hardware_outputs.xsd and project_mappings.xsd
      the current shapes (hardware_outputs: flat string lists, no accessor, reserved)
  cuems-nodeconf/specs/upstream-reports/hardware-outputs-obligation-withdrawn.md   why this
      repository exists; still OPEN until cuems-utils re-assigns the work
  cuems-common (origin/rc_1 README; feat/xml-refactor tree): jackd-cuems, jack-alsa-bridges,
      cuems-hdmi-audio-map, cuems-generate-display-conf, cuems-display-setup, cuems-ola-profile,
      olad.service, docs/latency-tuning.md, docs/ola-install.md, CLAUDE.md field notes
  cuems-engine/src/cuemsengine/NodeEngine.py   how hardware is consumed today: node_hw_outputs,
      node_mappings, read_display_conf, DISPLAY_MISMATCH
  cuems-power-bridge/src/cuemspowerbridge/displays/   projector control (PJLink, ESC/VP.net)
  cuems-relations/CLAUDE.md   ports, protocols, critical rules, naming

SETTLED — do not reopen without the maintainer:
  - Two units (D-1, 2026-10-22): cuems-hardware-node on every host (PartOf cuems-node.target),
    cuems-hardware-controller on the controller (PartOf cuems-controller.target). Both units,
    and stage 6's scoped restart rule, ship in THIS package, never in cuems-common, which is
    being stripped of non-essential responsibilities.
  - Stages 1-5 only observe and record; stage 6 is the only one that changes a box, and it
    applies the operator's agreement (2026-10-22).
  - cuems-hardware-node is the SOLE writer of /etc/cuems/hardware_outputs.xml, the per-node
    digital twin (2026-10-22).
  - The node API has its own transport, not the engine bus, on a port whose value lives in
    settings.xml (D-2, 2026-10-22). Both services read it, neither writes it (cuems-init-node is
    settings.xml's sole writer), and it must be the same on every host. The settings.xsd field is
    an upstream cuems-utils change.
  - This repository owns the probe, the twin, the catalogue, the agreement and the setup.
    cuems-nodeconf reads and writes no hardware data (withdrawn 2026-10-21).
  - cuems-utils owns every schema, model and accessor; this repository uses public paths only.
  - cuems-generate-display-conf, cuems-ola-profile, jack-alsa-bridges.service and cuems-gpu-pin
    belong to THIS repository (2026-10-22); the generator stays the VC's ExecStartPre via a
    drop-in shipped here.
    The VC owns /run/cuems/display.conf at run time and owns the display.conf format.
  - hardware_outputs.xml is per node, describes only that node, and is joined to network_map.xml
    by uuid only.
  - Never auto-stop a running project: setup refuses while a show is loaded.

MEASURED STARTING STATE (2026-10-22, corrected 2026-10-23): no code (the outdated prototype
CuemsHwDiscovery.py was removed; it was never empty); no tests; no
packaging. hardware_outputs.xsd cannot carry the twin; ConfigManager refuses HARDWARE_OUTPUTS by
design; default_mappings.xml is still the node inventory that cuems-generate-display-conf and the
engine read.
```

---

## 4. First feature — sketch

**Decided 2026-10-22 (D-13).** The first feature is a CLI with JSON output,
**`cuems-hw-mgr probe --json`**. It reads and discovers the host and builds the **complete digital
twin** as a `CuemsHardwareNode` object. Nothing is sent to the controller and no file is written.
The twin's shape is worked out here, in code and JSON. It is promoted to XSD/XML (`cuems-utils`)
later, so the JSON model is what the upstream structure pass will be derived from.

```
/speckit.specify <PASTE CONTEXT BLOCK>

Node digital twin from discovery: on any CUEMS host, `cuems-hw-mgr probe --json` reads the system
and prints the complete digital twin of the node: every video, audio and DMX device and port under
a stable identity. The centre of the feature is the CuemsHardwareNode object class: the in-memory
twin that later features persist (hardware_outputs.xml, written only by cuems-hardware-node) and
serve to the controller. The CLI is a thin view over it.

THE TWIN, CuemsHardwareNode — what it must model (01-architecture.md §4):
- Node, keyed by the uuid read from settings.xml, and nothing else about the node restated.
- Devices: class, device_key, transport (pci | usb | network | virtual), vendor/model/serial.
- Ports: port_id, direction, channels, class-specific capabilities, presence, source probe.
- Sinks where they exist (a monitor's EDID make/model/serial).
- Classes are data: the node iterates registered probes, with no hard-coded class triple.
- Serialises to JSON deterministically (stable key order, stable port order), so two probes of an
  unchanged host produce byte-identical output. This JSON is the draft of the future schema.

WHAT MUST BE TRUE WHEN DONE:
- Video from the VC contract v1 when its socket answers, else from DRM sysfs, else from
  /run/cuems/display.conf; the report says which source answered.
- Audio from ALSA with HDMI audio attributed to its video connector, USB audio by USB identity;
  JACK exposure reported when JACK runs, "unknown" otherwise.
- DMX from OLA's RPC when olad runs, USB candidates otherwise; OLA's numeric aliases are never ids.
- Port ids are stable across reboot, re-enumeration and re-plugging into the same socket, and unique
  per node across directions — proven by tests against recorded fixtures from each host model.
- Presence is present | absent | unknown; nothing reports "absent" for "could not tell". With no
  persisted previous twin, "absent" in a single run means the hardware enumerates the port but
  nothing is attached (a disconnected connector). Remembering ports that have disappeared across
  runs belongs to the persistence feature.
- The probe opens nothing that disturbs a show: no DRM master, no JACK client registration, no OLA
  writes; with /tmp/cuems.show.lock present it restricts itself to cheap reads.
- For every port, the report also records the id today's default_mappings.xml gives it. Projects
  reference outputs as <node uuid>_<output id>, so the twin's ids either reproduce today's on an
  unchanged host or need a migration (06-machinery-inventory.md finding 6).
- The video fallback starts from cuems-display-setup's DRM/EDID reading (cuems-common tree,
  unshipped; includes the sysfs size-0 EDID fix 5c266c3) rather than rewriting it blind.
- Runs as the cuems user; exit status distinguishes "twin built" from "twin built with degraded
  sources" from "could not run".

FIELD NOTES THIS FEATURE MUST SETTLE (CLAUDE.md "Field notes / gotchas"; 06-machinery-inventory.md):
- OLA rogue olad (06 finding 13). libola auto-starts its own olad whenever nothing listens on
  :9010. A read-only DMX probe that connects naively would START a rogue olad as cuems and break
  DMX on the host. The probe MUST check :9010 before connecting, or use a client that cannot
  auto-start, and a fixture-backed test must prove no olad is spawned. Identity follows OLA's own
  key: the interface serial (/etc/ola/ola-port.conf, 13-<SERIAL>-O-<port>). Eurolite MK2 dongles
  show stock FT232R descriptors and are distinguishable by serial only.
- canvas_region read as pixels (06 finding 3). For id continuity this feature reads
  default_mappings.xml. It MUST interpret canvas_region as the schema defines it (normalised
  [0, 1], a UI hint), never as pixels, and it MUST report, as a diagnostic in the JSON, any value
  that would make cuems-generate-display-conf raise in the VC's ExecStartPre. The fix itself
  belongs to the video setup feature, or to cuems-common earlier; not here.
- The VC's display.conf "Phase A" (06 finding 10). The video fallback reads display.conf but never
  assumes which file the VC used. It records the VC's get_state config_source when the socket
  answers, and the path it actually read otherwise (/run/cuems/display.conf, the operator override
  /etc/cuems/display.conf, or the VC's XDG fallback). Who GENERATES display.conf is not this
  feature's question. It is recorded as an open item for the video setup feature, to agree with
  the VC team.
- The dead hw_discovery chain (06 finding 2). This feature serves no API and does not answer
  /tmp/hwdiscovery.ipc. The spec states that explicitly, so that nobody wires the CLI into that
  socket early. Reuse or retirement is decided under D-5.

WHEN THIS FEATURE IS DONE, CLAUDE.md "Field notes / gotchas" is updated: each of the four entries
above is either resolved (and says how), or narrowed to what is still open, with a pointer to the
feature that will close it.
```

Then `/speckit.clarify`. Force four questions:
- **What is the stable key for a DMX interface that reports no serial**, and what does the probe do
  when two identical ones are attached?
- **Which of the twin's JSON fields are identity, and which are observation?** The persistence
  feature will need to tell "the same port, re-observed" from "a different port", so the split has
  to be explicit in the model now.
- **How does the DMX probe guarantee it never auto-starts `olad`?** A port check before
  connecting, or a client built without auto-start? And what is reported when `olad` is down?
- **Where do diagnostics live in the JSON?** The `canvas_region` hazard, a host with zero video
  connectors that should have some, OLA down: inside the twin, or beside it? Diagnostics are
  observations about the host, not part of its identity, and the answer shapes the future schema.

Field notes recorded in 06 that this feature covers without a separate question:
- **GPU identity** (finding 14) is recorded on the video device, so `cuems-gpu-pin` can key on it
  later.
- **NDI** (finding 11): the model leaves room for network video ports. They are not probed in 001.
- **Fixtures** are checked against `cuems-fleet`'s per-site records (finding 12).

---

## 5. Exit criteria for this step

| Criterion | State (2026-10-22) |
|---|---|
| `.specify/memory/constitution.md` ratified at 1.0.0, no placeholders left | **Done** |
| Its principles trace to §2 | **Done**. The one addition (`cuems-gpu-pin`) is recorded in §2 |
| The maintainer's rulings so far are reflected (D-1, D-2, D-13, stage boundary, twin writer, machinery) | **Done** |
| `CLAUDE.md` corrected to `cuems-hardware-manager` and agrees with the constitution (D-12, this repository) | **Done** |
| `cuems-RELATIONS` index row corrected (D-12, the other half) | **Open**. It still says `cuems_hwdiscovery` under Ops/provisioning; it should say `cuems-hardware-manager` under Core components. This is a change in that repository |
| Committed, signed | **Done** on `docs/architecture-planning` (constitution, `CLAUDE.md`, this file, planning README) |
