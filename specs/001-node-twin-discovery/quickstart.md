<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Quickstart — validating the node twin probe

Shapes are defined in [`data-model.md`](data-model.md) and [`contracts/`](contracts/); this guide only says how to prove the feature works.

## 1. In CI or on a workstation (no hardware)

Prerequisites: Python 3.11, `pytest`, `jsonschema`, and `cuems-utils` from its `feat/xml-refactor` checkout (installed editable into a dev venv, never into `/usr/lib/cuems`).

```sh
python3.11 -m venv .venv && . .venv/bin/activate
pip install -e ../cuems-utils -e '.[test]'
pytest                      # the whole suite must pass before and after any change
```

What the suite must show, and where:

| Proves | Test area | Spec |
|---|---|---|
| Expected twin per host model, byte for byte; two runs identical | `tests/fixtures/<model>/expected.json` vs the probe | US1, SC-001, SC-003 |
| Output validates against `contracts/probe-output.schema.json` | contract tests | FR-028 |
| Ids survive DRM/ALSA renumbering, pipe reassignment, re-plug and OLA alias reordering | identity property tests | US2, FR-011, SC-002 |
| Two nodes, identical serial-less DMX on the same socket: distinct (uuid, port_id) | identity tests | FR-010a |
| No `olad` spawned, with `:9010` empty and when it empties between check and connect; no subprocess, device open, bind or file write anywhere | safety harness | US3, FR-020, FR-021, SC-004 |
| Each source removed in turn: the fallback, report entry, log line, exit `3` | degraded-mode tests | US4, SC-005 |
| Legacy continuity, `canvas_region` hazard on `0.0`/`0.5`, `display.conf` provenance | report tests | US5, FR-032 to FR-034 |
| Mutating authored files leaves `twin` byte-identical | provenance guard | FR-008 |
| A test-only class appears by registering one probe | plug-in test | SC-009 |

## 2. On a real host (hardware-verification ledger)

Run over ssh as `cuems-admin`, with no sudo and without installing anything into the shared venv. Every source is readable this way (research, "Field measurements"). The exception is the VC socket, which needs group `cuems`, so video reports degraded with `permission` while the VC serves the contract:

```sh
env PYTHONPATH=/path/to/checkout/src \
  /usr/lib/cuems/bin/python -m cuemshardwaremanager probe --json > /tmp/twin.json
echo "exit=$?"
```

Check, and record each item in `specs/001-node-twin-discovery/hardware-verification.md`:

Checks marked ⚠ change service state. On the production-testing machines, which are reached read-only, they run only with the maintainer's explicit approval for that machine; otherwise the ledger records "not verified".

1. **Exit code.** `0` with the VC, OLA and audio all up. This needs a v1 VC, and none is deployed as of 2026-10-23, so until then expect `3` with video from `drm_sysfs`, and record the `0` case as "not verified: no v1 VC deployed". ⚠ Then stop the VC (only when no show is loaded) and run again: expect `3`, `report.sources.video == "drm_sysfs"`, and one `WARNING degraded` line.
2. **Every connector, audio device and DMX interface is listed.** Compare with the host's `cuems-fleet` record: all four audio kinds where present (HDMI, USB DSP, multichannel card, main L/R).
3. **Ids are stable.** ⚠ Reboot and run again: `jq -S .twin` is identical. Re-plug a USB DSP or DMX dongle into the same socket: the same.
4. **No rogue `olad`.** ⚠ Stop `olad` (with dmxplayers SIGSTOPped, per the OLA field note), run the probe, then check that `pgrep -u cuems olad` is empty.
5. **Show-safe.** Load a show and run the probe during playback: `report.show_lock.active == true`, no visible hitch, and no xrun in the `jackd-cuems` journal. Record N97 explicitly (SC-007).
6. **Twice in a row** gives byte-identical output (`cmp`).
7. **Timing.** `time` the full run: under 5 s with every source up (SC-006).

## 3. Capturing a fixture set

This happens only at the planned stop (task T073), on the maintainer's specific request. It uses the `dev/` procedure (`dev/README.md`): ssh as `cuems-admin`, no sudo, the script on stdin. Nothing is copied, installed, written or restarted on the host, and raw serials exist only in the pipe:

```sh
H=cuems-admin@<host>; S=dev/scripts/capture-readonly.sh; K=~/.ssh/cuems-org
ssh -i $K $H 'bash -s -- manifest' < $S > /tmp/fx-manifest.txt
ssh -i $K $H 'bash -s -- ola'      < $S > /tmp/fx-ola.json
ssh -i $K $H 'bash -s -- files'    < $S \
  | CUEMS_FIXTURE_SALT=<kept off-repo> cuems-hw-mgr fixture-import n97 \
      --ola /tmp/fx-ola.json --manifest /tmp/fx-manifest.txt
rm /tmp/fx-ola.json /tmp/fx-manifest.txt
```

Review `tests/fixtures/n97/expected.json` and check that no real serial survives (`grep -r` for the known serials) before committing.
