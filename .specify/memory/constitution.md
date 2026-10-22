# cuems-hardware-manager Constitution

`cuems-hardware-manager` is the CUEMS **hardware manager**. It owns the chain

> real hardware availability → digital twin → node promotion → system total capabilities →
> operator agreement → system setup

On every host, **`cuems-hardware-node`** probes the physically attached hardware: video
connectors and their sinks, audio devices, DMX interfaces and network displays. It keeps a per-node
digital twin under stable names, persists it as `/etc/cuems/hardware_outputs.xml` (schema owned by
`cuems-utils`), and serves it to the controller. On the controller, **`cuems-hardware-controller`**
aggregates every adopted node's twin into the cluster's capabilities, holds the operator's
agreement on which elements the system uses and how they are configured, and dispatches the setup
each node applies.

Python 3.11, import package `cuemshardwaremanager`, shared venv `/usr/lib/cuems/`, Debian bookworm.
The two systemd units are shipped by this package, `PartOf=cuems-node.target` and
`PartOf=cuems-controller.target` respectively, and both run as the `cuems` user.

**What it is not.** Each boundary is stated so that new code does not quietly absorb a sibling's
responsibility; a change that crosses one is a scope violation, not a convenience:

- not cue-time control — that is `cuems-engine` and the players;
- not network configuration, node discovery, adoption or node identity — that is `cuems-nodeconf`;
- not the power or brightness of projectors and nodes — that is `cuems-power-bridge`;
- not the writer of `settings.xml` — that is `cuems-init-node`;
- not the owner of any schema, model or accessor — that is `cuems-utils`;
- not DRM master — that is `cuems-videocomposer`.

## Core Principles

### I. It Runs Beside a Live Show, So It MUST Never Disturb One

The videocomposer contract records a ~0.3 s presentation hitch on a loaded N97 caused by a
sustained 10 Hz JSON job on the node, and tells clients never to poll `get_hardware`. JACK is a
real-time server. Therefore:

- Probing MUST be event-driven, with a slow reconcile as the safety net. Polling loops on
  expensive sources are forbidden.
- While `/tmp/cuems.show.lock` exists, probes MUST restrict themselves to cheap reads. Nothing
  that opens DRM, joins the JACK graph or reconfigures OLA may run during a show.
- Neither service is a dependency of playback. No playback unit may `Requires=` either of them,
  and a node whose agent is dead MUST boot and play its last applied setup.
- Applying a setup MUST be **refused** while a show is loaded. The ecosystem rule *never auto-stop
  a running project* means refuse with a reason; this repository never stops playback to make
  room.

Rationale: the show is the product. A management process that hitches a frame or silences an
output has failed at the only thing that matters, however correct its data.

### II. Observation and Intent Are Different Documents, and Only One Stage Writes to the Box

- **Stages 1–5 never change what is on screen, speaker or fixture.** Those are probe, twin,
  promotion, catalogue and agreement. Only stage 6, setup, touches the box, and only from an
  agreement an operator made.
- **One provenance per document** (`cuems-utils` flag F4). A discovered document carries no
  choices; an authored one carries no probe results.
- **One writer per document**, declared in its schema (F1).
- **Derived facts such as counts are computed, never stored** (F3).
- **`cuems-hardware-node` is the sole writer of `hardware_outputs.xml`**, the per-node digital
  twin. Nothing else, in this repository or outside it, writes that file.

The worked example: `display.conf` geometry (regions, blends, the chosen mode) is authored intent.
It is rendered from the agreement and never transcribed into the discovered twin.

Rationale: a document that mixes what *is* with what someone *chose* has no arbiter when the two
disagree, and the loser is whichever process wrote first.

### III. Identity Is Physical and Stable, Never Enumeration Order

Field evidence, all measured in sibling repositories:

- HDMI audio pipes are assigned to connectors at boot, so ALSA device numbers move. This is the
  reason `cuems-hdmi-audio-map` exists.
- The ALSA card is `PCH` on Intel and `Generic` on AMD; hard-coding it crash-looped `jackd` and
  took the node engine down with it.
- Input and output ports sharing one id numbering routed an audio cue to `system:capture_1`, and it
  played silent (`cuems-engine` `35cbe78`).

Therefore:

- **Ports are keyed by physical attributes**: GPU PCI path plus connector; the video connector,
  for HDMI audio; USB serial or port path; the DMX interface's own serial.
- **Port ids are unique per node across directions.**
- **Nodes are keyed by `uuid`**, the join key with `network_map.xml`. Nothing else about a node is
  restated here.
- **Presence is three-valued** (present, absent, unknown), and `unknown` is never `absent`.
- **The twin does not forget a port on its own.**

Rationale: projects reference outputs as `<node uuid>_<output id>`. An id that moves when a box
reboots, or when a dongle is re-plugged, silently re-routes a show.

### IV. It Consumes Contracts and Schemas It Does Not Own

- **The videocomposer contract v1** is read-only and versioned. Clients MUST ignore fields they
  do not know, and fall back to files when the socket is absent.
- **The `cuems-utils` schemas** are reached through public `ConfigManager` / `NodeIndex` paths
  only; `cuemsutils.xml` declares `__all__ == []`.
- **`network_map.xml` and `power-bridge.conf`** are read-only.

A change needed in any of them MUST be an upstream request in `specs/upstream-reports/`. A local
workaround or a private copy of a schema is forbidden.

Rationale: a private copy keeps resolving. It does not throw, the suite stays green, and the answer
drifts away from the owner's.

### V. Its Own Node API Is a Contract

The node API follows the videocomposer's idiom on purpose, so that the ecosystem has one
management-plane shape:

- requests are `{v, id, op}`;
- `hello` answers any version;
- optional features are announced as `get_caps` tokens;
- events carry a per-process `seq` and `pid`.

A change of meaning MUST bump `v`; additions are optional fields. Pickle, or any serialisation that
executes code on the receiver, is forbidden — the prototype this repository inherited pickled dicts
over raw TCP.

Rationale: the controller, the editor relay and operations tooling will all read this API. A
silent shape change reaches them as wrong data, not as an error.

### VI. A New Hardware Class Is Data, Not Schema

This is `cuems-utils` flag F6.

- Probes are per-class plug-ins.
- Nothing enumerates a hard-coded `('audio', 'video', 'dmx')` triple.
- Adding a class MUST cost a probe and, at most, one `xs:alternative` line upstream.

Rationale: `cuems-utils` measured roughly twenty sites across four repositories per hardware class
today. That cost is what this repository exists to remove; re-creating it here would defeat the
purpose.

### VII. Degraded Is the Normal Case, and Every Degraded Path Has a Real Trigger and a Log Line

The degraded cases are the everyday ones:

- the videocomposer may be stopped, or older than the contract;
- JACK or OLA may be down;
- the controller may be unreachable;
- `cuems-nodeconf` is disabled on most of the fleet, so the map is often hand-maintained;
- nodes go offline.

Each case MUST have a designed behaviour — a fallback source, a stale-but-kept catalogue entry, a
standalone node — named in the spec, triggered by a real condition, and announced by a log line.
An exception handler that happens to swallow the case does not count.

Rationale: on this fleet the degraded path is taken every day. A path nobody designed is a path
nobody can diagnose.

### VIII. Least Privilege

- **It runs as `cuems`, never root.** `cuems-nodeconf` is the ecosystem's one documented root
  exception, and this repository does not become a second.
- **Restarts needed by setup** go through a rule naming the exact units, the same pattern as the
  `99-cuems` sudoers drop-in.
- **Socket files are `0660 cuems:cuems`.** EDID serials are personal-ish data.
- **Anything it creates that another service touches is a permissions decision**, made
  deliberately and stated in the change that creates it.

Rationale: permissions decisions are correctness. `cuems-nodeconf`'s worst recorded defect was a
root-owned IPC socket that crash-looped the engine, but only when nodeconf won the boot race.

## Operating Constraints

**Scope.** Hardware probing, the per-node twin, node promotion, the cluster catalogue, the
operator agreement, and the setup that applies it. It also covers the hardware machinery that
renders that setup into subsystems (see Direction of Travel). The boundaries in the preamble are
permanent; widening them requires an amendment first.

**Units ship here.** This package ships its own systemd units and their privilege rules, attached
to `cuems-common`'s targets with `PartOf=` and `WantedBy=`. `cuems-common` is being stripped of
non-essential responsibilities, so nothing of this repository's goes there.

**The shared venv makes packaging a correctness concern.** This package MUST NOT bundle anything
another CUEMS package ships. The `cuems-power-bridge` `pythonosc` incident is the precedent: one
package's upgrade removed files another package depended on.

**One source per fact.** A hardware fact held in two writable places is a defect to remove, not a
convenience. `specs/planning/06-machinery-inventory.md` records today's copies and the single
source each one should come from.

**Naming and hygiene.**
- Controller/node naming only; no new master/slave identifiers.
- SPDX `GPL-3.0-or-later` headers on every source file.
- Files under `/etc/cuems` are never conffiles (`cuems-utils` D5).
- Comments name a document or a behaviour, never a feature number: two renumberings have already
  cost the siblings.

**Measure, do not transcribe.** Line numbers, commits and counts in planning documents MUST be
re-measured against the live tree, on the branch that is releasing, before being relied upon.

## Direction of Travel — Absorbing the Ecosystem's Hardware Machinery

This repository absorbs hardware machinery from `cuems-common` deliberately, one piece per feature
that replaces it. Already decided to belong here (2026-10-22): `cuems-generate-display-conf`,
`cuems-ola-profile`, `jack-alsa-bridges.service` and `cuems-gpu-pin`. The full measured list is
`specs/planning/06-machinery-inventory.md`, which also records the remaining candidates and the
single-source-of-truth target for every hardware fact. As `cuems-common` is stripped of
non-essential responsibilities, the hardware machinery it sheds lands here rather than being
scattered.

This binds current work in three ways:

- **A piece moves with the feature that replaces it, never ahead of it.** An absorbed script keeps
  its operational guarantees (exit contracts, ships-inert gates, unit ordering such as
  `Before=jackd-cuems.service`) until a spec replaces them explicitly.
- **It never absorbs control from `cuems-power-bridge`, nor network duties from
  `cuems-nodeconf`.** Describing a projector is in scope; powering it is not.
- **Overlaps found in other repositories are resolved by agreement, not by duplication.** Two
  examples are recorded in 06: `display.conf` generation, which the videocomposer also plans, and
  GPU policy, which thermalmon also sets. Neither side builds until the owner is agreed.

## Testing Gate and Development Workflow

**The gate.** CI needs no hardware. Every probe is tested against **recorded fixtures** captured
on real hosts, one fixture set per supported host model (Intel N97/N100, i3-1215U, AMD Picasso
FP530). The fixtures are:
- sysfs and procfs trees;
- videocomposer contract replies (the VC ships a mock and a reference client in
  `tools/contract/`);
- `jack_lsp` output;
- OLA RPC responses.

The suite MUST pass before a feature starts and before any merge, and a feature MUST NOT be
implemented on a red suite.

**Identity has property tests.** Re-enumeration, re-plugging and reboot order MUST NOT change a
port id, and the tests MUST say so explicitly.

**Test-first for parsing and identity code.** These are the paths where a wrong answer keeps
resolving instead of failing.

**What CI proves, and what it does not.** CI proves parsing and identity. It does not prove a host.
Behaviour on real hardware is recorded in a **hardware-verification ledger per feature**, as
`cuems-nodeconf` does. Any change to probing, setup or unit ordering MUST state how it was
verified on real hardware, or state plainly that it was not. Both are acceptable; silence is not.

**Fixtures must not be complicit.** Fixtures MUST be valid against the owning schema or contract.
For a change to a value read from a source this repository does not own, the deliverable includes
a test that fails against the old value.

**Commits** follow Conventional Commits with DCO sign-off, and are GPG-signed with the identity
shared by the sibling repositories. On "gpg failed to sign", retry; never `--no-gpg-sign`.
Planning artifacts live in `specs/planning/`, feature artifacts in `specs/NNN-*/`, and requests to
other repositories in `specs/upstream-reports/`.

## Governance

This constitution supersedes other practices for `cuems-hardware-manager`. Where it and a planning
document disagree, this document governs, and the disagreement is recorded rather than silently
resolved.

**Amendment procedure.** Amendments MUST be proposed as a change to this file, carry a Sync Impact
Report at its head, and state the rationale for the principle added, changed or removed.

- A principle MUST NOT be weakened to make a feature easier, including the first one. If a
  feature cannot satisfy a principle, that is a finding about the feature.
- Widening the repository's responsibility requires an amendment before the work starts. That
  covers a new boundary crossed, or a new class of machinery absorbed beyond what Direction of
  Travel and 06 record.

**Versioning policy.** Semantic versioning of the document itself:
- **MAJOR** — a principle is removed or redefined incompatibly.
- **MINOR** — a principle or section is added, or guidance materially expanded.
- **PATCH** — clarification, wording, or non-semantic refinement.

**Compliance review.** Every feature plan MUST include a constitution check naming which
principles bear on it and how they are satisfied. Reviews MUST verify compliance, and complexity
introduced against a principle MUST be justified in writing rather than assumed. `CLAUDE.md`
remains the runtime development guidance for this repository and is expected to stay consistent
with this document.

**Version**: 1.0.0 | **Ratified**: 2026-10-22 | **Last Amended**: 2026-10-22
