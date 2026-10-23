<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Feature Specification: Node digital twin from discovery

**Feature Branch**: `feat/hw-mgr-v0`

**Created**: 2026-10-22

**Status**: Draft

**Input**: User description: "Node digital twin from discovery: on any CUEMS host, `cuems-hw-mgr probe --json` reads the system and prints the complete digital twin of the node: every video, audio and DMX device and port under a stable identity. The centre of the feature is the CuemsHardwareNode object class: the in-memory twin that later features persist (hardware_outputs.xml, written only by cuems-hardware-node) and serve to the controller. The CLI is a thin view over it." The full brief is the `/speckit-specify` input of 2026-10-22, reproduced as the §4 prompt of `specs/planning/00-runnable-flow.md`.

**Stage**: 1 (availability) + 2 (digital twin, in memory only). Decided scope: D-13 in `specs/planning/04-open-decisions.md`.

## Clarifications

### Session 2026-10-22

- Q: What should identify a DMX interface that reports no serial number, and how should two identical serial-less interfaces be told apart? → A: Key on the physical USB port path and mark the identity as weak, so identical interfaces are told apart by socket. The node must also be part of the address: a physical port is addressed cluster-wide as (node uuid, `port_id`). Two identical devices on two different nodes, even on the same socket path, then never collide when the controller routes DMX (or any class) to them.
- Q: In the twin's JSON, should the fields that make a port "the same port next time" be kept visibly apart from the fields that only describe what was seen on this run? → A: Yes, as a structural split. Every device and port has an `identity` object and an `observed` object.
- Q: How should the DMX probe guarantee that it never starts a rogue `olad` when it reads OLA? → A: Both layers: check that `:9010` is listening first, and connect only through a client path that cannot auto-start `olad`. If either fails, the OLA view is `unknown` and DMX falls back to USB candidates.
- Q: Where in the JSON output should diagnostics live: the `canvas_region` hazard, a host with zero video connectors, OLA down, the `display.conf` provenance and the legacy-id continuity? → A: One document with `twin` and `report` side by side. The boundary is provenance, not "diagnostic or not". Everything read from sources an operator does not edit goes into `twin` and will be persisted: hardware, files written by services, and facts derived directly from an active daemon. Only operator-authored inputs and per-run metadata go into `report`. Following `cuems-nodeconf`'s mechanics, the persisted document coexists with a refresh cadence for live information. So every twin field is classed as either persisted state or live state.
- Q: The videocomposer's `get_state` reports the geometry it is currently driving (canvas, regions, blends, pacing). Should that geometry go into the twin? → A: As live state only. The VC is the entity that extracts capabilities, and the twin persists them: connectors, modes, preferred mode, sinks and the VC's `get_caps` tokens. What the VC is driving now (current mode, `config_source`, `get_state` geometry) is live twin state, refreshed and never written to the persisted document. The operator's agreement chooses among the capabilities and is where **permanence** lives: per-screen resolution as a mode `id`, canvas region, blend, deformation/warp, pacing, and which outputs are offered to projects as cue outputs. `display.conf` is a rendering of that agreement. Live geometry in the twin serves to show drift against the agreement.
- Maintainer ruling, outside the five questions: JACK relations need further research and agreement with the team. In this feature the JACK exposure field exists and is reported `unknown` (FR-018a). The spec branch is cut from the eventual merge, so work returns to `feat/hw-mgr-v0` afterwards.

## User Scenarios & Testing *(mandatory)*

The people this feature serves:

- **The integrator / operator at a host.** Needs to know what a box can actually drive, under names that will still be true tomorrow.
- **Operations (`cuems-fleet` `census`).** Today a person retypes every node's hardware into `nodes.yaml`, `devices.yaml` and `dmx.yaml`. Operations wants to record the probe's output instead.
- **The maintainers of the later stages.** Persistence, the node API, the catalogue, the agreement and setup all build on the twin's shape and ids. `cuems-utils` will promote the JSON shape to a schema.

### User Story 1 - See the whole node, under stable names (Priority: P1)

An integrator runs `cuems-hw-mgr probe --json` on any CUEMS host. They get one JSON document describing the node, keyed by its uuid. It lists every video, audio and DMX device the host has and every port on each device, under ids derived from physical attributes. It also says, for each class, which source answered.

**Why this priority**: Every later stage consumes this twin, so nothing else in the repository can start without it. It is also useful on its own the day it lands: it replaces hand-typed hardware records in operations.

**Independent Test**: Run the probe against a recorded fixture set from each supported host model, with every source up. Compare the output with that fixture's expected twin, byte for byte. Run it twice and compare the two outputs.

**Acceptance Scenarios**:

1. **Given** an N97 host whose videocomposer answers the contract, with two monitors and one disconnected HDMI connector, **When** the probe runs, **Then** the twin lists one GPU video device with three output ports. The two connected ones are `present` and carry their sinks (EDID make/model/serial) and mode lists. The third is `absent`. The report names the videocomposer contract as the video source.
2. **Given** a host with HDMI audio, onboard main L/R outputs, a multichannel card and an external USB DSP, **When** the probe runs, **Then** all four appear with their outputs and inputs.
   - Each HDMI audio port is attributed to the video connector it rides on.
   - The USB DSP is keyed by its USB identity.
   - The onboard and multichannel devices are keyed by PCI path.

   No id contains an ALSA card name or index.
3. **Given** a host with `olad` running and a Eurolite USB-DMX512 PRO MK2 attached, **When** the probe runs, **Then** the DMX port's id derives from the interface serial. OLA's numeric device alias appears nowhere in any id.
4. **Given** an unchanged host, **When** the probe runs twice, **Then** the two JSON outputs are byte-identical.
5. **Given** any host, **When** the probe runs, **Then** the twin contains the node uuid read from `settings.xml` and no other node attribute (no hostname, IP, MAC or role).

---

### User Story 2 - Ids that do not move (Priority: P1)

A maintainer of a later stage relies on a port's id staying the same when the box reboots, when the kernel enumerates devices in a different order, and when a USB device is re-plugged into the same socket. Projects reference outputs as `<node uuid>_<output id>`, so an id that moves silently re-routes a show.

**Why this priority**: Constitution Principle III. Ids are load-bearing from the first day anything persists or references them. A wrong id keeps resolving instead of failing, so this must be proven before anything is built on it.

**Independent Test**: Property-style tests over the recorded fixtures. Permute the enumeration order, move DRM card numbers, renumber ALSA cards and devices, reassign the HDMI pipes to different ALSA devices, re-plug a USB device into the same socket and re-order OLA's device aliases. Assert that every port id is unchanged.

**Acceptance Scenarios**:

1. **Given** a fixture whose DRM cards enumerate as `card1`/`card0` instead of `card0`/`card1`, **When** the probe runs, **Then** every video port id is the same as in the original fixture.
2. **Given** a fixture where the boot-time pipe assignment moves an HDMI audio port from ALSA device 3 to device 7, **When** the probe runs, **Then** that audio port's id is unchanged, because it follows its video connector.
3. **Given** a USB audio interface or DMX dongle re-plugged into the same socket, after its bus/device number changed, **When** the probe runs, **Then** its port ids are unchanged.
4. **Given** any fixture, **When** the probe runs, **Then** no two ports on the node share an id, inputs and outputs included.
5. **Given** two Eurolite MK2 dongles with identical USB descriptors and different serials, **When** the probe runs, **Then** they get distinct ids, each derived from its serial, and the ids do not change if the dongles swap sockets.
6. **Given** fixtures of two different nodes, each with an identical serial-less DMX interface on the same USB socket path, **When** both are probed, **Then** each port is flagged as weak identity. The pairs (node uuid, `port_id`) differ, so a route addressed to one node's interface can never reach the other's.

---

### User Story 3 - Safe beside a live show (Priority: P1)

An operator, or `cuems-fleet` `census`, runs the probe on a node that is playing a show. Nothing on screen, speaker or fixture changes. No frame hitches, no JACK xrun is caused, and no rogue `olad` appears.

**Why this priority**: Constitution Principle I, the first principle. A probe that disturbs a show has failed, however correct its data. Operations will run it on live venues.

**Independent Test**: Run against fixtures and fakes that record what the probe opens, connects to and spawns. Assert that the forbidden actions never happen. Prove with a fake where nothing listens on `:9010` that no `olad` is spawned. On real hardware, record the result in the hardware-verification ledger.

**Acceptance Scenarios**:

1. **Given** any host state, **When** the probe runs, **Then** it never becomes DRM master, never registers a JACK client, never writes to OLA, and never writes a file.
2. **Given** nothing listening on `localhost:9010`, **When** the DMX probe runs, **Then** no `olad` process is started. DMX falls back to USB candidates, and the OLA view is reported as `unknown`.
3. **Given** `/tmp/cuems.show.lock` exists, **When** the probe runs, **Then** it restricts itself to cheap reads (FR-024). The report says that the show-lock mode was in force, and lists each fact it did not gather because of it.
4. **Given** the videocomposer answers, **When** the probe runs, **Then** it reads `get_hardware` at most once, follows the contract's client rules, and never polls.

---

### User Story 4 - Degraded is reported, never hidden (Priority: P2)

On a node where the videocomposer is stopped, JACK is down or OLA is not running, the probe still produces a twin from the fallback sources. It says which sources were degraded and why, and its exit status lets `census` tell "full twin" from "twin with degraded sources" from "could not run".

**Why this priority**: Constitution Principle VII. These states are everyday ones on this fleet. Without this story the twin is right only when everything is up.

**Independent Test**: Run against fixtures with each source removed in turn: VC socket absent, `olad` not running, `settings.xml` missing. Check the fallback source chosen, the presence values, the report's degradation entries, the log line and the exit status.

**Acceptance Scenarios**:

1. **Given** the VC socket is absent, **When** the probe runs, **Then** video comes from DRM sysfs. The report names DRM sysfs as the video source and the VC's absence as the reason, and the exit status is "twin built with degraded sources".
2. **Given** the VC socket is absent and DRM sysfs exposes no connectors, **When** the probe runs, **Then** video comes from the `display.conf` the probe found, with presence `unknown`. The report names the exact path it read.
3. **Given** any JACK state, running or not, **When** the probe runs, **Then** every audio port's JACK exposure is `unknown` with the reason `pending JACK relations agreement`, never "not exposed". This alone does not make the exit status "degraded" (FR-018a).
4. **Given** a source the probe could not read, for example because of a permission, **When** the probe runs, **Then** the affected ports' presence is `unknown`, never `absent`.
5. **Given** `settings.xml` is unreadable or has no node uuid, **When** the probe runs, **Then** it exits "could not run" with the reason, and prints no twin.
6. **Given** every source answered, **When** the probe runs, **Then** the exit status is "twin built".

---

### User Story 5 - Continuity and hazards for the next stages (Priority: P2)

A maintainer planning the move off `default_mappings.xml` needs to know, for every port, what today's mappings call it. They also need any value already sitting on the host that would break today's `display.conf` generation, and which `display.conf` the videocomposer actually started from.

**Why this priority**: 06 findings 3, 6 and 10. Existing projects reference outputs by today's ids, so the migration cannot be planned without this mapping. The `canvas_region` hazard is a live defect, and this probe is the first tool that can see it on every host.

**Independent Test**: Run against fixtures that include a `default_mappings.xml` with audio, video and DMX entries, a template output carrying a fractional `canvas_region`, and an entry for hardware that is not attached. Check the continuity records, the diagnostics and the reported `display.conf` provenance.

**Acceptance Scenarios**:

1. **Given** a `default_mappings.xml` whose audio output `system:playback_1` corresponds to a physical port, **When** the probe runs, **Then** the report records against that port's twin id: the legacy direction, the legacy id, the legacy name, and the compound reference `<uuid>_system:playback_1`.
2. **Given** a mappings entry that matches no discovered port (a template "custom" output, or hardware that is gone), **When** the probe runs, **Then** it is listed as an unmatched legacy entry. It is never attached to a port by position.
3. **Given** a video output whose `canvas_region` holds a schema-valid value such as `0.5` or `0.0`, **When** the probe runs, **Then** the report carries a diagnostic naming the node, the output and the value, and stating that `cuems-generate-display-conf` would fail on it in the VC's `ExecStartPre` when no operator `display.conf` override exists.
4. **Given** the VC answers, **When** the probe runs, **Then** the twin records the VC's `get_state` `config_source` as the `display.conf` in use, as live state. **Given** the VC does not answer and video falls back to a file, **Then** the report records the path actually read: `/run/cuems/display.conf`, the operator override `/etc/cuems/display.conf`, or the VC's XDG fallback.

---

### Edge Cases

- **Zero video connectors on a host that should have some.** For example, Meteor Lake without `i915.force_probe`, where `/dev/dri` is absent. This produces a diagnostic, not just an empty list.
- **Connected but not driven.** A monitor plugged in after the VC started reports `current: null`. That is a normal twin state (present sink, no current mode), not an error.
- **VC reports `connection: unknown`.** The port's presence is `unknown`, never `absent`.
- **The VC answers, but the contract carries no GPU PCI path.** The port's physical key still needs it. The probe joins the VC's connector names with DRM sysfs, which is readable without DRM master. If the join cannot be made, the port is reported with its identity unresolved, and the report says why.
- **Two GPUs.** Connector names repeat across GPUs (`HDMI-A-1` on each). Ids stay distinct because the GPU's PCI path is part of the key.
- **A VC newer than v1.** Unknown fields are ignored (Principle IV). **A VC older than v1** has no socket: fallback.
- **The VC restarts during the probe** (`pid` change or `seq` gap). The probe re-reads once. If the state is still moving, video is reported degraded rather than looping.
- **An unresponsive VC or OLA.** Each source has a bounded wait. A timeout means that source is degraded, never a hang.
- **A USB audio or DMX device with no serial.** The key falls back to the physical USB port path, and the twin marks the identity as weak (port-path-based). Two identical serial-less devices on one node are distinguished by their sockets. On two different nodes they may share a `port_id`, and the node uuid tells them apart (FR-010a).
- **A DMX interface OLA reports that is not on USB** (ArtNet/sACN nodes OLA sees). Transport is `network`, and the id derives from the unique name OLA reports for the device, never its numeric alias.
- **`olad` running but not answering RPC.** The OLA view is `unknown`, and the probe falls back to USB candidates.
- **The ALSA card is `PCH` on Intel and `Generic` on AMD.** Neither name appears in any id. Both host families are covered by fixtures.
- **HDMI audio whose connector cannot be determined** (for example in show-lock mode, if the attribution needs a device open). Attribution is `unknown`. It is never guessed from the ALSA device number.
- **Input and output on the same physical audio device.** They are separate ports with distinct ids.
- **The show lock appears or disappears mid-probe.** The probe decides its mode once at start and reports that mode. If the lock appears during the run, any remaining expensive read is skipped and reported as skipped.
- **Run as root.** The probe refuses to run ("could not run"), so that it never becomes the second root process of the ecosystem by accident. **Run as a non-root user other than `cuems`.** It runs, and sources that user cannot read are reported degraded (for example the `0660 cuems:cuems` VC socket).
- **`default_mappings.xml` absent** (a host already migrated, or one never seeded). The continuity section is empty and says why. This is not a degradation of the twin.
- **`default_mappings.xml` describes other nodes too.** Only the local node's entries (by uuid) are used for continuity.

## Requirements *(mandatory)*

### Functional Requirements

**The twin (`CuemsHardwareNode`)**

- **FR-001**: The feature MUST provide an in-memory twin of the node, `CuemsHardwareNode`, which is the only thing the CLI renders. Later features persist and serve this same object. It is not re-derived by them.
- **FR-002**: The twin MUST be keyed by the node uuid. The uuid is read from `settings.xml` through `cuems-utils`' public interface, and is never minted, inferred or restated from another document. The twin MUST NOT carry any other node attribute: no hostname, address, MAC or role.
- **FR-003**: Each **device** MUST carry its class, `device_key`, transport (`pci` | `usb` | `network` | `virtual`), vendor, model and serial, with absent values explicitly empty or `unknown`, never omitted ad hoc. A GPU MUST be recorded as the video device its connectors belong to, with its PCI identity, so that GPU policy can key on it later.
- **FR-004**: Each **port** MUST carry its `port_id`, direction (`output` | `input`), channel count where meaningful, class-specific capabilities (for example a video port's mode list and preferred mode, or a DMX port's RDM support), presence, and the source probe that observed it.
- **FR-005**: A port MUST carry its **sink** where one is detected: for video, the attached monitor or projector's EDID make, model and serial.
- **FR-006**: The model MUST separate identity from observation **structurally**, as two objects on every device and every port. Persistence has to tell "the same port, re-observed" from "a different port".
  - The **`identity`** object holds what makes it the same thing next time: class, the physical key and its parts, `device_key` or `port_id`, direction (for a port), and the key strength (serial-based or port-path-based).
  - The **`observed`** object holds what this run saw: transport details, vendor/model/serial where they are not part of the key, presence, channels, capabilities, sink, JACK exposure and source probe.

  No field may appear in both objects. Two observations of the same thing MUST have equal `identity` objects.
- **FR-007**: Hardware classes MUST be data. The twin is built by iterating the registered per-class probes. No code path enumerates a fixed set of classes. Adding a class MUST require only a new probe, with no change to the twin, the identity resolver or the serialiser.
- **FR-008**: Everything in the twin MUST be discovered, and no operator-authored value may enter it (Principle II, F4). Discovered means read from a source an operator does not edit:
  - the hardware itself (sysfs, procfs, USB descriptors, EDID);
  - files written by services, for example `/etc/asound.conf` as `cuems-hdmi-audio-map` writes it at boot (live state, research R7);
  - facts reported directly by an active daemon, for example the VC contract's `get_hardware` and `config_source`, OLA's device view, and JACK exposure.

  A fact that a service holds or writes but that encodes an operator's choice is **live** state only, never persisted. Examples are the geometry the VC drives (FR-008b) and OLA's current universe ↔ port patch (`/etc/ola/ola-port.conf`, `FetchUniverses`). The operator agreement owns those choices (`specs/planning/06-machinery-inventory.md` §3).

  Operator-authored inputs MUST NOT enter the twin: `default_mappings.xml` names, ids and `canvas_region`, and the operator's `/etc/cuems/display.conf`. Where the feature reports them, they go in the report (FR-026).
- **FR-008b**: Video MUST split across three places by role.
  - **Capabilities, as persisted state.** The VC is the entity that extracts video capabilities. The twin records, as persisted state:
    - its connectors, modes (VC `id` plus typed fields) and preferred mode;
    - the sinks;
    - the VC's `get_caps` tokens, so that a capability a later VC announces (for example warp, blend or pacing support) appears as data with no change to the twin's shape.
  - **What the VC is driving now, as live state only.** This covers the current mode per connector, `config_source`, and the geometry `get_state` reports (canvas, regions, blends, pacing). It MUST NOT be written to the persisted document. It is never a source of truth; it exists so that later stages can show drift between what the agreement chose and what is running.
  - **Permanence of chosen geometry belongs to the operator agreement, not to the twin.** That covers per-screen resolution (a mode `id` from the twin), canvas region, blend, deformation/warp, pacing, and which outputs are offered to projects as cue outputs. `display.conf` is a rendering of the agreement. Neither is in scope here.
- **FR-008a**: Every field in the twin's `observed` object (FR-006) MUST be classed, in the documented shape (FR-028), as one of two kinds:
  - **persisted state**: changes only when the hardware or its service configuration changes, for example connectors, modes, sinks, device serials and channel counts;
  - **live state**: may change while nothing physical changes, for example presence, the VC's current mode and driven geometry (FR-008b), JACK exposure and OLA running state.

  This lets the persistence feature follow `cuems-nodeconf`'s mechanics: the persisted document is rewritten only when its persisted state changes, beside a refresh cadence for live state. That cadence is event-driven with a slow reconcile, never a tight poll (Principle I). In this feature both kinds appear in the one JSON document, and nothing is written.

**Identity**

- **FR-009**: Every `port_id` MUST derive from physical attributes and never from enumeration order. The keys by class:
  - **video**: GPU PCI path plus connector name;
  - **HDMI/DP audio**: the video connector the audio rides on;
  - **USB audio**: USB vendor:product plus serial, or the physical USB port path when there is no serial;
  - **DMX**: the interface's own serial, as OLA keys its port patches (`13-<SERIAL>-O-<port>` in `/etc/ola/ola-port.conf`), plus OLA's port index. With OLA down, the device is still keyed by its USB serial (the same device key), and its ports are not enumerated (FR-019).

  DRM card numbers, ALSA card names and indices, ALSA device numbers, USB bus/device numbers and OLA's numeric device aliases MUST NOT appear in any id.
- **FR-010**: Port ids MUST be unique per node across all classes and both directions.
- **FR-010a**: A physical port MUST be addressed cluster-wide by the pair (node uuid, `port_id`), the same pair projects already use as `<node uuid>_<output id>`.
  - The twin states its node uuid once, at its top level, and the documented JSON shape (FR-028) MUST state this addressing rule explicitly.
  - A `port_id` MUST NOT be assumed unique across nodes. Two identical devices on two nodes, even on the same socket path, can share a `port_id` and are told apart by the node uuid.
  - A `port_id` MUST NOT embed the node uuid or any other node attribute, so the node is held in one place only.
- **FR-011**: Port ids MUST be stable across reboot, re-enumeration, a change of HDMI pipe assignment, and re-plugging into the same socket.
- **FR-012**: Where an id rests on a weaker key (a USB port path because there is no serial), the twin MUST say so for that device, so that a later stage can warn that moving the device to another socket changes its id.

**Presence**

- **FR-013**: Presence MUST be three-valued: `present`, `absent` or `unknown`. `unknown` MUST be used whenever the source could not tell, failed, timed out or was not consulted. `absent` MUST NOT stand in for "could not tell".
- **FR-014**: Within a single run, with no persisted previous twin, `absent` MUST mean only that the hardware enumerates the port and nothing is attached to it, for example a disconnected connector. Remembering ports that have disappeared between runs is out of scope; it belongs to the persistence feature.

**Sources, per class**

- **FR-015**: **Video** MUST come, in this order of preference, from:
  1. the videocomposer contract v1, when its socket answers;
  2. otherwise DRM sysfs;
  3. otherwise the `display.conf` the probe can find, taking only connector existence from it, with presence `unknown`.

  The report MUST name the source that answered.
- **FR-016**: The video probe MUST follow the contract's client rules: subscribe before reading; read `get_hardware` on connect only, and re-read only on `state_changed`, a `pid` change or a `seq` gap; never poll `get_hardware`; ignore unknown fields. It MUST use typed mode fields and never parse a mode `id`.
- **FR-017**: The DRM sysfs fallback MUST start from `cuems-display-setup`'s DRM/EDID reading (`cuems-common` tree, unshipped), including its handling of the sysfs EDID file that reports size 0 while returning a full payload (`5c266c3`). It is carried forward, not rewritten blind.
- **FR-018**: **Audio** MUST come from ALSA. It MUST cover every kind of audio device the host has, each with its outputs and inputs:
  - **HDMI/DP-driven audio**, attributed to its video connector;
  - **external USB DSPs and interfaces**, keyed by USB identity;
  - **multichannel cards** (PCI/PCIe), keyed by PCI path plus the card's own stable stream identity;
  - **the main L/R outputs** (onboard analog), keyed by the controller's PCI path plus the codec's stable stream identity.

  No key uses the ALSA card index or name. Making every kind selectable in the agreement, and restarting services at setup, belongs to later features (maintainer scope ruling, `specs/planning/02-hardware-classes.md` §2).
- **FR-018a**: Each audio port MUST carry a JACK exposure field (which JACK port names it appears as), as live state. **How JACK relations are determined is deferred**, pending further research and agreement with the team. Until that is agreed, the following holds:
  - the field is `unknown`, with the reason `pending JACK relations agreement`;
  - the probe makes no attempt to read the JACK graph and does not touch JACK at all. Whether a later JACK read may register a client outside a show is pending with D-11. During a show, Principle I forbids it regardless;
  - this deliberate deferral is listed in the report as deferred, and it does **not** count as a degraded source for the exit status (FR-029).

  The model MUST keep the field and its place in the shape, so that adding the method later changes no structure.
- **FR-019**: **DMX** MUST come from OLA's RPC when `olad` runs, and otherwise from USB candidates (FTDI-class serial devices) with the OLA view `unknown`. A USB candidate is a device keyed by its serial, with no ports listed. Port indices are OLA's to define, so none is invented. Network DMX nodes MUST be reported only as OLA sees them. OLA's Python client (`python3-ola`) is a declared dependency of this package whether or not any DMX device is attached. If it is missing, that is an installation defect, reported as such (`ola_client_missing_dependency`).
- **FR-020**: The DMX probe MUST guard against starting `olad` with two independent layers. Either layer alone MUST be enough to prevent a spawn.
  1. Before any OLA connection, it verifies that something is already listening on `localhost:9010`. If nothing is, it does not attempt to connect.
  2. It connects only through a client path that cannot start `olad`, so that `olad` dying between the check and the connect still spawns nothing.

  If either layer fails, the OLA view is `unknown`, DMX falls back to USB candidates, and the report and log line name the layer that triggered. Fixture-backed tests MUST prove that no `olad` is spawned, both when `:9010` is empty and when it empties between the check and the connect.

**Never disturb a show**

- **FR-021**: The probe MUST NOT become DRM master, register a JACK client (in this feature it does not touch JACK at all, FR-018a; any future rule on client registration is pending with D-11), write to OLA (no patch, no profile, no plugin change), restart or signal any service, or write any file anywhere.
- **FR-022**: The probe MUST NOT open audio devices in a way that competes with `zita-j2a` or JACK for exclusive access.
- **FR-023**: Each external source MUST have a bounded wait. An unresponsive source is reported degraded, and the probe completes.
- **FR-024**: When `/tmp/cuems.show.lock` exists at start, the probe MUST run in **show-lock mode**, restricted to cheap reads:
  - files under sysfs, procfs and `/etc` or `/run` configuration;
  - at most one read of each read-only service request: VC `hello`, `get_caps`, `get_hardware` and `get_state`, OLA's read-only device listing.

  It MUST open no device node. The report MUST state that show-lock mode was in force and list each fact left `unknown` because of it.
- **FR-025**: The feature MUST serve no API, open no listening socket, and MUST NOT answer `/tmp/hwdiscovery.ipc`. That existing chain (editor → controller engine → `/tmp/hwdiscovery.ipc`) is left untouched. Whether it is reused or retired is decided under D-5, not here.

**Output, exit status, logs**

- **FR-026**: `cuems-hw-mgr probe --json` MUST print one JSON document with two top-level parts, `twin` and `report`. The boundary between them is provenance.
  - **`twin`** (FR-001 to FR-014) holds every discovered fact, including facts from service-written files and active daemons (FR-008). It is the part that will be persisted.
  - **`report`** holds only:
    - per-run metadata: which source answered for each class, degradations and their reasons, show-lock mode;
    - findings about operator-authored inputs: legacy continuity (FR-032), the `canvas_region` hazard (FR-033), the operator `display.conf` override;
    - diagnostics computed from the twin, such as zero connectors (FR-035), which are derived and never stored (F3).

  Nothing in `report` is ever persisted as part of the twin.
- **FR-027**: The JSON MUST be deterministic: a fixed key order, devices and ports ordered by their identity keys, and stable number formatting. It MUST contain no timestamps, durations, process ids or other per-run values, so that two probes of an unchanged host produce byte-identical output.
- **FR-028**: The JSON MUST carry a format version. Its shape MUST be documented field by field, marking identity and observation fields, as the draft from which `cuems-utils` will derive the `hardware_outputs` structure.
- **FR-029**: The exit status MUST distinguish three outcomes, each with a documented value:
  - **twin built**: every source answered;
  - **twin built with degraded sources**: at least one source fell back, timed out, was unreadable, or was skipped by show-lock mode;
  - **could not run**: for example no node uuid, run as root, or an internal failure.

  On "could not run", stdout MUST carry a JSON error object with the reason, and no twin.
- **FR-030**: Every degraded path MUST have a named trigger and emit one log line on stderr naming the class, the source that failed, the reason and the fallback taken (Principle VII). JSON goes only to stdout.
- **FR-031**: The `probe` command is intended to run as `cuems`, and MUST refuse to run as root. It reads and never writes the system, so root buys nothing. Other non-root users, such as `cuems-admin` over ssh, can run it, with unreadable sources reported as degraded. The privilege model of the future service daemon, which has to restart system services at setup, is not decided here (see Assumptions).

**Continuity and diagnostics (report only)**

- **FR-032**: For every twin port that corresponds to a local-node entry in today's `default_mappings.xml`, the report MUST record that entry's class, direction, legacy `id`, legacy `name` and the compound reference `<node uuid>_<name>` that projects use. The match is by physical correspondence: the connector for video, the interface for DMX. It is never made by position. Audio legacy entries are named by JACK port (`system:playback_1`), so matching them needs the deferred JACK relations (FR-018a). Until those are agreed, audio entries are listed as unmatched, with that reason. Entries that match no port, and ports that match no entry, MUST both be listed.
- **FR-033**: `canvas_region` MUST be interpreted as the schema defines it, normalised floats in [0, 1] and a UI hint, and never as pixels. For every local video output whose `canvas_region` `cuems-generate-display-conf` would fail to parse, the report MUST carry a diagnostic. Such a value is any non-integer literal, including `0.0` and `0.5`. The diagnostic names the output and value and says that the failure aborts the VC's `ExecStartPre` when no operator `display.conf` override exists. The probe fixes nothing.
- **FR-034**: The probe MUST record which `display.conf` is in use, and MUST NOT assume which file the VC used.
  - When the VC answers, its `get_state` `config_source` is daemon-reported and goes in the twin, as live state of the video device.
  - When the VC does not answer, the report records the path the probe actually read: `/run/cuems/display.conf`, the operator override `/etc/cuems/display.conf`, or the VC's XDG fallback. It records that none was found if so.
- **FR-035**: A host with zero video connectors MUST produce a diagnostic, not only an empty list. It is narrowed to video for now. Widening it to "zero devices of a class this host model is known to have" needs per-model expectations. Those can be derived once real configurations have been retrieved from the production-testing machines (task T073), and the requirement can be re-widened then.

**Tests, fixtures, documentation**

- **FR-036**: Every probe MUST be tested against recorded fixtures, one set per supported host model: Intel N97/N100, i3-1215U and AMD Picasso FP530. The fixtures are:
  - sysfs and procfs trees;
  - VC contract replies, valid against contract v1;
  - OLA RPC responses;
  - JACK state, captured for the later JACK relations work but not consumed in this feature (FR-018a).

  Fixtures MUST be checked against `cuems-fleet`'s per-site records of the same hosts.
- **FR-037**: The feature MUST provide a read-only way to capture a fixture set from a real host, obeying FR-021 to FR-024. It runs as `cuems-admin` over ssh with no sudo, using the `dev/scripts/` procedure, and copies nothing to the host (research R15). Captured EDID serials and USB serials MUST be pseudonymised consistently, so that identity tests stay valid and no personal-ish data is committed.
- **FR-038**: Identity MUST have property-style tests that say so explicitly. They cover re-enumeration, DRM card renumbering, ALSA renumbering, HDMI pipe reassignment, USB re-plug into the same socket and OLA alias reordering.
- **FR-039**: The feature MUST keep a hardware-verification ledger recording, per host model, what was run on real hardware and what was not.
- **FR-040**: When the feature is done, `CLAUDE.md` "Field notes / gotchas" MUST be updated. Each of the four entries below is either marked resolved (and says how) or narrowed to what is still open, with a pointer to the feature that will close it:
  - **OLA rogue `olad`**: resolved for probing by FR-020; still open for any `olad` restart, which belongs to the DMX setup feature;
  - **`canvas_region` read as pixels**: now diagnosed by FR-033; the fix belongs to the video setup feature or an earlier `cuems-common` fix;
  - **VC "Phase A"**: provenance is now recorded by FR-034; who generates `display.conf` stays open for the video setup feature, to agree with the VC team;
  - **dead `hw_discovery` chain**: untouched by FR-025; decided under D-5.

  Pointers name the feature, not a feature number.

### Key Entities *(include if feature involves data)*

- **Node (`CuemsHardwareNode`)**: the twin of one host, keyed by its uuid from `settings.xml`. It owns its devices, carries a format version and no other node attribute.
- **Device**: a physical or logical hardware unit: a GPU, an audio interface, a DMX interface, and later a network or virtual one. Identity: class, `device_key` and transport. Observation: vendor, model, serial, and the identity strength (serial-based or port-path-based).
- **Port**: one addressable input or output on a device. Identity: `port_id` and direction. Observation: channels, class-specific capabilities, presence (`present` | `absent` | `unknown`), JACK exposure for audio, and source probe.
- **Sink**: what is attached to a port where it can be detected, for example a monitor identified by EDID make/model/serial. It is identified separately from the port.
- **Probe**: a per-class plug-in that observes one hardware class from an ordered list of sources and returns observations. The node iterates whichever probes are registered.
- **Report**: the companion of the twin in the JSON output. It is never persisted and never feeds back into the twin. It contains:
  - per-run metadata: the source that answered for each class, the degradations with their reasons, and the show-lock mode;
  - findings about operator-authored inputs: legacy continuity from `default_mappings.xml`, the `canvas_region` hazard, the operator `display.conf` override or the fallback path read;
  - diagnostics computed from the twin, such as zero connectors.
- **Persisted state / live state**: the two kinds every observed twin field belongs to (FR-008a). Persisted state is rewritten only on change; live state is refreshed on events and a slow reconcile.
- **Legacy continuity record**: for one port, or one unmatched mappings entry: class, direction, legacy id, legacy name, and the compound reference `<node uuid>_<name>`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On every supported host model (N97/N100, i3-1215U, FP530), the probe lists every video connector, audio device and DMX interface that the host's `cuems-fleet` record lists, with none missing and none invented. This is verified against the fixtures in CI and recorded on real hardware in the ledger.
- **SC-002**: 100% of port ids are unchanged across every re-enumeration, renumbering and re-plug permutation in the identity test suite.
- **SC-003**: Two consecutive probes of an unchanged host or fixture produce byte-identical output in 100% of runs.
- **SC-004**: Zero `olad` processes are spawned, zero JACK clients registered, zero DRM master acquisitions and zero files written across the whole test suite, including the run with `:9010` empty.
- **SC-005**: Every source failure in the degraded-mode suite produces a fallback, a report entry, one log line and the "degraded" exit status. No port anywhere in that suite reports `absent` for a source that could not tell.
- **SC-006**: A probe completes in under 5 seconds on a supported host with all sources up. No single unresponsive source can stretch a probe beyond 10 seconds.
- **SC-007**: Run on a live show on an N97 node, the probe causes no presentation hitch and no JACK xrun, as recorded in the hardware-verification ledger. If that has not been verified, the ledger says so.
- **SC-008**: For every video and DMX port matching a local `default_mappings.xml` entry on the fixture hosts, the report gives the legacy compound reference. Every audio entry is listed as unmatched, pending JACK relations. The migration decision (finding 6) can then be made from probe output alone, without hand inspection.
- **SC-009**: Adding a test-only hardware class to the suite requires adding a probe and nothing else. The twin, the identity resolver and the serialiser are unchanged.
- **SC-010**: `cuems-fleet` `census` can record a node's hardware from the probe's JSON alone, replacing the hand-typed `hardware:` / `outputs:` entries for that node.

## Assumptions

- **Out of scope here**: writing `hardware_outputs.xml`; remembering absent ports across runs; revision; retention (D-6). All of these belong to the persistence feature, gated on `cuems-utils`' structure pass and accessor. Serving the twin, the node API and any socket are out of scope too. So are projectors and network displays, NDI and `cuems-dmx2net`'s virtual universes: the model leaves room for them through the `network` and `virtual` transports, and they are not probed here. Fixing `canvas_region`, generating `display.conf` and any OLA reconfiguration are also out of scope.
- **Legacy ids are not the twin's ids.** Today's `default_mappings.xml` numbers ids per direction from 0, so an input and an output share `0`. That breaks the cross-direction uniqueness required by Principle III and FR-010. The twin's ids therefore cannot reproduce today's verbatim, and continuity goes through the report's legacy records (FR-032). The migration itself is decided later, with this feature's output as its evidence. On top of that, today's project references use the legacy *name* (`<uuid>_system:playback_1`, `<uuid>_0`), not the numeric id.
- **JACK relations are deferred** (maintainer, 2026-10-22): they need further research and agreement with the team. Two points are pending in D-11. One is the `jack_lsp`-style one-shot it used to recommend (`jack_lsp` itself registers a short-lived JACK client). The other is whether any JACK client may be registered outside a show at all. The candidates to research include:
  - inference without joining the graph, from the JACK server's and the bridges' configuration and running arguments and the `multi_hdmi` layout;
  - a client-based read allowed outside a show;
  - taking the JACK view from the engine.

  This feature ships the field, reports it `unknown`, and does not touch JACK (FR-018a). Audio legacy continuity (FR-032) waits on the same agreement.
- **`display.conf` is authored intent.** As a last-resort video source, only connector names are taken from it, with presence `unknown`. Its geometry never enters the twin (Principle II's worked example). Only the VC's own report of what it drives enters the twin, and only as live state (FR-008b).
- **Open items for later features.** These are recorded here and not decided:
  - **Geometry changed directly on the VC** (OSC today, VC edit mode later) appears as live drift. Whether the agreement offers to adopt the running geometry is for the agreement and video setup features.
  - **Existing hand-made `/etc/cuems/display.conf` files** need a one-time import into the agreement when the video setup feature lands.
- **Upstream divergence to raise, not to fix here.** The current `hardware_outputs.xsd` annotation still names two writers: `cuems-hardware-discovery` for the inventory and `cuems-nodeconf` for transcribed geometry. That contradicts the settled sole-writer decision and Principle II. This feature writes no file, so it is not blocked. The divergence goes into the `specs/upstream-reports/` request that accompanies the structure pass, built from FR-028's documented shape.
- **The VC contract v1 is not deployed** (maintainer, 2026-10-23). Every deployed VC predates it; v1 is planned development. The contract source is built and tested against the VC's mock. On today's fleet, video always comes from DRM sysfs, which is the designed fallback, so a full-sources exit `0` is only reachable on a host with a v1 VC. Field verification of the contract path, and of the VC socket's permissions for `cuems-admin`, is deferred until a machine runs one.
- **Fixtures need host access.** At least one capture per supported host model has to be taken on real hardware with FR-037's capture path before the per-model tests are complete. The existing `cuems-fleet` records are the cross-check, not a substitute.
- **Privilege of the future services (D-14, constitution 1.1.0, 2026-10-23).** The daemons run as `cuems`. Restarting system services and writing root-owned configuration at setup happen in root oneshot apply units, which the daemon starts through a sudoers rule naming the exact units. This feature ships neither. Its CLI keeps refusing root (FR-031). `cuems-admin` (key-based ssh, no sudo) is the account for read-only inspection of production-testing machines.
- **Where persisted files go.** Persisted files are expected under `/etc/cuems/`, following the ecosystem's practice, or as `settings.xml` equivalents. The VC's XDG fallback `display.conf` path is read only as a last resort, under the home of the user the VC unit runs as (re-measured in T001).
- **`cuems-fleet` integration** (SC-010) is consumer-side. The request is `specs/upstream-reports/cuems-fleet-census-probe-json.md`.
- **Human-readable output.** Running `probe` without `--json` may print a human summary. Only the JSON is a contract.
- **Questions for `/speckit-clarify`.** `specs/planning/00-runnable-flow.md` §4 lists four. This spec takes a working default for each:
  1. **A DMX interface with no serial.** Resolved in Clarifications: key on the USB port path, flagged as weak identity (FR-012), and addressed cluster-wide by (node uuid, `port_id`) (FR-010a).
  2. **Identity versus observation.** Resolved in Clarifications: a structural `identity` / `observed` split (FR-006).
  3. **How the DMX probe avoids auto-starting `olad`.** Resolved in Clarifications: two independent layers (FR-020).
  4. **Where diagnostics live.** Resolved in Clarifications: the twin/report boundary is provenance (FR-008, FR-008a, FR-026).

  Clarify confirms or overturns each one.
