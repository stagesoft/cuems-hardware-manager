<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Contract — `cuems-hw-mgr` command line (v1)

`cuems-fleet` `census` and operators consume this. Only the `probe` JSON output and the exit codes are a contract; the human text is not.

## `cuems-hw-mgr probe [--json]`

Reads the host and prints the node twin. It is read-only: it writes no file, opens no listening socket and starts no process (FR-021, FR-025).

| Flag | Effect |
|---|---|
| `--json` | Print the document defined by [`probe-output.schema.json`](probe-output.schema.json) on stdout |
| *(none)* | Print a human summary, which is not a contract |

| Exit | Meaning | stdout with `--json` |
|---|---|---|
| `0` | Twin built; every consulted source answered | `{format, twin, report}` |
| `3` | Twin built with degraded sources (`report.degraded` is non-empty) | `{format, twin, report}` |
| `1` | Could not run: run as root, no node uuid, node not provisioned, internal error | `{format, error: {reason, detail}}` |
| `2` | Usage error | nothing (argparse prints usage on stderr) |

**What does and does not make a run degraded:**
- `report.deferred` entries, such as audio `jack_exposure` (FR-018a), never make a run degraded.
- Show-lock mode on its own is not degraded. A re-read it skipped is reported in `report.show_lock.skipped`, and it is degraded only if it left a fact `unknown`.

**stderr** carries log lines only, one per degradation:

```
WARNING degraded class=<class> source=<source> reason=<reason> fallback=<fallback>
```

**Environment:**
- `CUEMS_CONF_PATH` is honoured through `cuems-utils` (where `settings.xml` is read from).
- The `HostView` root is `/` and is not configurable on the command line.

## Fixture capture (FR-037, research R15)

A capture has two halves. The host side reads; the workstation side writes.

**On the host: `dev/scripts/capture-readonly.sh`**, run as `cuems-admin` with no sudo, the same way as the `dev/` inspections:

```sh
ssh -i ~/.ssh/cuems-org cuems-admin@<host> 'bash -s -- files'    < dev/scripts/capture-readonly.sh
ssh -i ~/.ssh/cuems-org cuems-admin@<host> 'bash -s -- ola'      < dev/scripts/capture-readonly.sh
ssh -i ~/.ssh/cuems-org cuems-admin@<host> 'bash -s -- manifest' < dev/scripts/capture-readonly.sh
```

| Mode | stdout |
|---|---|
| `files` | uncompressed tar under `root/`, holding the probe's source paths, with sysfs symlinks kept |
| `ola` | JSON `{plugins, devices, universes}`, or `{"unavailable": <reason>}` |
| `manifest` | `key=value` lines: DMI vendor, product and board, the date, `cuems-*` and OLA package versions, and the show-lock state |

It writes nothing, opens no device node, spawns no `olad` (R10's two layers) and needs no checkout.

**On the workstation: `cuems-hw-mgr fixture-import <model> --ola <file> --manifest <file>`**, which reads the `files` tar on stdin:
- It requires `CUEMS_FIXTURE_SALT`, which is never committed, and pseudonymises EDID and USB serials, OLA unique ids and `ola-port.conf` keys **before writing**.
- It writes `tests/fixtures/<model>/{MANIFEST, root/, services/ola/*.json}`, then runs `probe` on the tree to write `expected.json` for hand review.
- Exit codes: `0` imported; `1` refused (no salt, target not empty, a real serial survived pseudonymisation); `2` usage.

VC replies come from the VC's mock until a v1 VC is deployed (`services/vc/*.json`).

## Not provided by this feature

There is no API, no socket, and no answer on `/tmp/hwdiscovery.ipc` (FR-025, D-5). No file is written. Nothing is sent to the controller.
