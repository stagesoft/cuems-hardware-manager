<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Implementation Plan: Node digital twin from discovery

**Branch**: `feat/hw-mgr-v0`. The spec branch is cut from the eventual merge, and work returns here afterwards.

**Date**: 2026-10-22

**Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-node-twin-discovery/spec.md`

## Summary

`cuems-hw-mgr probe --json` builds `CuemsHardwareNode`, the in-memory digital twin of one host, and prints it beside a report. The node is keyed by its uuid from `settings.xml`. The twin lists every video, audio and DMX device and port under physical, stable ids.

**How each class is read.** Probes are per-class plug-ins discovered as data. Each reads the host through a `HostView` (research R1), so the same code runs on `/` or on a recorded fixture.
- **Video** comes from the VC contract v1 when it answers, joined to DRM sysfs for the GPU's PCI path. Otherwise it comes from DRM sysfs, ported from `cuems-display-setup` with the size-0 EDID fix, and finally from `display.conf`.
- **Audio** comes from ALSA procfs/sysfs only, with no device opens. It covers all four kinds: HDMI, USB DSP/interface, multichannel card and main L/R. HDMI audio is keyed by its video connector, and its current PCM mapping is live state from ELD matching.
- **DMX** comes from OLA's Python RPC client behind a port check, so no `olad` can ever be spawned. When OLA is down, it comes from USB candidates keyed by serial.

**JACK.** It is not touched (D-11 pending), and `jack_exposure` is always `unknown`.

**The report** carries the sources, degradations, deferrals, show-lock mode, legacy `default_mappings.xml` continuity, the `canvas_region` generator hazard and `display.conf` provenance.

**Output.** It is deterministic: byte-identical across runs on an unchanged host. Exit `0`/`3`/`1` means built, degraded or could not run.

## Technical Context

| | |
|---|---|
| **Language/Version** | Python 3.11 (shared venv `/usr/lib/cuems/`, Debian bookworm) |
| **Primary Dependencies** | `cuemsutils`: `ConfigManager.node_uuid`, `show_lock_file`, `node_mappings`; public paths only. `pynng` 0.8.1 for the VC contract, already in the venv. `python3-ola` (OLA's Python client), a **declared system dependency** whether or not DMX hardware is present. If it is missing, that is an installation defect, reported degraded (R10). Standard library otherwise: `argparse`, `json`, `logging`, `pkgutil`, `hmac`. No `edid-decode`, `python-jack` or `ola_*` binaries |
| **Storage** | None. No file is written (FR-021) |
| **Testing** | `pytest`, `jsonschema` (contract validation), recorded fixture trees under `tests/fixtures/<host-model>/`, and a safety harness patching `subprocess`, `os.exec*`, `os.fork`, `socket.bind` and `/dev/` opens |
| **Target Platform** | CUEMS nodes and controllers, Linux x86-64: Intel N97/N100, i3-1215U, AMD Picasso FP530 |
| **Project Type** | Library (`cuemshardwaremanager`) plus a thin CLI (`cuems-hw-mgr`) |
| **Performance Goals** | Under 5 s per probe with every source up. Under 10 s total whatever a source does: VC 1 s per request, OLA connect 200 ms plus RPC 2 s, VC event drain ≤ 100 ms (SC-006) |
| **Constraints** | Never disturbs a show: no DRM master or DRM open, no JACK, no OLA writes, no device-node opens, no subprocesses, no writes. Show-lock mode suppresses re-reads. Runs as `cuems` and refuses root. Deterministic output |
| **Scale/Scope** | One host per run: ~1–3 GPUs, ≤ 8 connectors, ≤ 10 ALSA cards, ≤ 4 DMX interfaces. Three per-class probes plus the report steps |

There are no NEEDS CLARIFICATION items left. Research resolved every unknown, and the items it could not measure here are listed as re-measurements in tasks T001 to T003:
- the VC contract against `feat/contract-report`;
- `ConfigManager.node_mappings` without a project loaded;
- `python3-ola` on a node, and its import from the venv.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | How this feature satisfies it | Status |
|---|---|---|
| **I. Never disturb a show** | Read-only by construction. No DRM open, JACK, OLA writes, device opens, subprocesses or writes, enforced by a harness on every probe test (contracts/probe-plugin.md rule 3). One-shot VC read following the client rules; never polls `get_hardware` (R3). Show-lock mode suppresses re-reads (R11). The `olad` spawn is prevented by two layers (R10). Not a dependency of anything | PASS |
| **II. Observation vs intent; one writer** | `twin` holds discovered facts only (FR-008), with a provenance-guard test that mutates authored files. VC geometry is live and never persisted (FR-008b). Authored inputs reach `report` only. Writes nothing, so it is not a second writer of `hardware_outputs.xml` | PASS |
| **III. Physical, stable identity** | The `port_id` grammar (data-model §6) is built from PCI BDF, connector, USB serial or port path, and DMX serial. It excludes card and device numbers and aliases. Unique per node across directions, with `(uuid, port_id)` cluster addressing. Three-valued presence with mandatory reasons. Identity property tests | PASS |
| **IV. Consumes what it does not own** | `cuems-utils` through `ConfigManager` only (R2). VC contract v1 read-only, ignoring unknown fields. OLA through its own client. **One justified exception**: the `canvas_region` literal check reproduces `cuems-generate-display-conf`'s parser (R16) — see Complexity Tracking | PASS (justified) |
| **V. Own API is a contract** | No API in this feature (FR-025). The CLI output is versioned (`cuems-hw-twin/1`) and has a JSON Schema contract | N/A (CLI contract kept) |
| **VI. A class is data** | Probes are discovered from a package, ordered by declared `requires`. A test-only class is added through `register()` (SC-009) | PASS |
| **VII. Degraded is normal** | Every fallback has a named trigger, a report entry and one log line (R14). The deliberate JACK deferral is not degradation | PASS |
| **VIII. Least privilege** | Refuses root (R19). Constitution 1.1.0 (D-14) confines privileged effects to root apply oneshots started by exact unit name. 001 ships neither daemon nor oneshot, so nothing here needs privilege. Creates no file or socket. Fixtures pseudonymise EDID and USB serials with an off-repo salt (R15) | PASS |
| **Operating Constraints** | Bundles nothing another package ships (no OLA `.proto` copy; `pynng`/`cuemsutils` are declared, not vendored). Host verification runs through `dev/scripts/capture-readonly.sh` plus a local `probe --fixture`. Nothing is installed, copied or written on hosts, and the shared venv is never touched (R15, R18). SPDX headers everywhere. Comments name documents and behaviours, never feature numbers | PASS |
| **Testing gate** | Fixture-based CI, identity property tests, test-first for parsing and identity. Hardware ledger `hardware-verification.md`. **Blocking gate**: the feature is not done until *recorded* captures exist from all three host models. They are taken read-only over ssh from the production-testing machines, on a specific request at a planned implementation stop (T073). Only host *behaviour* checks may read "not verified" in the ledger | PASS, with a blocking gate |

**Post-design re-check (after Phase 1):** unchanged. The design introduces no new principle exposure; the only exception is the R16 check, still justified below.

## Project Structure

### Documentation (this feature)

```text
specs/001-node-twin-discovery/
├── spec.md
├── plan.md                    # this file
├── research.md                # Phase 0
├── data-model.md              # Phase 1
├── quickstart.md              # Phase 1
├── contracts/
│   ├── cli.md                 # cuems-hw-mgr probe, fixture capture, exit codes
│   ├── probe-output.schema.json   # the twin's draft shape (for cuems-utils' structure pass)
│   └── probe-plugin.md        # the per-class Probe interface
├── hardware-verification.md   # ledger (created during implementation)
├── checklists/requirements.md
└── tasks.md                   # /speckit-tasks
```

### Source Code (repository root)

```text
pyproject.toml                         # setuptools, src layout, console script cuems-hw-mgr
src/cuemshardwaremanager/
├── __init__.py
├── __main__.py                        # python -m cuemshardwaremanager
├── cli.py                             # argparse: probe [--json], fixture-import <model>; exit codes
├── node.py                            # CuemsHardwareNode: runs probes, uniqueness check, serialise
├── model.py                           # Device, Port, Sink, identity/observed, Report types
├── identity.py                        # physical-key helpers and port_id grammar (data-model §6)
├── serialise.py                       # deterministic JSON (R13)
├── hostview.py                        # HostView: rooted fs reads, port check, show lock, euid
├── sources/
│   ├── vc_contract.py                 # pynng one-shot client (R3)
│   ├── drm_sysfs.py                   # ported from cuems-display-setup (R5)
│   ├── edid.py                        # base-block decoder (R6)
│   ├── alsa_procfs.py                 # cards, pcm info, stream0, ELD, codec pins (R7, R8)
│   ├── usb_sysfs.py                   # USB identity and port paths (R7, R9)
│   └── ola_rpc.py                     # port check + ola.OlaClient read-only (R10)
├── probes/                            # discovered as data (R12); each module exposes PROBE
│   ├── video.py
│   ├── audio.py                       # requires = ("video",)
│   └── dmx.py
├── report/
│   ├── continuity.py                  # default_mappings.xml via ConfigManager (R2)
│   ├── canvas_hazard.py               # generator-parser reproduction (R16)
│   └── diagnostics.py                 # zero connectors, weak identity, unresolved identity
└── fixture_import.py                  # workstation half of capture: pseudonymise, write fixtures (R15)

dev/                                   # not shipped; read-only host inspection (dev/README.md)
├── scripts/inspect-readonly*.sh       # access and detail inspections
├── scripts/capture-readonly.sh        # host half of capture (R15)
└── data/                              # inspection results

tests/
├── conftest.py                        # fixture loader, safety harness (forbidden-act patches)
├── fixtures/
│   ├── constructed/                   # hand-built minimal trees for unit tests
│   ├── n97/  n100/  i3-1215u/  fp530/ # recorded captures (gate: real hosts)
├── unit/                              # edid, identity grammar, serialise, each source parser
├── identity/                          # property tests: renumbering, re-plug, pipe swap, alias reorder
├── contract/                          # output vs probe-output.schema.json; VC replies vs contract v1
├── safety/                            # no olad spawn (both layers), no forbidden acts, show-lock
├── degraded/                          # each source removed in turn
└── report/                            # continuity, canvas hazard, display.conf provenance, provenance guard
```

**Structure decision.** A single Python project, `src/` layout. The outdated prototype `src/cuemshardwaremanager/CuemsHwDiscovery.py` is removed (T004, done). Module names follow behaviours (`probes/`, `sources/`, `report/`) rather than the later stages, so the persistence and API features can add `store/` and `api/` beside them (01 §3.1).

## Delivery notes for `/speckit-tasks`

- **T001 to T003, re-measure before coding.**
  - The VC contract text and mock replies on `feat/contract-report`.
  - `ConfigManager.node_mappings` resolving `default_mappings.xml` with no project loaded.
  - The OLA fork's `python/ola/OlaClient.py` (no spawn path). `python3-ola`'s location and its import from the venv are already measured (research, "Field measurements").
  - Any mismatch becomes a research amendment or an upstream report, never a workaround.
- **Test-first** for `edid.py`, `identity.py`, every `sources/` parser and the canvas hazard.
- **Hardware gate**:
  - recorded captures from N97/N100, i3-1215U and FP530;
  - ledger entries for the seven host checks in quickstart §2, SC-007 included;
  - a written "not verified" where host access was missing.
- **At completion**:
  - `CLAUDE.md` "Field notes / gotchas" updated as FR-040 lists, and `CLAUDE.md` "Status" updated (code exists, prototype gone);
  - a D-11 note recording that 001 does not read JACK;
  - `04-open-decisions.md` D-13 marked delivered.
- **Upstream, prepared alongside and not blocking.** A draft in `specs/upstream-reports/` for `cuems-utils`' structure pass, built from `contracts/probe-output.schema.json`. It also notes the stale two-writer annotation in `hardware_outputs.xsd`.

## Complexity Tracking

| Departure | Why needed | Simpler alternative rejected because |
|---|---|---|
| `report/canvas_hazard.py` reads `default_mappings.xml` text outside `ConfigManager` (R16) | The hazard is in `cuems-generate-display-conf`'s parser, which calls `int()` on the literal text. `cuems-utils` yields floats, which lose the literal, so `0.0` and `1.0` (in the shipped defaults) would be missed. The check reproduces a program this repository owns (06 C1). It is not a copy of the schema, and it feeds only `report` | Inferring from floats misses integral decimals. Asking `cuems-utils` for literals adds API for a defect that the video setup feature removes, once the generator stops reading pixels |
