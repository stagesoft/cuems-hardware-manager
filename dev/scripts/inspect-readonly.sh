#!/bin/bash
# SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run from the repository root, over ssh as cuems-admin, with no sudo:
#   ssh -i ~/.ssh/cuems-org cuems-admin@<host> 'bash -s' < dev/scripts/inspect-readonly.sh > dev/data/inspect-<host>.txt
# See dev/README.md.
# Read-only access check for cuems-hw-mgr probe sources, run as cuems-admin, no sudo.
# Writes nothing, opens no device node, prints no serials or EDID contents.
export LC_ALL=C
ok=0; ko=0
chk() { # chk <label> <path>: try an actual read, report size only
  if out=$(cat -- "$2" 2>&1 >/dev/null); then ok=$((ok+1)); printf 'OK   %-14s %s (%s bytes)\n' "$1" "$2" "$(wc -c <"$2" 2>/dev/null)";
  else ko=$((ko+1)); printf 'FAIL %-14s %s: %s\n' "$1" "$2" "${out##*: }"; fi; }
sec() { printf '\n== %s\n' "$1"; }

sec "identity"; id; hostname

sec "video: DRM sysfs"
for c in /sys/class/drm/card[0-9]; do
  [ -e "$c" ] || continue
  printf 'GPU %s -> %s\n' "$c" "$(readlink -f "$c/device")"
  chk drm-gpu "$c/device/vendor"; chk drm-gpu "$c/device/device"
done
for d in /sys/class/drm/card*-*; do
  [ -d "$d" ] || continue
  chk drm-status "$d/status"; chk drm-modes "$d/modes"; chk drm-edid "$d/edid"
done

sec "video: VC contract sockets (permission only, no connect)"
for s in /tmp/cuems-videocomposer.ipc /tmp/cuems-videocomposer-events.ipc; do
  if [ -S "$s" ]; then ls -l "$s"; [ -r "$s" ] && [ -w "$s" ] && echo "OK   vc-socket      $s usable" || { ko=$((ko+1)); echo "FAIL vc-socket      $s not usable by $(id -un)"; }
  else echo "--   vc-socket      $s absent (VC stopped?)"; fi
done

sec "video: display.conf candidates and show lock"
for f in /run/cuems/display.conf /etc/cuems/display.conf; do [ -e "$f" ] && chk display.conf "$f" || echo "--   display.conf   $f absent"; done
vcuser=$(systemctl show -p User --value cuems-videocomposer.service 2>/dev/null); echo "VC unit User=${vcuser:-?}"
[ -n "$vcuser" ] && x="$(getent passwd "$vcuser" | cut -d: -f6)/.config/cuems-videocomposer/display.conf" && { [ -e "$x" ] && chk display.conf "$x" || echo "--   display.conf   $x absent or unreachable"; }
[ -e /tmp/cuems.show.lock ] && echo "SHOW LOCK PRESENT" || echo "no show lock"

sec "audio: ALSA procfs/sysfs"
chk alsa /proc/asound/cards
for c in /proc/asound/card[0-9]*; do
  [ -d "$c" ] || continue
  n=${c##*card}; printf 'card%s -> %s\n' "$n" "$(readlink -f /sys/class/sound/card$n/device)"
  for f in "$c"/pcm*/info "$c"/stream* "$c"/eld#* "$c"/codec#*; do [ -e "$f" ] && chk alsa "$f"; done
  for f in "$c"/pcm*/sub0/hw_params; do [ -e "$f" ] && chk alsa-live "$f"; done
done
for f in /etc/asound.conf /etc/default/jack; do [ -e "$f" ] && chk alsa-conf "$f" || echo "--   alsa-conf      $f absent"; done

sec "usb"
for u in /sys/bus/usb/devices/*; do
  [ -e "$u/idVendor" ] || continue
  chk usb "$u/idVendor"; chk usb "$u/idProduct"; chk usb "$u/devpath"
  [ -e "$u/serial" ] && chk usb-serial "$u/serial"
done

sec "dmx: OLA"
if timeout 1 bash -c '</dev/tcp/127.0.0.1/9010' 2>/dev/null; then echo "OK   ola            :9010 listening"; else echo "--   ola            :9010 not listening (olad down?)"; fi
for f in /etc/ola/ola-port.conf /etc/ola/ola-usbdmx.conf /etc/ola/ola-usbpro.conf; do [ -e "$f" ] && chk ola-conf "$f"; done

sec "jack processes (cmdline only)"
for p in $(pgrep -x jackd; pgrep -x zita-j2a); do chk jack-cmd "/proc/$p/cmdline"; done

sec "cuems config"
for f in /etc/cuems/settings.xml /etc/cuems/default_mappings.xml; do [ -e "$f" ] && chk cuems-conf "$f" || echo "--   cuems-conf     $f absent"; done
ls -ld /etc/cuems

sec "python modules visible to the shared venv (located, not imported)"
/usr/lib/cuems/bin/python -I -B -c '
import importlib.util as u
for m in ("pynng","cuemsutils","ola","ola.OlaClient"):
    try: s=u.find_spec(m); print(("OK   " if s else "FAIL ")+"py-module      "+m+("  "+str(s.origin) if s else "  not found"))
    except Exception as e: print("FAIL py-module      "+m+"  "+type(e).__name__)
' 2>&1
dpkg -l python3-ola 2>/dev/null | tail -1

printf '\n== summary: %d readable, %d failed\n' "$ok" "$ko"
