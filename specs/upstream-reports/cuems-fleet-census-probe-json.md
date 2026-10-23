<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Request to `cuems-fleet`: record node hardware from `cuems-hw-mgr probe --json`

> **Status (2026-10-23): DRAFT, not sent.** Send it when `cuems-hw-mgr probe --json` has landed, with recorded fixtures for every host model (`specs/001-node-twin-discovery/`, task T073). It closes when `bin/census` records the probe's output and the hand-typed hardware fields are retired or derived from it.

**From**: `cuems-hardware-manager`, the node digital twin feature (`specs/001-node-twin-discovery/`).

**For**: `cuems-fleet` (`main`, measured at `ec478ee` in `specs/planning/06-machinery-inventory.md`).

**Why**: one source per fact (06 finding 12). Today `cuems-fleet` types each node's hardware twin by hand:
- `inventory/nodes.yaml`: the `hardware:` and `outputs:` fields;
- `inventory/devices.yaml`: projectors and DMX interfaces;
- `inventory/dmx.yaml`: the OLA patch key.

`cuems-hw-mgr probe --json` now produces that twin from the host itself.

## 1. What is asked

1. **`bin/census` calls the probe** on each node, after its existing `--require-idle` check:

   ```
   sudo -u cuems /usr/lib/cuems/bin/cuems-hw-mgr probe --json
   ```

   Until the Debian package lands, run it from a checkout with `PYTHONPATH`, as in `specs/001-node-twin-discovery/quickstart.md` §2. The probe is read-only: it writes no file, opens no listening socket and spawns no process. It is safe during a show, but `census`' idle rule may stay.
2. **Record the `twin` object** as the node's hardware record, keyed by `twin.uuid`, which is the join key with `network_map.xml`.
3. **Derive or retire the hand-typed fields** (`hardware:`, `outputs:`, the hardware rows of `devices.yaml`) from the recorded twin. Keep in `cuems-fleet` only what the twin does not describe: site, rack, cabling notes and fixtures.
4. **Use the exit status**:

   | Exit | Meaning | What `census` does |
   |---|---|---|
   | `0` | full twin | record it |
   | `3` | twin with degraded sources | record it, flagged, and keep `report.degraded` |
   | `1` | could not run | record the failure; stdout carries `{format, error}` |

## 2. The contract `cuems-fleet` consumes

- **Shape.** `specs/001-node-twin-discovery/contracts/probe-output.schema.json`, format `cuems-hw-twin/1`. Clients must ignore fields they do not know. A change of meaning bumps the format.
- **Addressing.** A port is `(twin.uuid, port.identity.port_id)`. A `port_id` is unique per node only.
- **Field states.**
  - Only `identity` and `persisted` fields describe the hardware.
  - `live` fields (presence, the current mode, the OLA patch, the VC's driven geometry) describe this moment. Do not treat a change in them as hardware drift.
  - `report` is per-run and never part of the hardware record.
- **JACK.** `jack_exposure` is always `unknown` in format `/1`, pending the team's agreement on JACK relations (D-11).

## 3. Privacy

EDID serials and USB serials are personal-ish data (constitution Principle VIII). The probe's output carries them in full. `cuems-fleet` already holds monitor EDID serials in `nodes.yaml`, so this request moves them from hand-typed to probed and does not widen what is held. The repository's access rules apply unchanged. The test fixtures in `cuems-hardware-manager` are pseudonymised; the live output is not.

## 4. What `cuems-hardware-manager` does in return

- It keeps `cuems-hw-twin/1` stable: additive changes only within `/1`.
- It treats `cuems-fleet`'s per-site records as the cross-check for its recorded fixtures (FR-036). It reads them and never copies them.
