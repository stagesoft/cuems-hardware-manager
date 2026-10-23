#!/bin/bash
# SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run from the repository root, over ssh as cuems-admin, with no sudo:
#   ssh -i ~/.ssh/cuems-org cuems-admin@<host> 'bash -s' < dev/scripts/inspect-readonly-2.sh > dev/data/inspect2-<host>.txt
# See dev/README.md.
# Follow-up read-only inspection, run as cuems-admin, no sudo. Writes nothing,
# opens no device node. Prints no serials and no EDID contents.
export LC_ALL=C
sec() { printf '\n== %s\n' "$1"; }

sec "host model (DMI)"
for f in sys_vendor product_name board_name; do printf '%-13s %s\n' "$f" "$(cat /sys/class/dmi/id/$f 2>&1)"; done

sec "show lock: age, owner, and who is running"
if [ -e /tmp/cuems.show.lock ]; then stat -c 'lock %U:%G mode %a modified %y' /tmp/cuems.show.lock; echo "boot: $(uptime -s)"; fi
for p in cuems-node-engine cuems-controller-engine cuems-videocomposer jackd olad zita-j2a; do
  printf '%-24s %s\n' "$p" "$(timeout 5 systemctl is-active "$p".service 2>/dev/null) pids=$(pgrep -d, -f "$p" | head -c 60)"
done
timeout 5 systemctl is-active jackd-cuems.service cuems-hdmi-audio-map.service 2>/dev/null | paste -sd' ' | sed 's/^/jackd-cuems, hdmi-audio-map: /'

sec "videocomposer build: does it carry contract v1?"
dpkg-query -W -f='${Package} ${Version}\n' cuems-videocomposer cuems-common cuems-utils python3-ola ola 2>/dev/null

sec "OLA python client: any spawn path?"
f=/usr/lib/python3/dist-packages/ola/OlaClient.py
grep -nE 'subprocess|Popen|os\.(system|exec|spawn|fork)|olad' "$f" || echo "no spawn-related tokens in $f"
grep -nE 'def (__init__|_ConnectToServer|Connect)|connect\(' "$f" | head -10

sec "HDMI ELD summary (presence flags only)"
for e in /proc/asound/card*/eld#*; do
  mp=$(awk '/^monitor_present/{print $2}' "$e"); ev=$(awk '/^eld_valid/{print $2}' "$e")
  [ "$mp" = 1 ] && printf '%s monitor_present=%s eld_valid=%s conn_type=%s\n' "$e" "$mp" "$ev" "$(awk '/^connection_type/{print $2}' "$e")"
done

sec "codec#2 pin/device structure (no monitor data)"
for c in /proc/asound/card*/codec#*; do
  grep -q 'HDMI\|DisplayPort' "$c" 2>/dev/null || continue
  echo "-- $c"; grep -nE '^Node 0x[0-9a-f]+ \[Pin Complex\]|Devices:|^ +(\*|) *Dev [0-9]+: PCM|DevList|Connection:' "$c" | head -40
done

sec "PCM ids (which pcmN is HDMI vs analog)"
for i in /proc/asound/card*/pcm*/info; do printf '%s: %s / %s\n' "$i" "$(awk -F': ' '/^id/{print $2}' "$i")" "$(awk -F': ' '/^name/{print $2}' "$i")"; done

sec "/etc/asound.conf structure (device names only)"
[ -r /etc/asound.conf ] && grep -nE '^\s*(pcm\.|ctl\.|type|slave|pcm|bindings|[0-9]+\s*\{)|hw:' /etc/asound.conf | head -40 || echo "absent"

sec "JACK command line (arguments only)"
for p in $(pgrep -x jackd; pgrep -x zita-j2a); do tr '\0' ' ' < /proc/$p/cmdline; echo; done

sec "USB: which devices have no serial, and their driver"
for u in /sys/bus/usb/devices/[0-9]*-*; do
  [ -e "$u/idVendor" ] || continue
  drv=$(for i in "$u"/*:*/driver; do [ -e "$i" ] && basename "$(readlink -f "$i")"; done | sort -u | paste -sd,)
  printf '%-10s %s:%s serial=%s drivers=%s\n' "$(basename "$u")" "$(cat $u/idVendor)" "$(cat $u/idProduct)" "$([ -e $u/serial ] && echo yes || echo no)" "${drv:-none}"
done

sec "ola-port.conf keys (serials masked)"
grep -oE '^[0-9]+-[^-]+-[IO]-[0-9]+' /etc/ola/ola-port.conf 2>/dev/null | sed -E 's/^([0-9]+)-[^-]+-/\1-<SERIAL>-/' | sort | uniq -c

sec "cuems-admin groups and /etc/cuems tree ownership"
id -nG; ls -la /etc/cuems | head -30
