<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Hardware classes — sources, identity, capability vs configuration

**Status (2026-10-22): PROPOSAL.** One section per class the first features cover, plus the classes
the design must leave room for. Each section separates what the **twin** records (discovered,
stage 2) from what the **agreement** decides (authored, stage 5) and where **setup** lands
(stage 6). Architecture context: [`01-architecture.md`](01-architecture.md).

The field notes cited are measured in sibling repositories; they are here because each one is a
probe or identity rule waiting to be written down.

---

## 1. Video outputs

| | |
|---|---|
| **Primary source** | VC contract v1 `get_hardware`: one entry per GPU connector, connected or not, with `connection`, `edid {make, model, serial}`, `current`, `preferred`, `modes[] {id, width, height, hz, interlaced}`. `get_state` for what is driven (canvas, regions, blends, pacing) |
| **Fallback** | DRM sysfs: `/sys/class/drm/card*-<connector>/{status,edid,modes}` — readable without DRM master, so safe while the VC runs. Then `/run/cuems/display.conf`, as the contract itself prescribes |
| **Identity** | `port_id` ← GPU PCI path + connector name (`HDMI-A-1`). Not `card0`/`card1` (DRM minor order is enumeration order). The **sink** (monitor or projector) is identified separately by EDID make/model/serial |
| **Twin records** | connectors, connection (three-valued), sink EDID, mode list by VC `id`, preferred mode, GPU vendor/model |
| **Agreement decides** | enabled, mode `id`, region on the canvas, blend, pacing (`coupled` / `per_surface`). VC v2 adds colour and warp |
| **Setup lands in** | v1 era: a rendering of `/etc/cuems/display.conf`, which `cuems-generate-display-conf` already copies verbatim to `/run/cuems/display.conf` at every VC start; then VC + node-engine restart. VC v2 era: the contract's write ops, gated by `show_loaded` on the VC side too |
| **Replaces today** | `cuems-display-setup` (interactive, 758 lines, probes DRM and authors `/etc/cuems/display.conf`); the video section of `default_mappings.xml` that `cuems-generate-display-conf` reads |

Rules the probe must respect, from the contract and the field:

- **Never poll `get_hardware`.** Read it on connect, after `state_changed`, and after a `pid` change.
  If something must be polled, poll `get_state`.
- `current: null` means *not driven*, which includes **plugged in after the VC started** — the VC
  builds its outputs only at start, and v1 has no `hotplug` cap. A connected-but-undriven connector
  is a normal twin state, not an error.
- `connection: unknown` is not `disconnected`.
- Interlaced modes are listed but never selected unless asked; `hz` is the field rate for them.
- `mode_warning kind=mixed_refresh` is worth surfacing to the operator at agreement time: unequal
  rates across a seam have no frame lock.
- The engine reads `display.conf` **only at node start** (`DISPLAY_MISMATCH`, `UNROUTED_VIDEO_OUTPUT`
  in its journal), so a video apply restarts the VC **and** the node engine.
- Boot-order hazards already handled elsewhere and not to be undone: the VC waits for Plymouth to
  release DRM master; Meteor Lake needs `i915.force_probe=7d45` or `/dev/dri` is absent; the Intel
  TC-port DP/HDMI silent failure needs a PCI rebind on some controllers. A twin with **zero
  connectors** on a host that should have them is a diagnosis worth reporting, not just an empty list.

## 2. Audio outputs and inputs

| | |
|---|---|
| **Sources** | ALSA: `/proc/asound/cards`, `/sys/class/sound/*` (works with JACK down). DRM ELD / connector state for HDMI audio (the connector ↔ CRTC pipe ↔ HDA device mapping `cuems-hdmi-audio-map` computes). USB descriptors for USB interfaces. JACK, read-only, for which physical ports are exposed (`system:playback_N`, `usb_audio:playback_N`) |
| **Identity** | HDMI/DP audio ← the **video connector** it rides on, never the ALSA device number (pipes are assigned at boot: pipe A/B/C → devices 3/7/8). USB audio ← USB vendor:product + serial, or physical port path when there is no serial. Never the ALSA card *name* (`PCH` on Intel N97/N100, `Generic` on AMD) |
| **Twin records** | devices, channels per direction, which are exposed in JACK, sample rate in use |
| **Agreement decides** | which devices join the JACK graph and how (the `multi_hdmi` slots, `zita-j2a` bridges), channel order and naming, the default output |
| **Setup lands in** | `/etc/asound.conf` (`multi_hdmi`), `/etc/default/jack` `DAEMON_ARGS`, the `jack-alsa-bridges` arguments — today hard-coded `hw:HID,0` and `0_mixer:output_7/8 → usb_audio:playback_1/2` |
| **Replaces today** | the audio sections of `default_mappings.xml`; the hard-coding in `jack-alsa-bridges.service`. `cuems-hdmi-audio-map`'s **knowledge** belongs in the twin; its **boot-time role** (before `jackd`) is a seam question (D-9) |

Rules:

- `multi_hdmi` always has **three slots (6 channels)** whatever is connected, so JACK channel
  numbering stays stable. The agreement must preserve that property or replace it with something
  equally stable — channel numbers are what projects end up referencing.
- **Port ids are unique per node across directions.** Inputs reusing the outputs' numbering routed a
  cue to `system:capture_1` and played silent (`cuems-engine` `35cbe78`).
- Pipewire and wireplumber are masked system-wide because they race `zita-j2a` for `hw:HID`. A probe
  must not open devices in a way that recreates that race.
- Registering a JACK client on the real-time server is not free. Prefer the least intrusive read
  (D-11).

## 3. DMX

| | |
|---|---|
| **Sources** | OLA RPC on `localhost:9010`: plugins, devices, ports, universe patching. USB enumeration (FTDI-based interfaces), `/etc/ola/*.conf` for the active profile. Network DMX (ArtNet, sACN) as OLA sees it |
| **Identity** | ← the device's own serial / unique name as OLA reports it, plus port index. Not OLA's numeric device alias (assignment order). USB VID:PID alone is not enough — common FTDI-based interfaces from different families can share it, which is why OLA's view is the primary source |
| **Twin records** | interfaces, ports and direction, RDM support, which plugin claims them, network nodes seen |
| **Agreement decides** | universe ↔ port patch, the OLA profile (`pro` and `opendmx` are mutually exclusive: usbpro vs ftdidmx driver), universes reserved for `cuems-dmx2net` |
| **Setup lands in** | OLA patching over RPC; the profile through `cuems-ola-profile` (or its successor, D-9) |
| **Replaces today** | `settings.xml`'s retired `universes` count (F3: derived, never stored); the empty `dmx` section the prototype wrote |

Rules:

- **Corrected 2026-10-22 ([`06-machinery-inventory.md`](06-machinery-inventory.md) finding 8):** the
  player is **not** universe-0-only, although the `cuems-RELATIONS` index says so.
  `cuems-dmxplayer` accepts any `/frame` universe in `0..65535` and sends one `SendDMX` per active
  universe, and the engine's blackout defaults to `(0, 1)`. So the agreement's universe ↔ port
  patch is real routing for every universe a project uses, and the engine's blackout should come
  from it.
- `cuems-ola-profile` already pins DMX interfaces by FTDI serial (`eurolite-mk2:SERIAL`): the
  identity rule above, living in a shell script today.
- `cuems-dmx2net` reserves universes ≥ 2 to drive network devices through ordinary DMX cues. Those
  universes are a **virtual** DMX output class in the twin (transport `virtual`), so the operator sees
  them beside physical interfaces.
- `olad` must bind `:9010` before the node engine spawns the player (`cuems-common` 1.3.0-12).
  A DMX apply that restarts `olad` must respect that order.
- The CUEMS OLA build is patched (`flock()` serial locking; self-lock race after > 21 h). The twin may
  record the OLA version so a missing patch is visible; it does not own the patch.

## 4. Network displays (projectors)

| | |
|---|---|
| **Sources** | `power-bridge.conf` `projector.N.*` (today's only authoring), the bridge's `GET /status`; PJLink class queries (`NAME`, `INF1`, `INF2`, `CLSS`) and, later, PJLink class 2 search for discovery |
| **Identity** | MAC or serial as the device reports it; never its IP |
| **Twin records** | projectors on the LAN, protocol (PJLink / Epson ESC/VP.net), model |
| **Agreement decides** | **which video output feeds which projector** — the sink link. This is what lets the operator see "HDMI-A-1 on node01 → stage-left projector" |
| **Setup lands in** | nothing directly: power and brightness stay with `cuems-power-bridge`. Whether the bridge's projector list moves from `power-bridge.conf` to the agreement is D-8 |

A projector is a *sink* of a video output, not an output of its own. It is in the first wave because
the bridge already holds projector configuration and the operator thinks in projectors, not in
connectors.

## 5. Classes to leave room for (F6: a new class is data, not schema)

| Class | Likely source | Note |
|---|---|---|
| MIDI ports | ALSA sequencer, `rtpmidid` | `cuems-midi-connector` owns wiring; the twin would only describe |
| Timecode in (LTC) | audio input + decoder | Today MTC is generated by the controller and distributed by `rtpmidid` |
| Video inputs / capture | V4L2 | No CUEMS consumer yet |
| NDI video in / out (network) | the videocomposer's own NDI discovery (`--discover-ndi`, `--list-ndi`) | **Already used by the VC** (input; output planned). The VC discovers; the twin describes them as video ports with transport `network` ([`06-machinery-inventory.md`](06-machinery-inventory.md) finding 11) |
| GPU (not an output, but policy-bearing) | PCI identity, DRM driver | Recorded so GPU policy (`cuems-gpu-pin`, decided to move here) can key on it. See 06 finding 14 |
| GPIO / relays | — | The Shelly relay is `cuems-power-bridge`'s; not this repository's |

Adding one must cost a probe plug-in and, at most, one `xs:alternative` line in `cuems-utils` —
`etc-cuems-first-install.md` §8.4 measured roughly twenty sites across four repositories per class
today, which is the cost this design exists to remove.
