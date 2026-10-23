<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Research — Node digital twin from discovery

**Date**: 2026-10-22.

**Measured against**:
- `cuems-utils` `feat/xml-refactor` `8e17ad7`;
- `cuems-common` `feat/xml-refactor` (`cuems-display-setup`, `cuems-generate-display-conf`, `cuems-hdmi-audio-map`, `cuems-ola-profile`);
- the VC contract v1 text, from a scratch copy, **not** a live `feat/contract-report` checkout. Re-measure it before implementing (R3).

Each entry gives the decision, the rationale and the alternatives considered.

---

## R1. Testability seam: every probe reads through a `HostView`

**Decision.** Probes never touch `/` directly. Each one receives a `HostView` that provides:
- a filesystem root, which is `/` on a host and a fixture directory in tests;
- a VC client, an OLA client and a port checker, each an interface with a real and a recorded implementation;
- the show-lock state and the effective uid.

A fixture set is then a directory tree (`sys/`, `proc/`, `etc/`, `run/`, `tmp/`) plus recorded service replies (`services/vc/*.json`, `services/ola/*.json`).

**Rationale.** The constitution's testing gate requires CI to run without hardware and every probe to be tested against recorded fixtures. A root-relative reader is also the simplest way to prove the forbidden acts (FR-021) never happen: the fakes record every call.

**Alternatives.**
- Monkey-patching `open` and `os`: brittle, and it hides what was read.
- Containers with fake sysfs: heavy, and sysfs symlinks are hard to fake.

## R2. Node uuid, show lock and legacy mappings through `cuems-utils`' public paths

**Decision.**
- **uuid and show-lock path.** `ConfigManager(config_dir, load_all=False)` gives `node_uuid` and `show_lock_file`, both public `ConfigBase` properties. When `node_uuid` is the library's published sentinel (an unprovisioned node), the probe exits **could not run** with the reason `node not provisioned`. The twin is keyed by uuid and the uuid is never minted (FR-002).
- **Legacy mappings** (FR-032). Read through `ConfigManager`'s public mapping path (`node_mappings`, which resolves `default_mappings.xml` when no project is loaded). `T0` in the tasks re-measures that this path loads `default_mappings.xml` with no project selected. If it does not, an upstream report is filed, and continuity is reported as unavailable (`reason: no public path`). It is never read privately.
- **A `default_mappings.xml` that fails schema validation** (for example a pixel `canvas_region` such as `1920`, outside `[0, 1]`) is reported as such. Continuity is then empty, with the validation message as the reason.

**Rationale.** Principle IV (public paths only, `cuemsutils.xml.__all__ == []`), and FR-002.

**Alternatives.**
- Parsing `settings.xml` with ElementTree, as `cuems-generate-display-conf` does: rejected, a private copy.

## R3. VC contract client: one-shot, subscribe first

**Decision.** Use `pynng` (0.8.1, already in `/usr/lib/cuems`). The probe:
1. connects `Sub0` to `ipc:///tmp/cuems-videocomposer-events.ipc`, subscribed to everything;
2. dials `Req0` to `ipc:///tmp/cuems-videocomposer.ipc`, with a 1 s send and receive timeout (the contract drops replies not read within 1 s);
3. sends `hello`, `get_caps`, `get_hardware` and `get_state`;
4. drains the subscription without blocking (≤ 100 ms). If it sees `state_changed`, a `pid` different from `hello`'s, or a `seq` gap, it re-reads `get_hardware` and `get_state` **once**.

If the state moves again, video is reported degraded (`vc_state_unstable`). Unknown fields are ignored. Mode `id`s are opaque strings, and sorting uses the typed fields.

**Rationale.** These are the contract's client rules ("subscribe, then read; re-read on gap or new pid; never poll get_hardware"). A one-shot CLI that reads once is the opposite of polling.

**Re-measure.** The contract text used here is a scratch copy. Task `T0` diffs it against `cuems-videocomposer` `feat/contract-report` `docs/contract-v1.md` and the VC's `tools/contract/` mock. The mock replies are the source for the VC fixtures (constitution: fixtures valid against the contract).

## R4. GPU and connector identity from DRM sysfs, even when the VC answers

**Decision.**
- **GPU.** `realpath(sys/class/drm/cardN/device)` gives the PCI function. The GPU key is `pci-<domain:bus:dev.fn>`, for example `pci-0000:00:02.0`, the same form as udev's `ID_PATH`. Vendor and device ids come from `device/vendor` and `device/device`, and the driver from `device/driver`.
- **Connectors** come from the directory names `cardN-<CONNECTOR>`.
- **Joining the VC to a GPU.** The VC's `get_hardware` carries connector names without the GPU, so its connectors are joined to the sysfs connector of the same name. With one DRM card, the join is exact. With several cards and one connector name present on more than one card, the port's identity is **unresolved** and the report gives the reason.
- **Show-lock mode** changes nothing here: these are sysfs reads, and DRM is never opened (FR-024).

**Rationale.** Principle III and FR-009: the key is GPU PCI path plus connector, and DRM minors (`card0`/`card1`) are enumeration order. Sysfs is readable without DRM master, so it is safe while the VC runs.

**Alternatives.**
- Opening `/dev/dri/cardN` for `drmModeGetResources`: needs no master, but `drmModeGetConnector` can force a re-probe and a visible flicker on some sinks. Rejected for 001.

## R5. DRM sysfs fallback: carried forward from `cuems-display-setup`

**Decision.** Port, and do not rewrite, `probe_connected_outputs` / `_read_modes` / `_read_edid_name` from `cuems-common` `usr/lib/cuems/bin/cuems-display-setup`. That keeps:
- **the glob** `card*-*/status`;
- **the modes-file de-duplication**;
- **`5c266c3`**: read `edid` unconditionally, because stat reports size 0, and treat empty bytes as "no EDID".

Two changes from the original:
- **All connectors are enumerated, not only connected ones.** `status` maps `connected` → present, `disconnected` → absent, and anything else → unknown.
- **EDID is decoded in Python, not with `edid-decode`** (R6).

Sysfs `modes` lists only `WxH`, with no refresh. In the fallback, modes therefore carry `width`/`height` with `hz: null` and `id: null`, and the device is marked `modes_partial`. VC mode `id`s are never synthesised.

**Rationale.** This is the brief's requirement and FR-017. Not synthesising `id`s keeps the VC as the only minter of mode ids (one source per fact).

## R6. EDID decoding: base block, in Python, shaped like the VC's `edid` object

**Decision.** Decode the 128-byte base block:
- `make`: the 3-letter PNP id from bytes 8–9, matching the VC's `"GSM"`;
- `model`: the 0xFC monitor-name descriptor (trimmed), matching `"LG ULTRAFINE"`;
- `serial`: the 0xFF serial-string descriptor, falling back to the 32-bit serial number at bytes 12–15 when nonzero, then `""`. This matches the VC's `"506NTMXDV771"`.

Check the header and checksum. A bad block gives `sink: unknown`, never a guess. The sink object has the same three fields whether the VC or sysfs answered.

**Rationale.** It avoids depending on the `edid-decode` binary and spawning a subprocess per connector. It also makes a sink compare equal across sources. The VC's own values are the reference, and a fixture test asserts equality on the same EDID.

**Alternatives.** `edid-decode` (what `cuems-display-setup` uses, for the name only): an external dependency and a subprocess, with output meant for humans.

## R7. ALSA without opening devices

**Decision.** Use only procfs and sysfs text:
- **Cards and streams**: `/proc/asound/cards`; `/proc/asound/cardN/pcmDD{p,c}/info` (id, name, subdevices) — no open needed.
- **The card's physical device**: `realpath(/sys/class/sound/cardN/device)`, giving a PCI function or a USB interface. For USB, the parent device's `idVendor`, `idProduct`, `serial` and `devpath` (the port path, for example `1-2.3`).
- **Channels**:
  - USB: `/proc/asound/cardN/stream0`, which lists channels per altsetting;
  - HDMI: the ELD SADs (R8);
  - any stream currently open by JACK or a bridge: `pcmDDp/sub0/hw_params`, read as **live** state;
- **`/etc/asound.conf`, as a live source.** `cuems-hdmi-audio-map` writes this file at boot. Its `multi_hdmi` definition records which HDMI PCM devices it slotted, and in which order, for this boot. The audio probe reads it as **live** state: for each HDMI audio port, `live.multi_hdmi_slot` (the slot index, or `null` when the port is not in the layout). It also cross-checks `live.alsa_pcm`. The file is service-written, so it is discovered (FR-008). It describes the current boot's slotting, which is why it is live and not persisted. An **absent** file means `cuems-hdmi-audio-map` has not run on this host. That is measured on 10.16.10.3, where it is absent. It gives `multi_hdmi_slot: {"state": "not_configured"}` and is **not** degradation; otherwise every such host would always exit `3`. Only an unreadable or unparseable file is degraded (`asound_conf_unreadable`), with `multi_hdmi_slot: unknown`;
  - otherwise `null`.
- **Kinds** (the maintainer's audio scope ruling, `02-hardware-classes.md` §2):

  | Kind | How it is recognised |
  |---|---|
  | `hdmi` | a PCM whose info `id`/`name` says HDMI/DP and that has ELD entries |
  | `usb` | a card under a USB device (DSPs and interfaces alike) |
  | `onboard` | an analog PCM on a PCI HDA controller that is the platform's audio function (the main L/R) |
  | `pci_multichannel` | an analog PCM on any other PCI card |

  `kind` is an observation. Identity is still physical: the PCI path plus the PCM device index for PCI analog, which is fixed by the codec or driver and not boot-assigned. The ALSA card index and name never enter a key.

**Rationale.** FR-022: never compete with `zita-j2a` or JACK for `hw:` devices. The pipewire race in `02-hardware-classes.md` §2 is exactly what an open would recreate. Reading `info` and `stream0` takes no device lock.

**Open, recorded.** Channel counts for idle PCI analog streams are not visible without opening the device, so they are `null`. That is acceptable under three-valued reporting. Whether the audio setup feature opens devices while no show is loaded is its own decision.

## R8. HDMI audio: the port belongs to its connector, and the PCM mapping is live

**Decision.**
- **Identity.** One HDMI/DP audio output port per audio-capable video connector (HDMI-A, DP; not DSI, eDP or VGA), keyed by the same GPU PCI path plus connector as the video port. Its `port_id` carries `audio:output` and the connector, so it is unique and stable whatever pipe the connector was given at boot.
- **Which ALSA PCM carries it now** is live state, `observed.alsa_pcm`. It is attributed by matching each ELD under `/proc/asound/cardN/eld#C.P` (when `monitor_present 1`, `eld_valid 1`) to the connector whose sink EDID has the same manufacturer and product. Monitor name is used only to break ties.
- **Ambiguity.** If two connectors carry identical sinks, or no ELD matches, `alsa_pcm` is `unknown` and the report lists it. It is never guessed from device numbers. The ELD codec/pin → PCM device mapping comes from `/proc/asound/cardN/codec#C` (`Pin` → `Devices`) where present.
- **Measured shape (2026-10-23, both hosts).** The Intel HDMI codec (`codec#2`) exposes **36** ELD files, `eld#2.0` to `eld#2.35`: one per pin × device set (DP-MST slots). Most are 88-byte "not present" stubs. Only the entries for connected sinks are full, at about 460 bytes. Four HDMI PCMs exist (`pcm3p`, `pcm7p`, `pcm8p`, `pcm9p`), not the three that `cuems-hdmi-audio-map`'s `PIPE_TO_DEVICE` table names. The reader therefore iterates every `eld#*` file, keeps only `monitor_present 1` / `eld_valid 1`, and maps an entry to its PCM through `codec#C` and never through a table. The exact `codec#2` format still has to be recorded from a capture.
- **Channels**: the maximum from the ELD SADs.
- **Presence**:
  - `present` when the video port is present and an ELD is valid;
  - `absent` when the video connector is disconnected;
  - `unknown` otherwise, for example a connected sink with no valid ELD.

**Rationale.** It follows the spec's identity rule (the video connector, never the ALSA device number) without the DRM ioctls `cuems-hdmi-audio-map` uses. So it is identical in show-lock mode and outside it. `cuems-hdmi-audio-map`'s CRTC → pipe → device knowledge comes here later with D-9 (06 C5), as a second, stronger attribution source.

**Alternatives.**
- Porting `cuems-hdmi-audio-map`'s ioctl path now: it opens `/dev/dri`, which FR-024 forbids under show lock, and it is D-9's scope.
- Keying by the ALSA device: forbidden.

## R9. USB DMX candidates and identity

**Decision.**
- **OLA down.** Candidates are USB devices under `/sys/bus/usb/devices/*` that either match a vendor:product table or are bound to `ftdi_sio`, `usbserial` or `usbdmx`-class drivers. The table holds FTDI `0403:6001` (FT232R, which also covers the Eurolite MK2), `0403:6015`, the DMXking/ENTTEC ids, and Eurolite `04d8:fa63`; it is kept as data in the DMX probe.
  - **Key**: the USB serial. Without one, the port path, flagged weak (FR-012).
  - **Ports**: not enumerated. Candidates carry `ports: []` and `observed.ports_known: false`, because port indices are OLA's to define. No port id is invented.
- **OLA up.** The device is keyed by the **serial embedded in OLA's device unique id**. The `usbdmx` and `usbpro` families use `<plugin>-<SERIAL>`, which is the same key `/etc/ola/ola-port.conf` uses (`13-<SERIAL>-O-<port>`). The DMX device key is therefore `serial-<SERIAL>` in both modes. Port ids are `dmx:<direction>:serial-<SERIAL>:<ola port index>`; OLA's port index within a device is defined by the driver, not assignment order.
- **OLA devices with no serial in their unique id** (ArtNet/sACN, transport `network`) are keyed by OLA's unique id string, flagged weak. OLA's numeric `alias` is never used (FR-009).

**Rationale.** It follows OLA's own key (06 finding 13), and the Eurolite MK2 is distinguishable only by serial. Keeping the device key identical across OLA-up and OLA-down is what makes it stable under FR-011.

## R10. Never spawning `olad` (FR-020): two layers

**Decision.**
- **Layer 1, the port check.** A TCP connect to `127.0.0.1:9010` with a 200 ms timeout, closed at once with no bytes sent. A refusal or timeout means the OLA view is `unknown` (`ola_not_listening`).
- **Layer 2, a client that cannot auto-start.** Use OLA's **Python** client (`ola.OlaClient`). It is a pure-Python socket plus protobuf RPC that only `connect()`s to the address it is given, and it contains no spawn path. The C++ `OlaClientWrapper`, used by `ola_dev_info` and every other `ola_*` tool, auto-starts `olad` by default, so **no `ola_*` binary is ever executed**. Read-only calls only: `FetchPlugins`, `FetchDevices`, `FetchUniverses`.
- **`python3-ola` is a declared dependency of this package** (maintainer, 2026-10-23), whether or not a DMX device is attached. It is recorded for the Debian `Depends:` when packaging lands, and in the install requirements until then. It can't be a pip dependency, because OLA's Python client is not on PyPI. If the module still cannot be imported, the install is broken: the OLA view is `unknown` (`ola_client_missing_dependency`), DMX falls back to USB candidates, and the log line names the missing dependency. That is degraded, never a silent skip.

**Verify (T0).**
- **Measured 2026-10-23 on two production-testing hosts:** `python3-ola` is at `/usr/lib/python3/dist-packages/ola/`, and `/usr/lib/cuems/bin/python -I` locates `ola` and `ola.OlaClient`. The shared venv therefore sees the system site-packages, and no packaging route is needed beyond declaring the dependency.
- **Still to do:** read `OlaClient.py` on a host (or in the fork) to confirm it has no spawn path.

**Tests.**
- A fake port checker says "listening", then the fake client's connect fails, as if `olad` died between the two layers: there must be no subprocess.
- `subprocess` and `os.exec*` are patched to fail the test when called anywhere in a DMX probe run.
- With nothing listening, no client is constructed at all.

**Alternatives.**
- Writing our own OLA RPC framing plus `.proto`: rejected, it bundles what `ola` ships (Operating Constraints).
- `ola_dev_info`: it spawns `olad`.

## R11. Show-lock mode

**Decision.**
- **When it is decided.** Once, at start: the `show_lock_file` path from `cuems-utils` exists or not.
- **What it restricts.** Under the lock:
  - files under `sys`, `proc`, `etc` and `run` are read;
  - VC `hello` / `get_caps` / `get_hardware` / `get_state` and OLA's `Fetch*` are each called at most once (re-reads after a VC gap are suppressed and reported);
  - no device node is opened, which is already true of every probe in 001 (R4, R7, R8).
- **Report.** `show_lock` is recorded in the report, together with the list of skipped re-reads.
- **Lock appearing mid-run.** Before each service call the probe re-checks; if the lock has appeared, remaining re-reads are skipped and reported.

**Rationale.** FR-024 and Principle I. Because 001 never opens devices in either mode, the practical difference is limited to re-reads. That keeps the safe path the everyday path.

## R12. Classes are data: probe discovery

**Decision.** `cuemshardwaremanager.probes` is a package. Each module exposes `PROBE`, an object implementing the `Probe` protocol (`contracts/probe-plugin.md`).
- **Discovery.** `pkgutil.iter_modules` over the package, in sorted module-name order. A registry API, `register(probe)`, lets tests add a test-only class (SC-009).
- **No class list.** No code names `audio`, `video` or `dmx` outside the probe modules themselves.
- **Cross-class facts.** HDMI audio needs the video ports. Probes declare `requires = ("video",)`, and the node runs them in dependency order, passing earlier results through a read-only context. That is data again, not a hard-coded sequence.

**Rationale.** F6 and SC-009.

**Alternatives.** `importlib.metadata` entry points cost a `pyproject` line per class and depend on packaging metadata being installed, so `PYTHONPATH` runs on hosts (quickstart) would not see the probes.

## R13. Serialisation, determinism and the output contract

**Decision.**
- **Encoding.** `json.dumps(obj, sort_keys=True, indent=2, ensure_ascii=False)` plus a trailing newline.
- **Ordering.** Arrays sorted by identity: devices by `(class, device_key)`, ports by `port_id`, modes by `(width, height, hz, interlaced)` descending.
- **Numbers.** Floats go through `round(x, 3)`; the VC's `hz` has 2 decimals.
- **No run values.** No timestamps, pids, durations or seq numbers.
- **Format marker.** `"format": "cuems-hw-twin/1"`.
- **Published shape.** `contracts/probe-output.schema.json` (JSON Schema 2020-12) is the documented, field-by-field shape required by FR-028. It marks each `observed` field `persisted` or `live` with an `x-state` annotation, and it is the draft handed to `cuems-utils` for the structure pass.

**Rationale.** FR-027 and FR-028; byte-identical output is SC-003.

## R14. Exit status and logging

**Decision.**

| Exit | Meaning |
|---|---|
| `0` | twin built |
| `3` | twin built with degraded sources |
| `1` | could not run |
| `2` | usage error (argparse's own) |

- **Logs.** `logging` to stderr, one line per degradation, in the form `WARNING degraded class=<c> source=<s> reason=<r> fallback=<f>`. JSON goes to stdout only.
- **Could not run.** stdout carries `{"format": "cuems-hw-twin/1", "error": {"reason": …, "detail": …}}` and no twin.
- **Not degradation.** The deliberate JACK deferral (FR-018a) is listed under `report.deferred`, not `report.degraded`.

**Rationale.** `0`/non-zero keeps `set -e` callers simple for the full case. `census` can then treat `3` as "record, with a flag" and `1` as "failed".

**Alternatives.**
- sysexits codes (`69`, `67`): more codes than callers need.
- Degraded exiting `0`: hides degradation from scripts.

## R15. Fixture capture and pseudonymisation

**Decision (revised 2026-10-23, maintainer).** Capture uses the same procedure as the inspections in `dev/`: `ssh cuems-admin@<host> 'bash -s' < dev/scripts/… > …`. Nothing is copied to the host and nothing is written there. It has two halves.

- **On the host: `dev/scripts/capture-readonly.sh`.** It is bash, read-only, needs no sudo and no checkout, and is called with a mode argument (`bash -s -- <mode>`):
  - `files` streams an uncompressed tar of the probe's source paths to stdout. The path list is a section of the script. Sysfs symlinks are archived as symlinks, and the tar is prefixed `root/`.
  - `ola` prints OLA's `FetchPlugins`, `FetchDevices` and `FetchUniverses` replies as JSON. It uses inline Python through `/usr/lib/cuems/bin/python -I -B`, with the same two-layer `:9010` guard (R10).
  - `manifest` prints the host model and package versions.
- **On the workstation: `cuems-hw-mgr fixture-import <model>`.** It reads the tar stream from stdin, plus the OLA JSON and the manifest. It pseudonymises before anything touches disk, writes `tests/fixtures/<model>/{root,services,MANIFEST}`, and then runs the probe on the result to produce `expected.json` for hand review. Raw serials exist only in the pipe.
- **Drift guard.** A test asserts that every path a recording `HostView` reads on the constructed fixtures matches a pattern in the script's path list. A probe that starts reading something new then fails CI until the script captures it too.

The manifest holds the host model (from `/sys/class/dmi/id/{sys_vendor,product_name,board_name}`, which any user can read), the date, the `cuems-*` package versions, and the show-lock state at capture.
- **Runs as `cuems-admin`, without sudo** (measured 2026-10-23). Every probe source is readable by `cuems-admin` on both hosts, including DRM sysfs and EDID, ALSA procfs, USB sysfs, `/etc/ola`, `/etc/cuems/settings.xml` and `default_mappings.xml`. The one source not yet measured is the VC socket (`0660 cuems:cuems`): it was absent on both hosts, and `cuems-admin` is not in group `cuems`. A capture as `cuems-admin` from a VC that serves the contract will therefore report video from DRM sysfs, degraded with reason `permission`. VC fixtures come from the VC's mock (T001) until that is decided.
- **Same rules as the probe.** It obeys FR-021 to FR-024.
- **Pseudonymisation.** EDID serials (both the descriptor and the 32-bit field, with the EDID checksum recomputed) and USB serials are replaced by `PSEUDO-<first 10 hex of HMAC-SHA256(salt, serial)>`. The salt comes from `CUEMS_FIXTURE_SALT`, is required, and is never committed. Re-capturing the same host with the same salt gives the same pseudonyms, which is what the re-plug tests need. OLA unique ids and `ola-port.conf` keys embedding a serial are rewritten with the same mapping.
- **Cross-check.** Fixtures are compared by hand against `cuems-fleet`'s `nodes.yaml` / `devices.yaml` / `dmx.yaml`, which are read only and never copied into this repository (FR-036). The ledger records each comparison.

**Rationale.** FR-036 to FR-038, and the constitution's "EDID serials are personal-ish data".

**Gate.** Constructed fixtures (hand-built trees) may be used for unit tests. The per-host-model suite is complete only with **recorded** captures from N97/N100, i3-1215U and FP530. It is a **blocking gate** for the feature, not a ledger item that may read "not verified". The captures are taken by connecting **read-only over ssh** to the production-testing machines, **only on a specific request**, at a planned stop in the implementation (task T073). Nothing on those machines is written, installed or restarted. `capture` runs from a checkout via `PYTHONPATH`, and the tree is copied back.

## R16. `canvas_region` hazard: reproduce the generator, not the schema

**Decision.** The hazard is a property of `cuems-generate-display-conf`'s parser, not of the schema: it calls `int()` on the text of `x`, `y`, `width` and `height`. So `0.0`, `0.5` and `1.0` all raise `ValueError`, while `0` and `1` do not. The schema value parsed through `cuems-utils` (R2) is a float and has lost the literal, so the diagnostic needs the literal text.

The probe therefore applies the generator's own reading to the same file: for each local-node `video/outputs/output/canvas_region` element, `int(findtext(child))`, flagging those that raise. This reproduces a program this repository owns (06 C1, decided 2026-10-22). It is not a private copy of the schema, and it reads nothing else. The diagnostic reports the value as written and the generator's exact behaviour. It notes that the failure only bites when no `/etc/cuems/display.conf` operator override exists, because the generator copies an override verbatim and never parses mappings.

This is recorded in the plan's Complexity Tracking, because it touches a `cuems-utils` document outside `ConfigManager`.

**Alternatives.**
- Infer from the float (non-integral means it raises): it misses `0.0` and `1.0`, which the shipped default mappings contain.
- Skip the diagnostic: it is required by the brief.

## R17. JACK

**Decision.** No JACK reads in 001 (FR-018a, D-11 pending). `jack_exposure` is always `{"state": "unknown", "reason": "pending JACK relations agreement"}`. Captures do record `jackd`'s and `zita-j2a`'s `/proc/<pid>/cmdline` and `/etc/default/jack`, for the later research. Probes do not consume them.

## R18. Packaging and running on a host

**Decision.**
- **In scope.** A `pyproject.toml` (setuptools, `src/` layout) with the console script `cuems-hw-mgr = cuemshardwaremanager.cli:main`. The runtime dependencies `pynng` and `cuemsutils` are declared and not bundled (Operating Constraints). `python3-ola` is declared as a system dependency (R10) and documented in `README.md` until the Debian package carries it.
- **Out of scope.** The Debian package and the systemd units arrive with the units feature.
- **On hosts, for the ledger.** Run without installing anything: `PYTHONPATH=<checkout>/src /usr/lib/cuems/bin/python -m cuemshardwaremanager probe --json`, as `cuems`. The shared venv is left untouched.
- **The empty placeholder `CuemsHwDiscovery.py` is removed.** The prototype stays in history at `b09b8cc`.

**Rationale.** The shared venv makes packaging a correctness concern, so not installing into it during verification avoids the `pythonosc`-class incident.

## R19. Root refusal

**Decision.** `os.geteuid() == 0` exits `1` with `reason: refuses to run as root` (FR-031). A non-root user other than `cuems` runs. Permission errors on the VC socket (`0660 cuems:cuems`) or on files become `degraded` with `reason: permission`.

## Field measurements, 2026-10-23

`dev/scripts/inspect-readonly.sh` was run as `cuems-admin` over ssh, with no sudo, on two production-testing hosts (10.16.10.2 and 10.16.10.3). The raw output is committed in `dev/data/`; see `dev/README.md`. The results are 100 and 93 reads with 0 failures.

| Finding | Effect on this design |
|---|---|
| **No VC contract socket on either host.** Confirmed by the maintainer (2026-10-23): the deployed VC **predates contract v1**, and v1 is planned development (`cuems-videocomposer` `feat/contract-report`), not yet on any machine | The VC-contract source is built and tested against the VC's mock only (T001, T024, T030). On today's fleet, video always comes from DRM sysfs, the designed fallback (R3/R5, Principle VII). Field verification of the contract path is deferred until a machine runs a v1 VC; the ledger records it as "not verified: no v1 VC deployed". The `cuems-admin` socket-permission question waits for the same moment |
| **`/tmp/cuems.show.lock` present on both hosts**, possibly stale | Every probe there runs in show-lock mode (R11). Whether a stale lock should be told apart from a live one belongs to the engine. The probe only reports it; the next inspection checks the lock's age and owner |
| **Three `display.conf` files.** `/run` and `/etc` match (the generator copied the override), and the VC's XDG fallback, `/var/lib/cuems/.config/cuems-videocomposer/display.conf`, **differs**. The VC unit's `User=` is `cuems`, with home `/var/lib/cuems` | This is field evidence of 06 finding 10 (the VC saving its own config). FR-034's provenance record matters. The XDG path in T058 resolves to `/var/lib/cuems/…` |
| **EDID** reads return 256 bytes for connected connectors and 0 for disconnected ones | This confirms the size-0 handling in R5 (`5c266c3`): read, then test for empty |
| **HDMI audio:** 36 ELD files on `codec#2` and four HDMI PCMs (3, 7, 8, 9) | R8 is amended: iterate the ELD files, map through `codec#C`, use no device table |
| **10.16.10.2:** `PCH` analog `pcm0p`/`pcm0c` open by JACK (`hw_params` populated), `jackd` running, `/etc/asound.conf` present. **10.16.10.3:** no analog codec on `card0`, a USB audio card (`1-8`, with a serial), no `jackd`, `/etc/asound.conf` absent | All four audio kinds must tolerate being absent. An absent `asound.conf` is `not_configured`, not degradation (R7) |
| **USB:** devices with and without serials on both hosts (for example `1-7` without one); OLA listening; `/etc/ola/ola-usbdmx.conf` present | Weak-identity (`port_path`) devices exist in the field (FR-012) |
| **`/etc/cuems` ownership differs between hosts:** `root:root 0755` on .2, `stagelab:stagelab` on .3 (a legacy user) | Hosts are not uniform. The persistence feature's ownership decision (D-14) has to normalise this, and must not assume either owner |
| **Both hosts report the hostname `controller`** | Irrelevant to the twin, which is keyed by uuid, but a reminder that hostnames are not identity |
| **`python3-ola` visible from the shared venv** | R10 is resolved (import route) |

