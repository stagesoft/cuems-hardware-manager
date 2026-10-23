---

description: "Task list for the node digital twin from discovery"
---

<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Tasks: Node digital twin from discovery

**Input**: Design documents from `specs/001-node-twin-discovery/`.

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md.

**Tests**: REQUIRED. The spec and the constitution both demand them:
- FR-036 to FR-038, and SC-001 to SC-005 and SC-009, are test-backed;
- the constitution requires test-first for parsing and identity code;
- the suite MUST pass before any merge.

Tests in each story are written first and MUST fail before the implementation they cover.

**Conventions.** Every new source file:
- starts with SPDX headers (`SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL`, `SPDX-License-Identifier: GPL-3.0-or-later`);
- names a document or a behaviour in its comments, never a feature number;
- reads the host only through `HostView`, using host-absolute paths.

Research and plan sections are cited as R1–R19 and §n of `data-model.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US5, the user stories in spec.md

---

## Phase 1: Setup and re-measurement

**Purpose**: Package skeleton, plus the three re-measurements the plan requires before any code relies on them.

- [ ] T001 Re-measure the VC contract. Diff the scratch copy used in research against `cuems-videocomposer` `feat/contract-report` `docs/contract-v1.md`, and copy the VC mock's replies from `tools/contract/` as the reference. Also record the VC unit's `User=`, which fixes the home directory for the XDG `display.conf` fallback. Record the result in `specs/001-node-twin-discovery/research.md` under R3 ("Re-measured"); a mismatch amends R3 before T030.
- [ ] T002 [P] Re-measure whether `cuemsutils` `ConfigManager(config_dir, load_all=False)` exposes `node_uuid`, `show_lock_file` and `node_mappings`, and whether `node_mappings` resolves `default_mappings.xml` with no project loaded. Measure in `../cuems-utils` `src/cuemsutils/tools/ConfigManager.py` and `ConfigBase.py`. Record the answer under R2 in `specs/001-node-twin-discovery/research.md`. If there is no public path, draft `specs/upstream-reports/cuems-utils-default-mappings-public-path.md` (never a private read).
- [ ] T003 [P] Re-measure OLA. Read the CUEMS OLA fork's `python/ola/OlaClient.py` and confirm it has no spawn or auto-start path. Record under R10 in `specs/001-node-twin-discovery/research.md`. Where `python3-ola` installs, and that the shared venv imports it, are already measured (research, "Field measurements"), so only the spawn-path read is left.
- [x] T004 Remove the outdated prototype (the 296-line pickle-over-TCP `CuemsHwDiscovery`, which imports the deleted `XmlReaderWriter` and `cuems_nodeconf.CuemsNode` and cannot run on the `feat/xml-refactor` line) from `src/cuemshardwaremanager/CuemsHwDiscovery.py`. The planning docs called it an empty placeholder, but it was never empty; this feature's design on the siblings' `feat/xml-refactor` interfaces replaces it. It stays in history at `b09b8cc` and `82efbd9`.
- [ ] T005 Create `pyproject.toml`, and add a "Requirements" section to `README.md` declaring the system dependency `python3-ola`, which is required whether or not DMX hardware is present (R10; it carries over to the Debian `Depends:` when packaging lands):
  - setuptools, `src/` layout, `requires-python = ">=3.11"`;
  - dependencies `cuemsutils` and `pynng`, declared and never vendored;
  - optional `test = ["pytest", "jsonschema"]`;
  - console script `cuems-hw-mgr = "cuemshardwaremanager.cli:main"`;
  - SPDX licence `GPL-3.0-or-later`.
- [ ] T006 [P] Create the package skeleton with SPDX headers: `src/cuemshardwaremanager/__init__.py`, `src/cuemshardwaremanager/__main__.py` (calls `cli.main()`), and the empty packages `src/cuemshardwaremanager/sources/__init__.py`, `src/cuemshardwaremanager/probes/__init__.py` and `src/cuemshardwaremanager/report/__init__.py`.
- [ ] T007 [P] Create the test layout: `tests/conftest.py` (empty for now), and the directories `tests/unit/`, `tests/identity/`, `tests/contract/`, `tests/safety/`, `tests/degraded/`, `tests/report/`, `tests/fixtures/constructed/`, and `tests/fixtures/README.md`. The README documents the fixture layout (`root/{sys,proc,etc,run,tmp}`, `services/{vc,ola}/*.json`, `MANIFEST`, `expected.json`; contracts/cli.md "capture") and the rule that constructed fixtures are not recorded ones.

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: The model, identity grammar, serialiser, host view, probe registry, node runner and safety harness that every story uses.

**⚠️ CRITICAL**: No user story starts until this phase is done.

### Tests first

- [ ] T008 [P] Unit tests for the `port_id` grammar in `tests/unit/test_identity.py`. Cover every `device_key` form of data-model §6 and every `local` form, and check the examples verbatim, for instance `video:output:pci-0000:00:02.0:HDMI-A-1` and `dmx:output:serial-PSEUDO-9be01c44aa:port1`. Reject keys containing a DRM minor (`card0`), an ALSA card index or name, a USB bus or device number, or an OLA alias. Assert that `key_strength` `port_path` and `service_name` are classified weak.
- [ ] T009 [P] Unit tests for deterministic serialisation in `tests/unit/test_serialise.py`:
  - `sort_keys=True`, `indent=2`, `ensure_ascii=False`, trailing newline;
  - devices sorted by `(class, device_key)`, ports by `port_id`, modes by `(width, height, hz, interlaced)` descending;
  - floats rounded to 3 places;
  - no timestamps or pids allowed in the model (R13);
  - two serialisations of equal models are byte-identical.
- [ ] T010 [P] Unit tests for `HostView` in `tests/unit/test_hostview.py`. Rooted reads (`read_text`, `read_bytes`, `listdir`, `exists`, `realpath` resolving relative symlinks inside the root); a path escaping the root is refused; `show_lock` re-checks the lock path each time; `euid` is injectable.
- [ ] T011 [P] Unit tests for the node runner in `tests/unit/test_node.py`:
  - probes run in topological order of `requires`, ties by `cls`;
  - a cycle is an internal error;
  - a duplicate `port_id` across probes is an internal error ("could not run"), never a merge (data-model §8);
  - a probe exception makes the run "could not run";
  - `register()` adds a test-only class.

### Implementation

- [ ] T012 [P] Implement the model types in `src/cuemshardwaremanager/model.py`: `Device`, `Port`, `Sink`, each with an `identity` object and an `observed` object, no field in both (FR-006); `Report`; `ProbeResult`.
  - Enums verbatim from data-model: transport `pci` · `usb` · `network` · `virtual`; key_strength `serial` · `port_path` · `bus_address` · `service_name`; presence `present` · `absent` · `unknown`; direction `output` · `input`.
  - Validation: "Every `presence: unknown` carries `presence_reason`."
  - The audio `jack_exposure` default is `{"state": "unknown", "reason": "pending JACK relations agreement"}`.
- [ ] T013 [P] Implement the physical-key helpers and `port_id` builder in `src/cuemshardwaremanager/identity.py`, following the data-model §6 grammar. These helpers are the only way probes build ids (contracts/probe-plugin.md rule 5). Make T008 pass.
- [ ] T014 [P] Implement the deterministic JSON in `src/cuemshardwaremanager/serialise.py`: `"format": "cuems-hw-twin/1"`, the `{format, twin, report}` and `{format, error}` documents (R13). Make T009 pass.
- [ ] T015 [P] Implement `HostView` in `src/cuemshardwaremanager/hostview.py`:
  - a rooted filesystem reader;
  - `port_listening(host, port, timeout)`, a TCP connect closed with no bytes sent;
  - `show_lock`;
  - `euid`;
  - slots for the `vc` client and the `ola` client factory.
  - Provide `HostView.live()` (root `/`) and `HostView.from_fixture(path)`, with recorded VC and OLA clients replaying `services/*.json`. Make T010 pass.
- [ ] T016 Implement the probe protocol, discovery and registry in `src/cuemshardwaremanager/probes/__init__.py`. Use `pkgutil.iter_modules` in sorted order, collect each module's `PROBE`, and add `register(probe)` for tests (R12). Follow contracts/probe-plugin.md. No class names appear in this file.
- [ ] T017 Implement `CuemsHardwareNode` in `src/cuemshardwaremanager/node.py`:
  - read the uuid through `cuemsutils` `ConfigManager(load_all=False).node_uuid` (FR-002, R2);
  - the published "unprovisioned" sentinel uuid → could not run, `node not provisioned`;
  - run the probes in dependency order with a read-only `ProbeContext`;
  - enforce `port_id` uniqueness across all probes;
  - collect the report;
  - return the twin and the report.
  - Make T011 pass.
- [ ] T018 Implement the safety harness in `tests/conftest.py`. An autouse fixture patches `subprocess.*`, `os.exec*`, `os.fork`, `os.posix_spawn*`, `socket.socket.bind`, any `open`/`os.open` of a path under `/dev/`, and any write-mode open, so that each fails the test (contracts/probe-plugin.md rule 3). It also gives fixtures access to `HostView.from_fixture`.
- [ ] T019 [P] Write the EDID decoder tests in `tests/unit/test_edid.py`:
  - `make` is the PNP id from bytes 8–9 (e.g. `GSM`);
  - `model` is the 0xFC descriptor;
  - `serial` is the 0xFF descriptor, else the 32-bit serial when nonzero, else `""`;
  - a bad header or checksum gives `{"state": "unknown"}`;
  - empty bytes from a size-0 sysfs file mean "no EDID" (`5c266c3`).
- [ ] T020 [P] Implement the EDID decoder in `src/cuemshardwaremanager/sources/edid.py` (R6). Make T019 pass.

**Checkpoint**: the foundation is ready; user stories can begin.

---

## Phase 3: User Story 1 — See the whole node, under stable names (Priority: P1) 🎯 MVP

**Goal**: `cuems-hw-mgr probe --json` on a host with every source up prints the node uuid and every video, audio (all four kinds) and DMX device and port under physical ids, and says which source answered.

**Independent Test**: For each constructed fixture with every source up, the probe output equals `expected.json` byte for byte. Two runs are identical, and the output validates against `contracts/probe-output.schema.json`.

### Tests for User Story 1 (write first, must fail)

- [ ] T021 [P] [US1] Build the constructed fixture `tests/fixtures/constructed/intel-allsources/`, modelled on an N97:
  - one i915 GPU at `pci-0000:00:02.0`, connectors `HDMI-A-1` (connected, EDID), `HDMI-A-2` (connected, EDID) and `HDMI-A-3` (disconnected);
  - VC replies (`hello`, `get_caps`, `get_hardware`, `get_state`) taken from T001's reference;
  - ALSA: the `PCH` card with an analog `pcm0p` (main L/R), three HDMI PCMs with ELDs for the two connected monitors, and a USB DSP card with `stream0` and a serial;
  - `/etc/asound.conf` with a `multi_hdmi` definition as `cuems-hdmi-audio-map` writes it;
  - OLA replies with one Eurolite MK2, `usbdmx-<PSEUDO serial>`, one output port;
  - `/etc/cuems/settings.xml` with a provisioned uuid;
  - `expected.json`.
- [ ] T022 [P] [US1] Build the constructed fixture `tests/fixtures/constructed/amd-allsources/`, modelled on an FP530: an amdgpu GPU, a `Generic` HDMI HDA card on the GPU's audio function, an onboard analog card, a PCI multichannel card (`pcm0p` and `pcm0c`, 8 channels), VC replies, OLA replies, and `expected.json`.
- [ ] T023 [P] [US1] Contract test in `tests/contract/test_output_schema.py`: the probe output for every fixture under `tests/fixtures/**/` validates against `specs/001-node-twin-discovery/contracts/probe-output.schema.json`.
- [ ] T024 [P] [US1] Contract test in `tests/contract/test_vc_replies.py`: every `services/vc/*.json` in the fixtures matches the shapes of contract v1 (T001); unknown extra fields are tolerated.
- [ ] T025 [P] [US1] Golden tests in `tests/test_probe_golden.py`. For each fixture, `probe --json` equals `expected.json` byte for byte; two consecutive runs are identical (SC-003); `twin` contains `uuid` and `devices` only (FR-002).
- [ ] T026 [P] [US1] Unit tests for the DRM sysfs reader in `tests/unit/test_drm_sysfs.py`:
  - GPU key from `realpath(sys/class/drm/cardN/device)` → `pci-<BDF>`, plus vendor, device and driver;
  - connectors from `cardN-<CONNECTOR>` directories;
  - `status` → present / absent / unknown;
  - modes de-duplicated from the `modes` file;
  - EDID read unconditionally (R4, R5).
- [ ] T027 [P] [US1] Unit tests for the ALSA reader in `tests/unit/test_alsa_procfs.py`:
  - cards, `pcmDD{p,c}/info`, `stream0` channels, `hw_params` as live state;
  - the physical device via `/sys/class/sound/cardN/device`;
  - kind classification `hdmi` · `usb` · `onboard` · `pci_multichannel` (R7);
  - `/etc/asound.conf` `multi_hdmi` slots parsed into `live.multi_hdmi_slot`; an absent file gives `not_configured` and is not degradation; an unreadable or garbled file gives `asound_conf_unreadable`;
  - 36 `eld#2.N` files with only some valid, and four HDMI PCMs (3, 7, 8, 9), as measured on the production-testing hosts (research, "Field measurements"). The mapping goes through `codec#C`, with no device table;
  - neither the ALSA card index nor the card name appears in any key.
- [ ] T028 [P] [US1] Unit tests for HDMI attribution in `tests/unit/test_hdmi_audio.py`. ELD (`monitor_present 1`, `eld_valid 1`) is matched to the connector's sink EDID by manufacturer plus product, and gives `live.alsa_pcm` and `max_channels` from the SADs. Two identical sinks give `alsa_pcm` `unknown` plus `sink_ambiguous`. Presence follows R8.
- [ ] T029 [P] [US1] Unit tests for the OLA reader in `tests/unit/test_ola_rpc.py`, using recorded replies: the device key `serial-<SERIAL>` comes from the unique id `<plugin>-<SERIAL>`; port ids use OLA's port index; network devices with no serial are keyed `ola-<UID>`, weak; the numeric alias is never used (R9).

### Implementation for User Story 1

- [ ] T030 [P] [US1] Implement the VC client in `src/cuemshardwaremanager/sources/vc_contract.py` (R3), following the contract's client rules. No deployed VC serves contract v1 yet (research, "Field measurements"), so this is built and tested against the VC's mock only:
  - `pynng` `Sub0` on `ipc:///tmp/cuems-videocomposer-events.ipc`, subscribed first;
  - `Req0` on `ipc:///tmp/cuems-videocomposer.ipc` with 1 s timeouts;
  - `hello`, `get_caps`, `get_hardware`, `get_state`;
  - a non-blocking drain of ≤ 100 ms;
  - one re-read on `state_changed`, a `pid` change or a `seq` gap;
  - unknown fields ignored;
  - mode `id`s treated as opaque.
  - Add a recorded-reply implementation for `HostView.from_fixture`.
- [ ] T031 [P] [US1] Implement `src/cuemshardwaremanager/sources/drm_sysfs.py`, ported from `cuems-common` `usr/lib/cuems/bin/cuems-display-setup` (`probe_connected_outputs`, `_read_modes`, `_read_edid_name`). Keep the `5c266c3` unconditional EDID read. Enumerate all connectors rather than only connected ones, and decode EDID with `sources/edid.py` (R5). Credit the origin in the module docstring. Make T026 pass.
- [ ] T032 [P] [US1] Implement `src/cuemshardwaremanager/sources/usb_sysfs.py`: USB device identity (`idVendor`, `idProduct`, `serial`, `devpath`) for a sysfs node or its ancestor interface (R7, R9).
- [ ] T033 [P] [US1] Implement `src/cuemshardwaremanager/sources/alsa_procfs.py` (R7, R8): cards, PCM info, `stream0`, `hw_params`, ELD files `eld#C.P`, the codec pin → device map from `codec#C`, the physical device path, and the `multi_hdmi` slot layout parsed from `/etc/asound.conf` as live state (R7; an unreadable file gives `asound_conf_unreadable`). It opens no device node. Make T027 pass.
- [ ] T034 [P] [US1] Implement `src/cuemshardwaremanager/sources/ola_rpc.py`:
  - layer 1: `HostView.port_listening("127.0.0.1", 9010, 0.2)` before any client is constructed;
  - layer 2: `ola.OlaClient`, imported lazily, with read-only `FetchPlugins`, `FetchDevices` and `FetchUniverses` only;
  - no `ola_*` binary is ever executed (R10);
  - an import failure returns `ola_client_missing_dependency` (an installation defect, logged as such; R10).
  - Add a recorded-reply implementation. Make T029 pass.
- [ ] T035 [US1] Implement the video probe in `src/cuemshardwaremanager/probes/video.py` (`PROBE`, `cls = "video"`, `requires = ()`):
  - VC contract first, joined to DRM sysfs by connector name for the GPU PCI key (R4);
  - `observed.capabilities.vc_caps` from `get_caps` (persisted);
  - modes, `preferred` and `sink` (persisted);
  - `live.current`, `live.config_source` and `live.driven_geometry` (live only, FR-008b);
  - `report.sources["video"] = "vc_contract_v1"`.
- [ ] T036 [US1] Implement the audio probe in `src/cuemshardwaremanager/probes/audio.py` (`cls = "audio"`, `requires = ("video",)`):
  - all four kinds per R7;
  - HDMI/DP audio ports created per audio-capable video connector and keyed on the GPU PCI path plus connector, with `live.alsa_pcm` from ELD matching (R8) and `live.multi_hdmi_slot` (R7). They sit on an **audio-class device that this probe emits** (`device_key = pci-<GPU BDF>`), never on the video probe's device (data-model §6, contracts/probe-plugin.md);
  - USB by USB identity, PCI analog by PCI path plus `pcmN`;
  - inputs and outputs as separate ports;
  - `jack_exposure` always the deferred value, with a `report.deferred` entry and no JACK access (FR-018a).
- [ ] T037 [US1] Implement the DMX probe in `src/cuemshardwaremanager/probes/dmx.py` (`cls = "dmx"`, `requires = ()`): from OLA when both layers pass, with device key `serial-<SERIAL>` and ports `port<N>` (R9). Put OLA's current universe ↔ port patch (`FetchUniverses`) in `observed.live.ola_patch` as live state only, never persisted (FR-008). Set `report.sources["dmx"] = "ola_rpc"`.
- [ ] T038 [US1] Implement `src/cuemshardwaremanager/cli.py`:
  - argparse `probe [--json] [--fixture <dir>]` and `fixture-import <model> [--out <dir>]`; `fixture-import` is wired to T071;
  - `--fixture` runs the probe on `HostView.from_fixture(<dir>)` instead of `/`, for ledger checks on captured hosts (quickstart §2). It is a development option, like `fixture-import` (contracts/cli.md);
  - build `HostView.live()`, run `CuemsHardwareNode`, print the JSON on stdout;
  - exit codes `0` / `3` / `1` / `2` per contracts/cli.md;
  - a human summary without `--json`;
  - stderr logging format `WARNING degraded class=<c> source=<s> reason=<r> fallback=<f>` (R14).
- [ ] T039 [US1] Produce and hand-review `expected.json` for T021 and T022 from the implementation. Then make T023, T024 and T025 pass.

**Checkpoint**: US1 runs end to end on constructed fixtures. This is the MVP.

---

## Phase 4: User Story 2 — Ids that do not move (Priority: P1)

**Goal**: Port ids are proven stable across reboot, re-enumeration, HDMI pipe reassignment, re-plug and OLA alias reordering, and are unique per node, with cluster addressing by (uuid, port_id).

**Independent Test**: The identity property suite passes on every fixture, and it states each property explicitly.

### Tests for User Story 2 (write first, must fail where behaviour is missing)

- [ ] T040 [P] [US2] Write fixture-mutation helpers in `tests/identity/mutate.py`:
  - swap DRM minors (`card0` ↔ `card1`);
  - renumber ALSA cards;
  - move HDMI ELD/PCM devices 3 ↔ 7 ↔ 8;
  - change the USB bus or device number while keeping `devpath`;
  - move a USB device to another `devpath`;
  - reorder OLA aliases.
  - Each returns a new temporary fixture tree.
- [ ] T041 [P] [US2] Property tests in `tests/identity/test_stability.py`, one test per property, each named for it (FR-011, SC-002): for every fixture and every mutation in T040 except "another socket", the set of `port_id`s is unchanged.
- [ ] T042 [P] [US2] Test in `tests/identity/test_uniqueness.py`: no two ports on a node share a `port_id` across classes and directions, inputs included (FR-010).
- [ ] T043 [P] [US2] Test in `tests/identity/test_eurolite_pair.py`: two Eurolite MK2s with identical descriptors and different serials get distinct serial-derived ids, unchanged when they swap sockets (US2 scenario 5).
- [ ] T044 [P] [US2] Test in `tests/identity/test_cross_node.py`, with constructed fixtures `tests/fixtures/constructed/node-a-serialless-dmx/` and `node-b-serialless-dmx/`. Two uuids each have an identical serial-less DMX interface on the same `devpath`, with OLA down. Both devices are flagged `weak_identity`; the `port_id`s may be equal; the pairs `(twin.uuid, port_id)` differ; no `port_id` embeds a uuid (FR-010a, US2 scenario 6).
- [ ] T045 [P] [US2] Test in `tests/identity/test_weak_identity.py`: a serial-less USB device gets `key_strength: port_path`, and moving it to another socket changes its id and is reported as `weak_identity` (FR-012).
- [ ] T046 [P] [US2] Build the constructed fixture `tests/fixtures/constructed/two-gpu-same-connector/` (two DRM cards on different PCI functions, both exposing `HDMI-A-1`, with the VC answering) and write `tests/identity/test_two_gpu.py`. The sysfs ports get distinct ids through the GPU PCI key. A VC connector that can't be joined to one card is reported `identity_unresolved` with the reason, and is never guessed (R4, spec Edge Cases "Two GPUs").

### Implementation for User Story 2

- [ ] T047 [US2] Implement `weak_identity` and `identity_unresolved` diagnostics in `src/cuemshardwaremanager/report/diagnostics.py`. A device with `key_strength` in `{port_path, service_name}` gets `weak_identity`. A VC connector name present on more than one DRM card gets `identity_unresolved`, with the reason (R4). Fix any id defect the tests T041 to T046 expose in `src/cuemshardwaremanager/identity.py` or the probes.

**Checkpoint**: Identity is proven, and later stages can rely on the ids.

---

## Phase 5: User Story 3 — Safe beside a live show (Priority: P1)

**Goal**: The probe never disturbs a show. There is no DRM master, JACK, OLA writes, device opens, subprocesses or writes; no `olad` is ever spawned; and show-lock mode restricts work and is reported.

**Independent Test**: The safety suite passes with the forbidden-act harness active, including both `olad` race cases.

### Tests for User Story 3 (write first)

- [ ] T048 [P] [US3] Test in `tests/safety/test_no_olad_spawn.py`, with `subprocess` and `os.exec*` patched to fail. (a) `:9010` is not listening: no OLA client is constructed, the OLA view is `unknown` (`ola_not_listening`), and the fallback is USB candidates. (b) The port check says listening but the client connect fails, as if `olad` died between the two: nothing is spawned and the reason names layer 2 (FR-020, SC-004).
- [ ] T049 [P] [US3] Test in `tests/safety/test_forbidden_acts.py`: a full probe on every fixture, with the T018 harness strict, completes without any `/dev/` open, subprocess, fork, bind or write. Assert that `jackd`-related paths are never read during probing (FR-018a, FR-021).
- [ ] T050 [P] [US3] Test in `tests/safety/test_show_lock.py`, with the fixture's `/tmp/cuems.show.lock` (or the `show_lock_file` from `settings.xml`) present:
  - `report.show_lock.active` is `true`;
  - VC and OLA requests are issued at most once each;
  - a VC `state_changed` during the drain causes no re-read, and the skip is listed in `report.show_lock.skipped`;
  - a lock that appears mid-run is honoured for the remaining requests (FR-024, R11).
- [ ] T051 [P] [US3] Test in `tests/safety/test_vc_no_poll.py`: within one run, `get_hardware` is sent at most twice (the initial read and one re-read after a gap), never in a loop (FR-016).

### Implementation for User Story 3

- [ ] T052 [US3] Implement show-lock mode:
  - in `src/cuemshardwaremanager/hostview.py`, read the lock path from `ConfigManager.show_lock_file`;
  - in `src/cuemshardwaremanager/sources/vc_contract.py`, re-check before each request and suppress re-reads under the lock;
  - in `src/cuemshardwaremanager/node.py`, record `report.show_lock` with `active` and `skipped`.
- [ ] T053 [US3] Harden `src/cuemshardwaremanager/sources/ola_rpc.py` for T048: both layers are independent, each one alone prevents a spawn, and the reason names the layer that triggered.

**Checkpoint**: Safe to run on live venues, as far as CI can prove it. The host proof is in the ledger.

---

## Phase 6: User Story 4 — Degraded is reported, never hidden (Priority: P2)

**Goal**: With the VC, OLA or a readable source missing, the probe still builds the twin from fallbacks, reports why, logs one line per degradation, and exits `3`. It exits `1` when it cannot run.

**Independent Test**: Each source is removed in turn; check the fallback, the report entry, the log line, the presence values and the exit code.

### Tests for User Story 4 (write first)

- [ ] T054 [P] [US4] Tests in `tests/degraded/test_video_fallbacks.py`. (a) With no VC socket, video comes from `drm_sysfs`; modes carry `id: null`, `hz: null` and `modes_partial`; there is one degradation and the exit is `3`. (b) With no VC and no DRM connectors, connector names come from `display.conf` with presence `unknown`, `report.display_conf.path_read` holds the exact path, and there is a `zero_video_connectors` diagnostic (FR-015, FR-035). (c) VC `connection: unknown` gives presence `unknown`, never `absent`.
- [ ] T055 [P] [US4] Tests in `tests/degraded/test_dmx_fallback.py`: with OLA down, USB candidates are keyed `serial-<SERIAL>`, the same device key as with OLA up; `ports: []` and `ports_known: false`; no invented port id.
- [ ] T056 [P] [US4] Tests in `tests/degraded/test_permissions_and_exit.py`:
  - an unreadable source → presence `unknown` with `presence_reason: permission`, and the exit is `3`;
  - every source up → `0`;
  - JACK deferral alone → still `0`;
  - root → `1` with `refuses to run as root`;
  - a missing `settings.xml` or the unprovisioned sentinel → `1`, with `{format, error}` on stdout and no twin.
  - Every degradation produces exactly one stderr line in the R14 format (FR-029 to FR-031, SC-005).
- [ ] T057 [P] [US4] Test in `tests/degraded/test_vc_unstable.py`. The recorded VC replies change `pid` after `hello`, then change again after the single re-read. Video is reported degraded with diagnostic `vc_state_unstable`, `get_hardware` is sent at most twice, and the exit is `3` (spec Edge Cases, R3).

### Implementation for User Story 4

- [ ] T058 [US4] Add the source fallbacks to `src/cuemshardwaremanager/probes/video.py`: VC → `drm_sysfs` → `display.conf`. The `display.conf` search order is `/run/cuems/display.conf`, `/etc/cuems/display.conf`, then the VC's XDG fallback `<home of the VC unit's User= (T001)>/.config/cuems-videocomposer/display.conf`. Persisted CUEMS files are expected under `/etc/cuems/`, so the XDG path is a last resort only. Take connector names only, never geometry (FR-008). Write the path read, or `null`, to `report.display_conf`.
- [ ] T059 [US4] Add the USB-candidate fallback to `src/cuemshardwaremanager/probes/dmx.py`. Recognise candidates from a vendor:product table kept as data in the module (FTDI `0403:6001`, `0403:6015`, the DMXking/ENTTEC ids, Eurolite `04d8:fa63`), plus drivers `ftdi_sio` and `usbserial` (R9). Set `report.sources["dmx"] = "usb_sysfs"`.
- [ ] T060 [US4] Implement the degradation plumbing in `src/cuemshardwaremanager/node.py` and `src/cuemshardwaremanager/cli.py`: `report.degraded` entries `{class, source, reason, fallback}`, one stderr line each; exit `3` exactly when `report.degraded` is non-empty; the root refusal checked before anything is read (R19); the could-not-run document.
- [ ] T061 [US4] Implement the `zero_video_connectors` diagnostic in `src/cuemshardwaremanager/report/diagnostics.py` (FR-035, narrowed to video). Re-widening to per-class expectations waits on the real configurations retrieved in T073.

**Checkpoint**: Degraded hosts produce honest twins.

---

## Phase 7: User Story 5 — Continuity and hazards for the next stages (Priority: P2)

**Goal**: The report gives each port's legacy `default_mappings.xml` identity, flags `canvas_region` values that break `cuems-generate-display-conf`, and records which `display.conf` is in use. None of it enters the twin.

**Independent Test**: Fixtures with a `default_mappings.xml` containing audio, video, DMX, a "custom" template output, an entry with no hardware, and fractional `canvas_region` values give the expected `report.continuity` and diagnostics. Mutating authored files leaves `twin` byte-identical.

### Tests for User Story 5 (write first)

- [ ] T062 [P] [US5] Add `etc/cuems/default_mappings.xml` to `tests/fixtures/constructed/intel-allsources/`. It is schema-valid and shaped like `cuems-editor` `specs/001-cuems-utils-migration/evidence/mappings-capture/default_mappings.xml`, with:
  - audio `system:playback_1/2` and `system:capture_1/2`;
  - video outputs with `mapped_to` `HDMI-A-1` and `salida_002`;
  - a `custom` output with `canvas_region` `0.0/0.0/1.0/1.0`;
  - one with `0.5`;
  - a DMX output;
  - a second node's entries.
- [ ] T063 [P] [US5] Tests in `tests/report/test_continuity.py`:
  - video matched by `mapped_to` == connector; DMX matched by interface;
  - every audio entry is in `unmatched_entries` with `pending JACK relations agreement`;
  - `custom` and `salida_002` are unmatched entries; never matched by position;
  - ports with no entry are listed in `unmatched_ports`;
  - `legacy_reference` is `"<uuid>_<legacy_name>"`;
  - other nodes' entries are ignored;
  - an absent `default_mappings.xml` gives `available: false` with a reason, and is not degradation;
  - a schema-invalid file gives `mappings_invalid` (FR-032).
- [ ] T064 [P] [US5] Tests in `tests/report/test_canvas_hazard.py`: `0.0`, `0.5` and `1.0` are flagged `canvas_region_generator_hazard`; `0` and `1` are not. The detail states that `cuems-generate-display-conf` raises in the VC's `ExecStartPre` only when no `/etc/cuems/display.conf` override exists, and nothing is modified (FR-033, R16).
- [ ] T065 [P] [US5] Tests in `tests/report/test_display_conf_provenance.py`: with the VC answering, `twin…live.config_source` equals `get_state`'s `config_source`, and there is no `report.display_conf`. With the VC absent, `report.display_conf.path_read` is the path actually read, for each of the three locations and for none (FR-034).
- [ ] T066 [P] [US5] Provenance guard in `tests/report/test_provenance_guard.py`. Mutate `default_mappings.xml` (ids, names, `canvas_region`) and `/etc/cuems/display.conf` geometry, then assert that `twin` is byte-identical while `report` changes (FR-008, data-model §8).

### Implementation for User Story 5

- [ ] T067 [US5] Implement `src/cuemshardwaremanager/report/continuity.py`. Read through `cuemsutils` `ConfigManager` public mappings only, per T002's finding; if there is no public path, `available: false` with `reason: no public path`. Match video by connector and DMX by interface; audio is deferred. Produce `matched`, `unmatched_entries` and `unmatched_ports`.
- [ ] T068 [US5] Implement `src/cuemshardwaremanager/report/canvas_hazard.py`. Reproduce `cuems-generate-display-conf`'s reading on the local node's `video/outputs/output/canvas_region` children (`x`, `y`, `width`, `height` via `int(findtext(...))`) and flag those that raise. The module docstring cites research R16 and the plan's Complexity Tracking entry. It feeds `report` only.
- [ ] T069 [US5] Wire the report steps into `src/cuemshardwaremanager/node.py` after all probes, as report steps rather than probes (contracts/probe-plugin.md rule 6).

**Checkpoint**: All five stories are independently functional.

---

## Phase 8: Fixture capture and the hardware gate

**Purpose**: Recorded fixtures from real hosts (FR-036, FR-037, the constitution's testing gate), and the hardware-verification ledger (FR-039).

- [ ] T070 Tests in `tests/unit/test_fixture_import.py` and `tests/unit/test_capture_script.py`:
  - **`fixture-import`** turns a `files` tar, an `ola` JSON and a `manifest` into `tests/fixtures/<model>/`.
    - EDID serials (descriptor and 32-bit field, checksum recomputed) and USB serials become `PSEUDO-<10 hex of HMAC-SHA256(salt, serial)>`, consistently, with OLA unique ids and `ola-port.conf` keys rewritten to match.
    - It refuses with no `CUEMS_FIXTURE_SALT`, into a non-empty target, or when a real serial survives.
    - Nothing is written before pseudonymisation (R15).
  - **The drift guard.** Every path a recording `HostView` reads on the constructed fixtures matches a pattern in `dev/scripts/capture-readonly.sh`'s path list.
  - **`capture-readonly.sh`**:
    - passes `bash -n` and `shellcheck` where available;
    - with a fake root, `files` emits a tar whose members are all under `root/`;
    - it contains no write redirection outside `/dev/null`, and no `sudo`, `systemctl`, `kill`, `ola_*` or `/dev/` opens;
    - **its `ola` mode agrees with the probe:** run against a fake `ola` module, its JSON loads through `HostView.from_fixture`'s recorded OLA client and gives the same DMX devices as the recorded replies T029 uses. That keeps the two guarded OLA reads (`sources/ola_rpc.py` and the script's inline Python) from drifting.
- [ ] T071 Implement the two halves of capture (contracts/cli.md "Fixture capture", R15):
  - **`dev/scripts/capture-readonly.sh`**, with SPDX header and a usage line, following the `dev/README.md` rules. Modes:
    - `files`: a tar to stdout of the path list, which also covers `/proc/<pid>/cmdline` for `jackd` and `zita-j2a` and `/etc/default/jack`, for the later JACK research only (R17);
    - `ola`: inline Python via `/usr/lib/cuems/bin/python -I -B`, behind the two-layer `:9010` guard;
    - `manifest`: DMI fields, the date, package versions, show-lock state.
  - **`src/cuemshardwaremanager/fixture_import.py`** and the `fixture-import` sub-command in `src/cuemshardwaremanager/cli.py`. It pseudonymises in memory, writes the fixture tree (`tests/fixtures/<model>/`, or `--out <dir>` for ledger scratch use), and runs `probe` on it for `expected.json`.
  - Add the script to `dev/README.md`'s table. Make T070 pass.
- [ ] T072 Create the ledger `specs/001-node-twin-discovery/hardware-verification.md`, with one section per host model (N97, N100, i3-1215U, FP530) and the seven checks of quickstart §2. Each check is recorded as verified (date, host, result) or "not verified" (reason).
- [ ] T073 **⛔ STOP: implementation pauses here until the maintainer specifically requests it.** Then, for each production-testing machine, run `dev/scripts/capture-readonly.sh` with the `dev/` procedure. Connect as `cuems-admin` with no sudo, using `ssh … 'bash -s -- <mode>' < dev/scripts/capture-readonly.sh`, with nothing copied, installed, written or restarted on the machine. Pipe the result into `cuems-hw-mgr fixture-import <model>` locally, into `tests/fixtures/n97/`, `tests/fixtures/n100/`, `tests/fixtures/i3-1215u/` and `tests/fixtures/fp530/` (the model comes from the manifest's DMI fields). If the information needed changes, change the script in `dev/scripts/`, not the command. Hand-review each `expected.json` against the host's `cuems-fleet` `nodes.yaml` / `devices.yaml` / `dmx.yaml` without copying them, and record each comparison in the ledger (SC-001).
  - This is a **blocking gate**: the feature is not done without these captures, and there is no "not verified" escape.
  - Afterwards, decide from the retrieved configurations whether FR-035 can be re-widened to per-class expectations, and record the decision in `specs/001-node-twin-discovery/spec.md`.
- [ ] T074 On a real N97 during playback, run the quickstart §2 show-safety check (⚠: loading a show changes machine state, so it needs the maintainer's explicit approval for that machine). Capture with `dev/scripts/capture-readonly.sh`, and record any hitch or xrun in the ledger (SC-007). Without approval or host access, write "not verified" in the ledger.

---

## Phase 9: Polish and cross-cutting concerns

- [ ] T075 [P] Test in `tests/unit/test_plugin_extensibility.py`: registering a test-only class probe (`cls = "testclass"`) makes its devices appear, with no change to `node.py`, `identity.py` or `serialise.py`. Grep-assert that no file outside `src/cuemshardwaremanager/probes/` names `"audio"`, `"video"` or `"dmx"` as a class list (SC-009, Principle VI).
- [ ] T076 [P] Performance test in `tests/test_timing.py`. On fixtures, a probe finishes well under 5 s. With recorded VC and OLA clients that never answer, the run completes under 10 s, with both reported degraded (SC-006, FR-023).
- [ ] T077 Update `CLAUDE.md` "Field notes / gotchas" per FR-040:
  - OLA rogue `olad`: resolved for probing by the two-layer guard; still open for any `olad` restart, owned by the DMX setup feature;
  - `canvas_region`: now diagnosed by the probe's report; the fix belongs to the video setup feature or an earlier `cuems-common` fix;
  - VC "Phase A": provenance recorded; who generates `display.conf` stays open for the video setup feature with the VC team;
  - the dead `hw_discovery` chain: untouched; decided under D-5.
  - Update "Status": code exists, the prototype is gone, and `cuems-hw-mgr probe --json` is the entry point. Name features, never feature numbers.
- [ ] T078 [P] Update `specs/planning/04-open-decisions.md`: in the D-13 row, record that the feature was delivered and give the date; in the D-11 row, add a note that the twin ships `jack_exposure` as `unknown` and that captures record JACK command lines for the research.
- [ ] T079 [P] Draft `specs/upstream-reports/cuems-utils-hardware-outputs-structure.md` for `cuems-utils`' structure pass, built from `specs/001-node-twin-discovery/contracts/probe-output.schema.json`. It covers:
  - persisted versus live fields;
  - the `(uuid, port_id)` addressing rule;
  - D-7, the `direction` field inside a schema named `hardware_outputs`;
  - the stale two-writer annotation in `hardware_outputs.xsd`, which contradicts the sole-writer decision.
- [ ] T080 Run quickstart §1 end to end (`pip install -e ../cuems-utils -e '.[test]'`, `pytest`). Fix anything stale in `specs/001-node-twin-discovery/quickstart.md`. Confirm SPDX headers on every new file in `src/` and `tests/`.

---

## Dependencies and execution order

### Phase dependencies

- **Setup (Phase 1)**: none. T001 to T003 inform R2, R3 and R10, so finish them before the code that relies on them (T030, T034, T067).
- **Foundational (Phase 2)**: depends on Setup and **blocks every story**.
- **US1 (Phase 3)**: depends on Foundational. It is the MVP.
- **US2 (Phase 4)**: depends on US1's probes (it mutates their fixtures).
- **US3 (Phase 5)**: depends on US1's sources (`vc_contract.py`, `ola_rpc.py`). It can run in parallel with US2.
- **US4 (Phase 6)**: depends on US1's probes. It can run in parallel with US2 and US3.
- **US5 (Phase 7)**: depends on Foundational plus T035 (video ports for matching). It can run in parallel with US2 to US4.
- **Hardware gate (Phase 8)**: T070 and T071 need US1. T073 and T074 need host access and every story done.
- **Polish (Phase 9)**: after the stories wanted. T077 to T079 go last.

### Within each story

The tests come first and fail; then the sources, then the probes, then the CLI and report wiring. Re-run the whole suite before closing a phase; a red suite blocks the next one (Testing Gate).

### Parallel opportunities

- **Setup**: T002, T003, T006 and T007.
- **Foundational**: tests T008 to T011 and T019; implementations T012 to T015 and T020 after their tests.
- **US1**: fixtures T021 and T022, tests T023 to T029, and the sources T030 to T034 are all different files. The probes T035 to T037 follow in sequence (audio needs video).
- **US2**: T040 to T046.
- **US3**: T048 to T051.
- **US4**: T054 to T057.
- **US5**: T062 to T066.
- **After US1**: US2, US3, US4 and US5 can proceed in parallel.

---

## Parallel example: User Story 1

```bash
# Fixtures and tests together:
Task: "Constructed fixture tests/fixtures/constructed/intel-allsources/"
Task: "Constructed fixture tests/fixtures/constructed/amd-allsources/"
Task: "Unit tests tests/unit/test_drm_sysfs.py"
Task: "Unit tests tests/unit/test_alsa_procfs.py"
Task: "Unit tests tests/unit/test_hdmi_audio.py"
Task: "Unit tests tests/unit/test_ola_rpc.py"

# Then the sources together:
Task: "src/cuemshardwaremanager/sources/vc_contract.py"
Task: "src/cuemshardwaremanager/sources/drm_sysfs.py"
Task: "src/cuemshardwaremanager/sources/usb_sysfs.py"
Task: "src/cuemshardwaremanager/sources/alsa_procfs.py"
Task: "src/cuemshardwaremanager/sources/ola_rpc.py"
```

---

## Implementation strategy

### MVP first (US1)

1. Phase 1, including the T001 to T003 re-measurements.
2. Phase 2.
3. Phase 3. **Stop and validate**: golden output on both constructed fixtures, schema-valid and byte-stable.

### Incremental delivery

1. **MVP → US2 (identity proof)**: nothing may persist or reference ids before this lands.
2. **→ US3**: safety; required before any run on a live venue.
3. **→ US4**: degraded paths.
4. **→ US5**: continuity and hazards.
5. **→ Phase 8**: recorded captures and the ledger. The feature is not "done" until the ledger states verified or not verified for every check.
6. **→ Phase 9**: `CLAUDE.md` field notes, planning rows, and the upstream draft.

US1 alone is useful to `cuems-fleet` `census`, but it must not run on live venues until US3 is complete.
