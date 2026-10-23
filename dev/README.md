<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# `dev/`: read-only inspection of production-testing machines

These are working tools for measuring real hosts before and during implementation. They are not shipped in the package.

## Rules

Every script here:
- runs over ssh as **`cuems-admin`** with the org key, and **without sudo**;
- writes **nothing** on the host;
- opens **no device node**;
- starts, stops and signals **no service**;
- prints **no serials and no EDID contents**: only paths, sizes, flags and errors.

Run one only when the maintainer asks for it. The same procedure is used for the fixture capture at the hardware gate (`specs/001-node-twin-discovery/tasks.md`, task T073).

## Procedure

From the repository root:

```sh
ssh -i ~/.ssh/cuems-org cuems-admin@<host> 'bash -s' \
  < dev/scripts/<script>.sh > dev/data/<stem>-<host>.txt
```

When the information needed changes, edit the script here (or add a new one beside it) instead of writing a one-off command, so later runs stay comparable.

## Scripts

| Script | Stem | Measures |
|---|---|---|
| `scripts/inspect-readonly.sh` | `inspect` | Whether every source `cuems-hw-mgr probe` reads is readable as `cuems-admin`: DRM sysfs, the VC sockets (permission only), the `display.conf` candidates, the show lock, ALSA procfs/sysfs, `/etc/asound.conf`, `/etc/default/jack`, USB sysfs, OLA `:9010` and `/etc/ola`, JACK command lines, `/etc/cuems`, and the shared venv's modules |
| `scripts/inspect-readonly-2.sh` | `inspect2` | Follow-up detail: DMI host model; show-lock age and running services; package versions; whether `OlaClient.py` has a spawn path; valid ELD entries; HDMI codec pin/device structure; PCM ids; `asound.conf` structure; JACK arguments; USB devices without serial and their drivers; `ola-port.conf` key shapes (serials masked); `/etc/cuems` ownership |

## Data

| File | Host | Date | Result |
|---|---|---|---|
| `data/inspect-10.16.10.2.txt` | 10.16.10.2 | 2026-10-23 | 100 readable, 0 failed |
| `data/inspect-10.16.10.3.txt` | 10.16.10.3 | 2026-10-23 | 93 readable, 0 failed |

`inspect-readonly-2.sh` produced no output on its first attempt (2026-10-23). The cause is unknown and may be the remote connection; it is to be retried when needed. Since then, the scan of the videocomposer binary has been removed and the `systemctl` calls are bounded by `timeout 5`.

The findings are folded into `specs/001-node-twin-discovery/research.md`, "Field measurements, 2026-10-23".
