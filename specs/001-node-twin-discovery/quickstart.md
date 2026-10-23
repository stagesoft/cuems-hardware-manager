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

On the production-testing machines, every check runs **against `dev/scripts/capture-readonly.sh`**. That is the same `dev/` procedure as §3: ssh as `cuems-admin`, no sudo, the script on stdin, nothing copied, installed or written on the host. The probe itself runs **on the workstation**, against the captured tree, imported into a scratch directory rather than `tests/fixtures/`:

```sh
H=cuems-admin@<host>; S=dev/scripts/capture-readonly.sh; K=~/.ssh/cuems-org; L=/tmp/ledger-<host>
ssh -i $K $H 'bash -s -- manifest' < $S > $L.manifest
ssh -i $K $H 'bash -s -- ola'      < $S > $L.ola.json
time ssh -i $K $H 'bash -s -- files' < $S \
  | CUEMS_FIXTURE_SALT=<kept off-repo> cuems-hw-mgr fixture-import <model> --out $L \
      --ola $L.ola.json --manifest $L.manifest
cuems-hw-mgr probe --json --fixture $L > $L.twin.json; echo "exit=$?"
```

Record each item in `specs/001-node-twin-discovery/hardware-verification.md`. Checks marked ⚠ change machine state. On the production-testing machines they run only with the maintainer's explicit approval for that machine; otherwise the ledger records "not verified".

1. **Exit code.** With OLA and audio up, expect `3` with `report.sources.video == "drm_sysfs"`. `0` needs a v1 VC, and none is deployed as of 2026-10-23, so record the `0` case as "not verified: no v1 VC deployed". Skip any "stop the VC" variant until then: today it gives the same result as not stopping it.
2. **Every connector, audio device and DMX interface is listed.** Compare `$L.twin.json` with the host's `cuems-fleet` record: all four audio kinds where present (HDMI, USB DSP, multichannel card, main L/R).
3. **Ids are stable.** ⚠ Reboot, capture again, and compare: `jq -S .twin` is identical. Re-plug a USB DSP or DMX dongle into the same socket, capture again: the same.
4. **No rogue `olad`.** ⚠ Stop `olad` (with dmxplayers SIGSTOPped, per the OLA field note), run the `ola` mode, then check `ssh $H pgrep -u cuems olad` is empty. The `ola` mode carries the same two-layer guard as the probe (R10).
5. **Show-safe.** ⚠ Load a show, and capture during playback: `report.show_lock.active == true`, no visible hitch, and no xrun in the `jackd-cuems` journal. Record N97 explicitly (SC-007).
6. **Twice in a row.** Two consecutive captures of an unchanged host give byte-identical `$L.twin.json` (`cmp`).
7. **Timing.** The `time` of the `files` capture bounds the host-side reads the probe would make, and the local `probe --fixture` time bounds its processing. Record both. Their sum is under 5 s (SC-006). This is a proxy, not an on-host probe run, and the ledger says so.

Afterwards, delete `$L*`: it holds the twin of a production host.

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
