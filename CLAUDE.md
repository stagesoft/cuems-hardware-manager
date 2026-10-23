<!-- SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# cuems-hardware-manager

Part of the **CUEMS** ecosystem — see the [`cuems-RELATIONS`](https://github.com/stagesoft/cuems-RELATIONS) repo for the system index, architecture diagram, and protocol/port map.

**Governance:** [`.specify/memory/constitution.md`](.specify/memory/constitution.md) (v1.1.0, amended 2026-10-23). Where this file and the constitution disagree, the constitution governs. Fix this file.

## Role

The CUEMS **hardware manager** owns the chain *real hardware availability → digital twin → node promotion → system total capabilities → operator agreement → system setup*. It is a core component that runs on every host, not a provisioning tool. It ships two systemd units from this package:

- **`cuems-hardware-node`** runs on every host (`PartOf=cuems-node.target`). It probes the attached hardware: video connectors and sinks, audio devices, DMX interfaces and network displays. It keeps the per-node **digital twin** and is the **sole writer** of `/etc/cuems/hardware_outputs.xml`, whose schema `cuems-utils` owns. It serves the twin to the controller, and applies its share of the operator's setup.
- **`cuems-hardware-controller`** runs on the controller (`PartOf=cuems-controller.target`). It combines every adopted node's twin into the cluster's capabilities, holds the operator's agreement, and sends each node its share.

Stages 1–5 only observe and record. **Only stage 6 (setup) changes a box**, only from an agreement the operator made, and **never while a show is loaded**: it refuses with a reason and never stops playback. Neither unit is a dependency of playback. Python 3.11, import package `cuemshardwaremanager`, shared venv `/usr/lib/cuems/`. Both units run as `cuems`, never root. Setup's privileged effects run only in root oneshot units shipped here, which the daemon starts through a sudoers rule naming the exact units (constitution VIII, D-14). `cuems-admin` is for humans only.

**Not this repository's job:**
- cue-time control (`cuems-engine`, the players);
- network configuration, node discovery, adoption or identity (`cuems-nodeconf`);
- projector or node power and brightness (`cuems-power-bridge`);
- writing `settings.xml` (`cuems-init-node`);
- owning any schema (`cuems-utils`);
- DRM master (`cuems-videocomposer`).

**Taking over hardware scripts from `cuems-common`.** That package is being stripped of non-essential responsibilities, so the hardware machinery it sheds moves here, each piece together with the feature that replaces it. Already decided: `cuems-generate-display-conf`, `cuems-ola-profile`, `jack-alsa-bridges.service`, `cuems-gpu-pin`. The full list is [`specs/planning/06-machinery-inventory.md`](specs/planning/06-machinery-inventory.md).

## Status

Design phase; **no code yet**. The pickle-over-TCP prototype `CuemsHwDiscovery.py` was removed on 2026-10-23 (task T004 of the node twin feature). It was never an empty placeholder: it sat at `src/cuemshardwaremanager/` with its full content until then. It stays in history at `b09b8cc` and `82efbd9`, and serves only as a record of *what* was probed. New code builds on the siblings' `feat/xml-refactor` interfaces, never on it. Start from [`specs/planning/README.md`](specs/planning/README.md). The first feature is `cuems-hw-mgr probe --json` over a `CuemsHardwareNode` class: the complete twin, read-only, no file written and nothing sent to the controller. Its draft is in [`specs/planning/00-runnable-flow.md`](specs/planning/00-runnable-flow.md) §4.

## Working rules

- **Identity is physical**, never enumeration order. A port is keyed by GPU PCI path + connector, by the video connector for HDMI audio, by USB serial or port path, or by the DMX interface's serial. A node is keyed by `uuid`. Port ids are load-bearing, because projects reference outputs as `<node uuid>_<output id>`.
- **Upstream changes go through `specs/upstream-reports/`.** That covers the VC contract, `cuems-utils` schemas (public `ConfigManager`/`NodeIndex` paths only), `network_map.xml` and `power-bridge.conf`. Never use a local workaround or a private copy.
- **One source per fact.** A hardware fact held in two writable places is a defect to remove.
- **Re-measure before citing a coordinate**, on the branch that is releasing. In comments, name a document or a behaviour, never a feature number.
- **Commits:** Conventional Commits, DCO sign-off, GPG-signed as `Adrià Masip <adria@stagelab.coop>` with key `B25EB0EDCB9F13C2`, the same as the siblings (set in this repo's local git config). On "gpg failed to sign", retry; never `--no-gpg-sign`.

## Field notes / gotchas

- **The videocomposer plans to generate `display.conf` itself.** Its "Phase A" comment is in `DRMBackend.cpp` on `rc_1`, and it collides with our renderer. Agree the split with the VC team before either side builds it (06 finding 10).
- **`cuems-generate-display-conf` reads `canvas_region` as pixels.** The schema defines it as normalized `[0,1]` floats, so a valid `0.5` raises in the VC's `ExecStartPre` (06 finding 3).
- **A `hw_discovery` chain already exists and nothing answers it.** It runs editor → controller engine → `/tmp/hwdiscovery.ipc`. Reuse it or retire it; don't build a second one (06 finding 2).
- **OLA:** `libola` starts a rogue `olad` whenever `:9010` is empty. Pause live dmxplayers (SIGSTOP) around any `olad` restart. Port patches are keyed by interface serial and saved only on a clean shutdown (06 finding 13).
