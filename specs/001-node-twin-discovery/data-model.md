<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Data model — Node digital twin from discovery

This is the in-memory model behind `cuems-hw-mgr probe --json`. The wire shape is `contracts/probe-output.schema.json`, and this document explains it. Field states:
- **P** is persisted state: it changes only when hardware or service configuration changes.
- **L** is live state: it is refreshed and never written by the persistence feature (FR-008a).

`identity` fields carry no state mark, because they *are* the key.

## 1. Probe output (top level)

| Field | Type | Notes |
|---|---|---|
| `format` | string | `"cuems-hw-twin/1"`. Additive changes keep `/1`; a change of meaning bumps it |
| `twin` | Node | Purely discovered (FR-008). It is the part a later feature persists |
| `report` | Report | Per-run metadata and findings about operator-authored inputs. Never persisted (FR-026) |

On "could not run" the document is `{format, error: {reason, detail}}` and has no `twin` or `report`.

## 2. Node — `CuemsHardwareNode`

| Field | Type | Notes |
|---|---|---|
| `uuid` | string | From `settings.xml` through `ConfigManager.node_uuid`. The only node attribute (FR-002) |
| `devices` | Device[] | Sorted by `(identity.class, identity.device_key)` |

**Addressing rule (FR-010a).** A physical port is addressed cluster-wide by `(twin.uuid, port.identity.port_id)`. Projects write that pair as `<uuid>_<port_id>`. A `port_id` is unique within a node and is **not** unique across nodes. It never embeds the uuid.

## 3. Device

**`identity`**

| Field | Type | Notes |
|---|---|---|
| `class` | string | The registered probe's class name: `video`, `audio`, `dmx`, … (data, F6) |
| `device_key` | string | Physical key (§6) |
| `transport` | enum | `pci` · `usb` · `network` · `virtual` |
| `key_strength` | enum | `serial` · `port_path` · `bus_address` · `service_name` (FR-012). `port_path` and `service_name` count as **weak** |

**`observed`**

| Field | State | Notes |
|---|---|---|
| `vendor`, `model`, `serial` | P | Strings; `""` when the source has none, `null` when unknown |
| `vendor_id`, `product_id` | P | Hex strings (PCI or USB) |
| `driver` | P | The kernel driver bound, e.g. `i915`, `amdgpu`, `snd_usb_audio`, `ftdi_sio` |
| `kind` | P | Class-specific category. Audio: `hdmi` · `usb` · `onboard` · `pci_multichannel` (02 §2 ruling) |
| `presence` | L | Device-level presence |
| `source` | L | The probe source that observed it (§7) |
| `capabilities` | P | Class-specific. Video GPU: `vc_caps` (the VC `get_caps` tokens, FR-008b), `modes_partial` |
| `live` | L | Class-specific live state. Video GPU: `config_source`, `driven_geometry` (the canvas, regions, blends and pacing `get_state` reports; FR-008b). DMX: `ola_plugin`, `ola_running`, and `ola_patch` (OLA's current universe ↔ port patch from `FetchUniverses`; operator intent held by a service, so it is live only and never persisted; FR-008) |
| `ports_known` | L | `false` when ports cannot be enumerated from the answering source (DMX with OLA down) |
| `ports` | Port[] | Sorted by `port_id` |

## 4. Port

**`identity`**

| Field | Type | Notes |
|---|---|---|
| `port_id` | string | §6 grammar. Unique per node across classes and directions (FR-010) |
| `direction` | enum | `output` · `input` |
| `key` | object | The physical key parts the id was built from, e.g. `{gpu: "pci-0000:00:02.0", connector: "HDMI-A-1"}` |

**`observed`**

| Field | State | Notes |
|---|---|---|
| `presence` | L | `present` · `absent` · `unknown` (FR-013, FR-014) |
| `presence_reason` | L | Required when `unknown`, e.g. `vc_connection_unknown`, `permission`, `not_consulted` |
| `channels` | P | Integer or `null` |
| `capabilities` | P | Video: `modes[] {id, width, height, hz, interlaced}` and `preferred`. HDMI audio: `max_channels` from the ELD. DMX: `rdm` |
| `sink` | P | Optional `{make, model, serial}` (EDID; FR-005), or `{"state": "unknown"}` |
| `live` | L | Video: `current` (a mode `id` or `null`, meaning not driven). HDMI audio: `alsa_pcm` (`{card_id, device}` or `unknown`, R8) and `multi_hdmi_slot` (from `/etc/asound.conf`, R7: an index, `null`, `{state: not_configured}` when the file is absent, or `{state: unknown}`). Audio: `hw_params` when the stream is open. All audio: `jack_exposure` |
| `source` | L | §7 |

**Audio `jack_exposure`**, every audio port, in 001: `{"state": "unknown", "reason": "pending JACK relations agreement"}` (FR-018a). The field keeps its place in the shape.

## 5. Report

| Field | Notes |
|---|---|
| `sources` | `{<class>: <source that answered>}` (§7) |
| `degraded` | `[{class, source, reason, fallback}]`, one entry per log line (FR-030) |
| `deferred` | `[{class, field, reason}]`, e.g. audio `jack_exposure`. Not degradation (FR-018a) |
| `show_lock` | `{active: bool, skipped: [{class, what}]}` (FR-024) |
| `display_conf` | Only when the VC did not answer: `{path_read: <path> \| null}` (FR-034) |
| `diagnostics` | `[{code, class, subject, detail}]`. Codes: `zero_video_connectors`, `canvas_region_generator_hazard`, `identity_unresolved`, `weak_identity`, `vc_state_unstable`, `mappings_invalid`, `sink_ambiguous` |
| `continuity` | `{available: bool, reason?, matched: [...], unmatched_entries: [...], unmatched_ports: [...]}` (FR-032) |

**A continuity record** holds `{port_id?, class, direction, legacy_id, legacy_name, legacy_reference}`, where `legacy_reference` is `"<uuid>_<legacy_name>"`. Audio entries are always in `unmatched_entries`, with the reason `pending JACK relations agreement`.

## 6. Physical keys and the `port_id` grammar

```
port_id    = class ":" direction ":" device_key [ ":" local ]
device_key = "pci-" BDF                     ; GPU or PCI audio function,  key_strength=bus_address
           | "usb-" VID ":" PID ":serial-" S ; USB with serial,             key_strength=serial
           | "usb-" VID ":" PID ":path-" P   ; USB without serial (devpath), key_strength=port_path
           | "serial-" S                     ; DMX interface (OLA or USB),   key_strength=serial
           | "ola-" UID                      ; OLA device with no serial,    key_strength=service_name
local      = connector                       ; video and HDMI audio: "HDMI-A-1"
           | "pcm" N                         ; PCI or USB analog: the PCM device index fixed by codec/driver
           | "port" N                        ; DMX: OLA's port index within the device
```

Examples:
- video: `video:output:pci-0000:00:02.0:HDMI-A-1`
- HDMI audio: `audio:output:pci-0000:00:02.0:HDMI-A-1`. This is keyed by the **video** device's PCI path, not the HDA function's, so it follows the connector (FR-009)
- main L/R: `audio:output:pci-0000:00:1f.3:pcm0`
- USB DSP input: `audio:input:usb-1397:0509:serial-PSEUDO-3fa9c1e2d0:pcm0`
- DMX: `dmx:output:serial-PSEUDO-9be01c44aa:port1`

These never appear in a key: DRM minor (`cardN`), ALSA card index or name, ALSA device numbers for HDMI, USB bus or device numbers, and OLA aliases.

HDMI audio ports belong to an **audio-class device that the audio probe emits itself**, with `device_key = pci-<GPU BDF>`. It is never added to the video probe's GPU device (contracts/probe-plugin.md: a probe never touches another probe's devices). Devices are unique by `(class, device_key)`, so the video GPU device and its HDMI-audio device share a key without colliding. The node's single uniqueness check spans every port of every device.

## 7. Sources

| Class | Ordered sources | `source` values |
|---|---|---|
| video | VC contract → DRM sysfs → `display.conf` | `vc_contract_v1`, `drm_sysfs`, `display_conf` |
| audio | ALSA procfs/sysfs (+ ELD) | `alsa_procfs` |
| dmx | OLA RPC → USB enumeration | `ola_rpc`, `usb_sysfs` |

## 8. Validation rules

- **Uniqueness.** `port_id` is unique across `twin.devices[*].ports[*]`. A duplicate is an internal error ("could not run"), never a silent merge.
- **Unknown presence needs a reason.** Every `presence: unknown` carries `presence_reason`.
- **When `absent` is allowed.** Only where the source enumerates the port and says nothing is attached, i.e. DRM `disconnected` or VC `disconnected` (FR-014).
- **Authored values stay out.** No `observed` field comes from an operator-authored file (FR-008). The guard is a test that runs the probe with `default_mappings.xml` and `/etc/cuems/display.conf` mutated, and asserts that `twin` is byte-identical.
- **Weak keys are flagged.** `key_strength` in `{port_path, service_name}` adds the device to the report as `weak_identity` (FR-012).

## 9. State transitions

None within a run. Presence across runs, revision and retention belong to the persistence feature, which will use the P/L marking above: rewrite only when P changes (`cuems-nodeconf`'s signature-compare mechanics), and refresh L on events.
