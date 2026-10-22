<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Hardware machinery across the ecosystem — state-of-the-art review and single source of truth

**Status (2026-10-22): MEASURED, proposals open.** This is an inventory of every piece of
hardware-related machinery found in the sibling checkouts: what it does, whether it is actually
shipped, what it reads and writes, and where it should live once this repository exists. §3 then
goes fact by fact: how many places hold each hardware fact today, and which single source should
hold it.

**Decided 2026-10-22 (maintainer):** `cuems-generate-display-conf`, `cuems-ola-profile`,
`jack-alsa-bridges.service` and `cuems-gpu-pin` **belong in this repository**. Everything else
marked *absorb* below is a proposal.

## 0. Method and coverage

Measured on the working trees at `cuems-common` `feat/xml-refactor` `ba19317`, `cuems-utils`
`feat/xml-refactor` `b592a57`, `cuems-engine` `3ada95d`, `cuems-editor`, `cuems-frontend`,
`cuems-nodeconf` `6e9be84`, `cuems-power-bridge` `666cb25` and `cuems-dmxplayer`. The method:
- a file-name sweep of each tree for audio, ALSA, JACK, display, DRM, GPU, HDMI, OLA, DMX, udev,
  modprobe and mapping terms;
- a content grep for the consumers of `default_mappings.xml`, `node_hw_outputs`,
  `display.conf`, `hw_discovery` and JACK port names;
- for `cuems-common`, a cross-check of every hit against `debian/install`, `debian/rules` and
  `debian/postinst`, to tell **shipped** from merely **present in the tree**.

**Second pass, same day.** The repositories that are not checked out locally were shallow-cloned
read-only and swept the same way. Each was measured on its releasing branch where one exists:

| Repo | Branch @ commit |
|---|---|
| `cuems-videocomposer` | `rc_1` `e699229`, and `feat/contract-report` `811367f` |
| `cuems-audioplayer` | `rc_1` `f95a390` |
| `jack-volume` | `master` `93c2929` |
| `cuems-midi-connector` | `main` `12226e5` |
| `rtpmidid` | `master` `7f552d2` |
| `cuems-iso` | `debian_12` |
| `ola` fork | `0.10-cuems-eurolite-mk2` (CUEMS notes) |
| `cuems-dmx2net` | `main` `b792626` |
| `cuems-fleet` | `main` `ec478ee` (structure only; no secrets read or copied) |
| `cuems-thermalmon` | `main` `642a3c7` |

Results are in §2.4 and findings 10–15. `rtpmidid` was only checked against its index entry: it
carries MIDI, which is a later class.

---

## 1. Headline findings

1. **Four hardware files sit in `cuems-common`'s tree but are not shipped.** None of them is in
   `debian/install` or `debian/rules`:
   - `usr/lib/cuems/bin/cuems-display-setup`: 758 lines, the **only** operator tool that authors
     `/etc/cuems/display.conf`;
   - `etc/asound.conf`: a static Intel-only `multi_hdmi` on `hw:PCH`;
   - `etc/default/jack`: `USER=stagelab`, `-dmulti_hdmi`;
   - `etc/modprobe.d/alsa-card-order.conf`: pins `snd_hda_intel index=0`, `snd_usb_audio index=1`.

   On deployed hosts, `/etc/asound.conf` is written by `cuems-hdmi-audio-map` at boot. **Who places
   `/etc/default/jack` is not measured**; it has to be checked on a host before the audio setup
   feature.
2. **A hardware-discovery request chain already exists end to end, and nothing answers it.**
   - The editor's WebSocket action `hw_discovery` (`CuemsWsUser.py:699`) asks the controller
     engine.
   - The engine forwards it from `ControllerEngine.hwdiscovery` (`:875`) through
     `request_to_hwdiscovery` to an NNG request on `IpcAddress.HWDISCOVERY = '/tmp/hwdiscovery.ipc'`
     (`cuems-utils` `CommunicatorServices.py:57`).
   - It also has an OSC endpoint, `/engine/command/hwdiscovery`, and an `EngineStatus.hwdiscovery`
     field.
   - **No process listens on that socket**, and no frontend caller was found.

   It is a ready-made, unused UI path for `cuems-hardware-controller` (D-5). It also has to be
   decided explicitly: reuse it or retire it. It must not be duplicated.
3. **The display.conf generator reads the schema's `canvas_region` with the wrong meaning.**
   `cuems-generate-display-conf` reads `<canvas_region>` from `default_mappings.xml` as **integer
   pixels** (`int(findtext('x'))`). `project_mappings.xsd` defines it as **normalised floats in
   [0, 1]** and calls it *"a UI-template hint only … does NOT describe physical monitor layout"*.
   So any schema-valid fractional value (`0.5`) raises `ValueError` in the VC's `ExecStartPre`,
   and a failing `ExecStartPre` aborts the videocomposer's start. Outputs without a region are laid
   out at a fixed 1920×1080 each, whatever their mode. This is a live defect in a script this
   repository now owns. It belongs in the video setup feature, or in an earlier fix in
   `cuems-common`.
4. **`display.conf` has four handlers and no schema.**
   - `cuems-display-setup` writes `/etc/cuems/display.conf`.
   - The generator copies that file, or builds one from `default_mappings.xml`, into
     `/run/cuems/display.conf`.
   - The videocomposer parses it in C++.
   - The engine parses it again in Python (`cuemsengine/tools/display_conf.py`,
     `read_display_conf`).

   The format is the videocomposer's own config, and nothing checks that the two parsers agree.
5. **The HDMI-audio knowledge is held three times, and the JACK wiring is hard-coded in three
   places.**
   - HDMI audio: the static `asound.conf` (unshipped, `PCH`), `cuems-hdmi-audio-map` (detected,
     card-agnostic) and `alsa-card-order.conf` (unshipped, index pinning).
   - JACK wiring: `/etc/default/jack` (`-dmulti_hdmi`), `jack-alsa-bridges.service` (`hw:HID,0`,
     `0_mixer:output_7/8 → usb_audio:playback_1/2`), and the engine's `AudioMixer` defaults
     (`system:playback_1/2`).

   The static `asound.conf` hard-codes the very `PCH` card name whose hard-coding once
   crash-looped `jackd` on AMD.
6. **The output reference key across documents is `<node uuid>_<output id>`.** It appears in the
   `system-defaults.toml` seed comment and in `cuems-nodeconf`'s refusal to merge colliding
   identities (*"the compound `<identity>_<output>` prefix in the project library is the only record
   of which node an output belongs to"*). Port ids in the twin are therefore **load-bearing for
   existing projects**, not just tidy. Whatever ids feature 001 produces must either reproduce
   today's ids on an unchanged host, or come with a migration.
7. **`settings.xml` still stores one derived fact: `videoplayer/outputs`.** It is in
   `settings.xsd:120`, with seed value `outputs = 2`. F3 retired `audio_cards` and `universes`; this
   count stays only until the twin can answer `len(video outputs)`.
8. **DMX is not "universe 0 only".** The `cuems-RELATIONS` index says the player sends universe 0.
   But `cuems-dmxplayer` accepts any `/frame` universe in `0..65535` (`cuems_constants.h`) and
   sends one `SendDMX` per active universe, and the engine's blackout defaults to universes
   `(0, 1)`. `cuems-ola-profile` also has a fifth profile, `eurolite-mk2[:SERIAL]`, which pins an
   FTDI serial. That is the identity-by-serial rule already living in a shell script.
   ([`02-hardware-classes.md`](02-hardware-classes.md) §3 has been corrected.)
9. **Several video-output quirks are hard-coded where the twin could derive them.**
   `cuems-wake-monitors.sh` hard-codes i2c buses 4 and 11, which only fit one controller. Its own
   README's TODO is to *"discover bus numbers dynamically via `/sys/class/drm/<connector>/ddc/i2c-N`"*,
   which is exactly a twin attribute of a video port. `cuems-i915-rebind.sh` is opt-in per host for
   one GPU family, and `cuems-gpu-pin` gates on a PCI-id allow-list. The trigger in all three is
   hardware identity, which is what the twin records.

Second pass (other repositories):

10. **The videocomposer plans to generate `display.conf` itself.** `DRMBackend.cpp:1433` (`rc_1`)
    says: *"FUTURE (PHASE A — urgent): the load in openWindow() should become a
    load-or-generate-and-save so videocomposer itself owns display.conf generation on first boot and
    preserves operator edits on subsequent boots."* That collides with C1 (now owned here) and with
    this repository's video renderer.
    - The same file confirms finding 3: `canvas_region` was *"repurposed from a layout directive
      into a UI-template hint"* on 2026-04-23, *"so reading it as pixels became incorrect"*.
    - The VC also has a third config location, an XDG fallback
      `~/.config/cuems-videocomposer/display.conf`
      (`DisplayConfigurationManager::getDefaultConfigPath`).

    Proposal, to agree with the VC team **before either side builds**:
    - the VC owns the `display.conf` **format**, its run-time state and the v2 write ops;
    - this repository owns the **intent** (the agreement) and the rendering;
    - VC-side generation stays a first-boot fallback for when no rendering exists.
11. **The videocomposer already does network video I/O.** NDI input with discovery
    (`--discover-ndi`, `--list-ndi`, `input/NDIDiscovery.cpp`, `resources/ndi/ndi-config.v1.json`)
    and an NDI output plan (`.cursor/plans/ndi-output-support.plan.md`). NDI sources and sinks are a
    video class with transport `network`. The twin has to leave room for them, and their discovery
    already lives in the VC ([`02-hardware-classes.md`](02-hardware-classes.md) §5, updated).
12. **`cuems-fleet` keeps a hand-written hardware twin of every deployed node.**
    - `inventory/nodes.yaml` has free-text `hardware:` and `outputs:` per node: CPU/board, connectors,
      modes, canvas, even monitor EDID serials.
    - `inventory/devices.yaml` lists projectors and DMX interfaces with model, serial and `host_uuid`.
    - `inventory/dmx.yaml` has universes, the OLA patch key (`13-<SERIAL>-O-1`), fixtures, and the
      `cuems-dmx2net` consumer.
    - Its `bin/census` already probes a box read-only over ssh, at nice 19, refusing during a show
      (`--require-idle`).

    That is this repository's twin, typed by hand. SSOT: fleet should **record** the twin, with
    `census` calling `cuems-hw-mgr probe --json`, rather than re-type it. Feature 001's JSON is
    useful to operations the day it lands, and fleet's per-site records are a ready-made fixture
    corpus for it.
13. **OLA behaviour the DMX probe and renderer must embed** (`ola` fork `CLAUDE.md`):
    - **Rogue `olad`.** `libola` auto-starts its own `olad` as `cuems` whenever `:9010` is empty.
      Any `systemctl restart olad`, or `cuems-ola-profile`, must SIGSTOP live dmxplayers first.
    - **Port patches are keyed by interface serial** (`/etc/ola/ola-port.conf`), and are flushed
      only on a clean shutdown.
    - **The Eurolite MK2 shows stock FT232R descriptors.** It cannot be told apart by USB identity,
      only by serial.
    - **A recorded venue failure** (fleet `events`): *"DMX dead 35 min — FT232 re-enumerated, olad
      never reopened"*. Event-driven presence tracking of DMX ports detects exactly this.
14. **GPU clock policy is split across two repositories.**
    - `cuems-gpu-pin` (AMD DPM `high`, allow-list `1002:15d8`) moves here (decided).
    - `cuems-thermalmon`'s `cuems-thermalmon-gpucap.service` caps the i915 `gt_max_freq` (1200 →
      800 MHz) for N97 peak-power micro-bursts.

    Both are boot oneshots keyed on GPU identity, and thermalmon also detects GPUs in its own
    collectors (root, system python). SSOT proposal: one owner for **GPU policy**, this repository,
    beside `cuems-gpu-pin`. thermalmon stays the monitor that measures whether a policy helps. This
    is a joint decision with thermalmon.
15. **`cuems-dmx2net` holds the reserved universes, and its safety depends on facts held elsewhere.**
    - The universes are in `/etc/cuems/dmx2net.conf` and must be ≥ 2, because the engine's blackout
      defaults to `(0, 1)` (finding 8).
    - It is single-sender only by deployment: DMX cues fire on every node, because `DmxCue` has no
      `localize_cue`.
    - Its runbook forbids patching any port to the reserved universe on any host. OLA's web UI on
      `:9090` can do exactly that.
    - It runs as root (`SO_BINDTODEVICE`) under system python.

    SSOT: reserved universes belong in the **agreement**. The agreement can then enforce "no port
    patched to a reserved universe" and give the engine its blackout set, instead of three
    repositories keeping one invariant by convention.

---

## 2. Inventory

Proposal key:
- **Absorb**: moves into this repository with the feature that replaces it.
- **Absorb-later**: moves here, but after the first setup features.
- **Retire**: deleted when superseded.
- **Stays**: keeps its owner.
- **Consumer**: another repository that reads hardware data and migrates onto the twin or the
  agreement; it does not move.

### 2.1 `cuems-common` (feat/xml-refactor `ba19317`)

| # | Piece | Shipped | What it does | Proposal |
|---|---|---|---|---|
| C1 | `usr/lib/cuems/bin/cuems-generate-display-conf` + VC drop-in `display-conf-gen.conf` | yes | VC `ExecStartPre`. Copies `/etc/cuems/display.conf` verbatim if present, else builds one from `default_mappings.xml` filtered by local uuid | **Absorb (decided).** It becomes the last step of the video renderer, still running as the VC's `ExecStartPre`, through a drop-in shipped by this package. Fix finding 3 on the way |
| C2 | `usr/lib/cuems/bin/cuems-display-setup` | **no** | Interactive authoring of `/etc/cuems/display.conf`: DRM/EDID probe, layout prompts, refuses under show lock | **Absorb as prior art, then retire.** Superseded by the agreement plus the video renderer. Its DRM/EDID reading (incl. `5c266c3`, the sysfs size-0 EDID quirk) is input for the video probe's fallback |
| C3 | `usr/bin/cuems-ola-profile` | yes | Toggles OLA plugin profiles (`pro`, `opendmx`, `eurolite-mk2[:SERIAL]`, `artnet`, `sacn`), handles the `ftdi_sio` blacklist, restarts `olad` | **Absorb (decided).** The DMX renderer's backend; its profile table becomes part of the DMX class |
| C4 | `etc/systemd/system/jack-alsa-bridges.service` | yes | `zita-j2a` for `hw:HID,0`, hard-coded mixer wiring | **Absorb (decided)**, **parameterised** from the applied setup (one bridge per agreed USB device) |
| C5 | `usr/bin/cuems-hdmi-audio-map` + `cuems-hdmi-audio-map.service` | yes | Boot oneshot before `jackd`: DRM CRTC → HDA device, writes `/etc/asound.conf` `multi_hdmi` | **Absorb.** Resolves D-9: one implementation of the pipe → device mapping, used by the audio probe and by the boot oneshot, keeping `Before=jackd-cuems.service` |
| C6 | `jackd-cuems.service` | yes | The JACK server; reads `DAEMON_ARGS` from `/etc/default/jack` | **Absorb** with the audio setup feature. `DAEMON_ARGS` becomes a rendering of the agreement |
| C7 | `etc/default/jack` | **no** | `USER=stagelab`, `-R -dalsa -dmulti_hdmi -r48000 -p512 -n3` | **Rendered** by audio setup. Measure first where deployed hosts get it from |
| C8 | `etc/asound.conf` | **no** | Static Intel-only `multi_hdmi` | **Retire** — C5 writes the real one, card-agnostic |
| C9 | `etc/modprobe.d/alsa-card-order.conf` | **no** | Pins ALSA card indices | **Retire.** Identity by attribute (02 §2) makes index pinning unnecessary |
| C10 | `etc/tmpfiles.d/jack-cuems.conf`; the pipewire/wireplumber masks in `etc/systemd/user/` | yes | Keep JACK shm alive; keep pipewire off `hw:HID` | **Absorb with C6**: they are the audio stack's preconditions |
| C11 | `olad.service`; postinst OLA block (init.d diversion, `~/.ola → /etc/ola` symlinks); `scripts/test-ola-flock-patch.sh`; `docs/ola-install.md`; `instructions/ola-dmx-configuration.txt` | unit + postinst yes | The DMX daemon and its rogue-instance defences | **Absorb with the DMX setup feature**. The node engine's `After=olad.service` ordering must survive the move |
| C12 | `usr/lib/cuems/bin/cuems-extract-video-latency` | yes | VC `ExecStartPre`: `output_latency_ms` from `settings.xml` | **Absorb-later** (D-10). It will read override → measured → `auto` |
| C13 | `usr/bin/cuems-wake-monitors.sh` + `wake-monitors.conf.example`; `usr/bin/cuems-i915-rebind.sh` + `i915-rebind.conf.example`; `hdmi-helpers.README` | yes (opt-in) | DDC wake on hard-coded i2c buses; i915 PCI rebind before VC start | **Absorb-later** as twin-driven video quirks (finding 9) |
| C14 | `cuems-gpu-pin` + unit + `/etc/cuems/gpu-pin.conf` | yes (gated) | AMD DPM pin on a PCI-id allow-list | **Absorb — decided 2026-10-22.** Becomes this repository's GPU-policy module, gated on the twin's GPU identity. Keep its exit contract and the ships-`false` gate. Pair with thermalmon's gpucap (finding 14) |
| C15 | `docs/latency-tuning.md` | yes (doc) | Names a `hardware-discovery` role | Stays with its doc owner; correct the name (03 §4) |
| C16 | VC drop-ins `30-memory-limits.conf`, `40-wait-for-plymouth.conf`; `videocomposer-flags.env.example` | yes | VC process limits and boot ordering | **Stays** with whoever owns the VC unit — not hardware outputs |
| C17 | `cuems-displays-on` + unit | yes | Boot confirmation that projectors came on | **Not here**: `cuems-power-bridge` already plans to absorb it (its A3/A4) |
| C18 | `etc/systemd/network/10-*.link`, `link-files.README` | yes | NIC naming | **Not here**: networking (`cuems-nodeconf` / `cuems-common`) |
| C19 | `etc/modules-load.d/cuems-midi.conf` | yes | Loads `snd-seq` | Not now. Belongs with a future MIDI class, alongside `cuems-midi-connector` |
| C20 | `etc/grub.d/11_cuems_recovery` | yes | Recovery boot entry that masks the VC | **Stays** — boot/recovery, not outputs |

### 2.2 `cuems-utils` (feat/xml-refactor `b592a57`)

| # | Piece | What it does | Proposal |
|---|---|---|---|
| U1 | `xml/schemas/hardware_outputs.xsd`; `SchemaName.HARDWARE_OUTPUTS` refused in `ConfigManager` | Reserved, not loadable | Stays with `cuems-utils`; **promoted from feature 001's JSON model** (D-13) |
| U2 | `project_mappings.xsd` node device inventory; `make_defaults._default_mappings`; `init_node` (three-way merge of `default_mappings.xml`); `system-defaults.toml` `[project_mappings.*]` | Generates and maintains the node-scoped fallback document | **Retire** with the layer (`etc-cuems-first-install.md` §8.5 step 5) |
| U3 | `ConfigManager.node_hw_outputs` / `HardwareOutputs`, `using_default_mappings`, `get_video_output_id` / `get_audio_output_id` | Flattens mappings into `{section}_{direction}` port-name lists; the fossil pair | **Replaced** by the twin accessor; the fossil pair deleted or backed (capability-layer §7 item 2) |
| U4 | `tools/identity_check.py`, `tools/remint.py` | Rewrite the uuid across `settings.xml`, `network_map.xml`, `default_mappings.xml` | **Consumer**: follows whichever document carries the node uuid next (the twin, the applied slice) |
| U5 | `settings.xsd:120` `videoplayer/outputs`; seed `outputs = 2` | Stored count | **Retire** (F3) once the twin answers it |
| U6 | `CommunicatorServices.IpcAddress.HWDISCOVERY = '/tmp/hwdiscovery.ipc'` | The address of finding 2's dead chain | **Reuse** as `cuems-hardware-controller`'s local endpoint, or retire. Decide in D-5 |
| U7 | `cues/AudioCue`, `VideoCue`, `DmxCue` reading `project_node_mappings` | Cue-side output resolution | **Consumer** |

### 2.3 Other repositories

| # | Repo | Piece | Proposal |
|---|---|---|---|
| E1 | `cuems-engine` | `ControllerEngine.hwdiscovery`, `ControllerCommunications.request_to_hwdiscovery`, OSC `/engine/command/hwdiscovery`, `EngineStatus.hwdiscovery` | Finding 2. The engine hop is only needed if the UI path keeps going through the engine; D-5 recommends editor → controller service directly |
| E2 | `cuems-engine` | `tools/display_conf.py` `read_display_conf` | **Consumer**: a second `display.conf` parser. Should read geometry from the applied agreement (accessor) or the VC's `get_state` |
| E3 | `cuems-engine` | `NodeEngine.set_audio_players` sizes the mixer by `node_hw_outputs`; `AudioMixer` defaults to `system:playback_1/2` | **Consumer**; the hard-coded defaults become the agreement's default output |
| E4 | `cuems-engine` | `DmxPlayer.send_blackout` defaults to universes `(0, 1)` | **Consumer**: should black out the agreement's patched universes |
| E5 | `cuems-engine` | `VideoPlayer` / `NodeEngine` `DISPLAY_MISMATCH`, `UNROUTED_VIDEO_OUTPUT` | **Consumer**; these diagnostics become checks of the agreement against the twin |
| ED1 | `cuems-editor` | WS action `hw_discovery` (`CuemsWsUser.py:699`) | Finding 2 — the relay already exists |
| ED2 | `cuems-editor` | `cli.py` and `CuemsWsServer` merging mapping-document nodes' outputs into the node list; `hardware_outputs` refusal messages | **Consumer** |
| F1 | `cuems-frontend` | `core/mapping-wire.ts` (device class → outputs), audio/video mixers over `node.outputs`, read-only `project-mappings` view, schema descriptor listing `hardware_outputs` | **Consumer**; gains the agreement UI. No `hw_discovery` caller found |
| P1 | `cuems-power-bridge` | `displays/` (PJLink, ESC/VP.net, manager), `power-bridge.conf` `projector.N.{host,driver,name,port,password,brightness,escvp_*}` | **Stays**; read by the network-displays work (D-8) |
| N1 | `cuems-nodeconf` | none (only the compound-key comment in finding 6) | — |
| X1 | `cuems-dmxplayer` | universes `0..65535` per `/frame`, one `SendDMX` per active universe | **Consumer** |

### 2.4 Second pass — repositories not checked out locally

| # | Repo | Piece | Proposal |
|---|---|---|---|
| V1 | `cuems-videocomposer` | `DisplayConfigurationManager` (the `display.conf` parser and writer: `canvas_size`, `refresh`, `blend`, `enabled`, …); `DRMBackend` reading `/run/cuems/display.conf`; the XDG fallback path | **Stays**: the VC owns the format. This repository renders to it (finding 10) |
| V2 | `cuems-videocomposer` | *Phase A* plan: the VC generates and saves `display.conf` itself | **Agree before building** (finding 10) |
| V3 | `cuems-videocomposer` | `docs/contract-v1.md` (`feat/contract-report`) | **Consumed** — the primary video probe |
| V4 | `cuems-videocomposer` | NDI discovery and input, NDI output plan, `ndi-config.v1.json` | **Stays**; the twin describes NDI as a network video class (finding 11) |
| V5 | `cuems-videocomposer` | ships no systemd unit (`cuems-common` ships `cuems-videocomposer.service`) | Its unit is outside this repository; C1's drop-in attaches to it |
| A1 | `cuems-audioplayer` | `--device` selection through RtAudio on the JACK API; never auto-connects to `system:playback_*` | **Consumer**: the engine wires it to the mixer |
| J1 | `jack-volume` | `0_mixer` with `num_channels` passed in, ports `output_N` / `input_N` | **Consumer**. The `0_mixer:output_7/8` wiring in C4 implies an 8-channel mixer (6 HDMI + 2 USB): a number to derive from the agreement, not hard-code |
| M1 | `cuems-midi-connector` | wires ALSA sequencer clients by name (`MtcMaster`, `rtpmidid`, players); no hardware MIDI devices | Not now — MIDI class later |
| I1 | `cuems-iso` | stock live-build hooks, no hardware-specific configuration | Nothing to absorb. Hardware-model golden images are still only a future note in `cuems-common` |
| O1 | `ola` fork | `+cuems3`: flock patch, Eurolite MK2 backport; field notes (finding 13) | **Stays** (a fork). The DMX renderer must embed its operational rules |
| D1 | `cuems-dmx2net` | `/etc/cuems/dmx2net.conf` reserved universes ≥ 2; its own unit (root) | **Stays** as the network-DMX bridge; reserved universes move into the agreement (finding 15) |
| FL1 | `cuems-fleet` | `nodes.yaml` `hardware:` / `outputs:`, `devices.yaml`, `dmx.yaml` | **Consumer**: records the twin rather than re-typing it (finding 12) |
| FL2 | `cuems-fleet` | `bin/census` (read-only remote probe, `--require-idle`) | **Consumer**: calls `cuems-hw-mgr probe --json` once it exists |
| T1 | `cuems-thermalmon` | `cuems-thermalmon-gpucap.service` (i915 frequency cap) | **Proposal: absorb**, beside `cuems-gpu-pin` (finding 14). Joint decision with thermalmon |
| T2 | `cuems-thermalmon` | GPU/CPU collectors (amdgpu, i915, MSR) | **Stays**: monitoring, not inventory. May later read GPU identity from the twin |

---

## 3. Single source of truth — fact by fact

For each hardware fact: every place it is held today, and the one place it should come from. A fact
held in more than one writable place has no arbiter (F1). A fact computable from another is not
stored (F3).

| Fact | Held today | Single source (proposed) | Everything else becomes |
|---|---|---|---|
| Which video connectors exist, their modes and sinks | VC DRM detection; `cuems-display-setup` probe; `default_mappings.xml` video outputs (`mapped_to` = connector); `display.conf` `[output:…]` sections; `settings.xml` `videoplayer/outputs` count | **Twin** (`cuems-hardware-node`, fed by the VC contract) | a probe input (VC); a rendering (`display.conf`); deleted (count, mappings inventory) |
| Video geometry: canvas, regions, blends, chosen mode | `/etc/cuems/display.conf` (hand or `cuems-display-setup`); generator's fallback from `canvas_region` read as pixels (finding 3); `project_mappings` `canvas_region` as a normalised UI hint | **Agreement** (`cuems-hardware-controller`), applied slice on each node | `display.conf` = a rendering; `canvas_region` stays only as what the schema says it is, an authoring hint |
| What the VC is driving right now | VC `get_state`; engine re-parsing `display.conf` | **VC `get_state`** (runtime, never stored) | engine reads the applied agreement or asks the VC; no third parser |
| HDMI audio: connector ↔ ALSA device | static `asound.conf`; `cuems-hdmi-audio-map`; `alsa-card-order.conf` | **Twin** (one implementation, C5) | `asound.conf` = a rendering; the static file and card pinning retired |
| Which audio devices join JACK, and how | `/etc/default/jack`; `jack-alsa-bridges.service` arguments; engine `AudioMixer` defaults | **Agreement** | `DAEMON_ARGS`, bridge arguments = renderings; engine defaults read the agreement |
| Audio output count / mixer size | `node_hw_outputs` derived from `default_mappings.xml` | **Twin + agreement** (count of agreed outputs) | computed, never stored |
| DMX interfaces and their identity | `/etc/ola/*.conf` via `cuems-ola-profile` (incl. pinned FTDI serial); OLA's runtime view | **Twin** (from OLA + USB) | OLA config = a rendering |
| Universe ↔ port patch, active universes | OLA's patch state (`/etc/ola/ola-port.conf`, keyed by serial); engine blackout default `(0, 1)`; `cuems-dmx2net`'s reserved universes in `/etc/cuems/dmx2net.conf`; fleet's `dmx.yaml` | **Agreement** | OLA patch = a rendering; engine blackout set and dmx2net's universes read from the agreement; fleet records it |
| Per-node hardware record for operations | `cuems-fleet` `nodes.yaml` `hardware:` / `outputs:` (free text), `devices.yaml`, `dmx.yaml` — typed by hand | **Twin** | fleet records `cuems-hw-mgr probe --json` output via `census` |
| GPU policy (clock pin / cap) | `cuems-gpu-pin` (AMD, `cuems-common` → here); `cuems-thermalmon-gpucap` (i915) | **This repository**, keyed on the twin's GPU identity | thermalmon measures; it does not set policy |
| Who generates `display.conf` | the generator (C1, here); the VC's planned *Phase A* self-generation; hand edits; `cuems-display-setup` (unshipped) | **This repository's renderer** from the agreement; VC generation only as a first-boot fallback | agreed with the VC team (finding 10) |
| NDI sources and sinks | VC's NDI discovery | **VC discovers, twin describes** | — |
| Projector list and link to outputs | `power-bridge.conf` `projector.N.*` | `power-bridge.conf` for now (D-8); the **output → projector link** in the agreement | — |
| Measured output latency | nowhere (only operator overrides in `settings.xml`) | **Twin** (D-10) | `cuems-extract-video-latency` reads override → measured → `auto` |
| Node identity in hardware documents | `settings.xml` uuid; copied into `default_mappings.xml` node entry | **`settings.xml`** (unchanged) | the twin carries the uuid as its key, read from `settings.xml`, never minted |
| Output reference used by projects | `<node uuid>_<output id>` from `default_mappings.xml` ids | **Agreement output ids**, derived from twin port ids | needs an id-continuity rule or a migration (finding 6) |

## 4. What this changes in the plan

- **Feature 001** gains two requirements. It must record, for every port, the id today's
  `default_mappings.xml` would give it, so continuity can be checked (finding 6). Its video
  fallback starts from `cuems-display-setup`'s DRM/EDID code (C2).
- **D-5** now has a concrete option: answer the existing `/tmp/hwdiscovery.ipc` chain rather than
  build a new one (finding 2).
- **D-9** resolves toward absorbing `cuems-hdmi-audio-map` (C5).
- **The setup features take their pieces with them**:
  - video: C1, C2, C13 later;
  - audio: C4, C5, C6, C7, C8, C9, C10;
  - DMX: C3, C11.
- **Finding 3 is a live defect.** Either `cuems-common` fixes it now, or the video setup feature
  takes it on; raise it with `cuems-common` either way, since it ships there today.
- **To measure on a host before the audio setup feature**: where `/etc/default/jack` comes from, and
  whether any deployed host still carries the static `asound.conf` or `alsa-card-order.conf` from an
  older hand install.
- **Raise with the VC team now** (finding 10): who generates `display.conf`. Both sides have it on
  their roadmap.
- **Fixture corpus for 001**: `cuems-fleet`'s per-site records describe real hosts (FP530, N97,
  N100, i3) and their outputs. They are what the probe's recorded fixtures should be checked
  against (finding 12).
- **GPU policy** joins the plan as a module of `cuems-hardware-node` (C14 decided; T1 proposed). It
  needs no agreement: it is keyed on hardware identity, gated per host, and inert by default, so it
  can follow the twin feature directly.
- **The DMX setup feature** must embed the OLA rules in finding 13 (SIGSTOP wrap, clean-shutdown
  persistence, serial-only identity), and the agreement must own reserved universes (finding 15).
