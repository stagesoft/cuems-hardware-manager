<!--
SPDX-FileCopyrightText: 2026 Stagelab Coop SCCL
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Contract — the per-class probe plug-in (internal)

This is the interface that makes hardware classes data (Principle VI, FR-007, SC-009). It is internal to this package, but it is held stable, because each later class (network displays, NDI, MIDI, GPU policy inputs) is added through it.

## Shape

```python
class Probe(Protocol):
    cls: str                      # the class name this probe reports, e.g. "dmx"
    requires: tuple[str, ...]     # classes whose results it needs first, e.g. ("video",)

    def probe(self, host: HostView, ctx: ProbeContext) -> ProbeResult: ...
```

- **`HostView`** (research R1): `read_text(path)`, `read_bytes(path)`, `realpath(path)`, `listdir(path)`, `exists(path)`; `vc` (the contract client, or `None`); `ola` (the client factory); `port_listening(host, port)`; `show_lock` (`bool`, re-checkable); `euid`. Paths are host-absolute (`/sys/...`) and resolve under the view's root.
- **`ProbeContext`**: read-only results of the classes in `requires`, plus `report`, through which a probe adds degradations, deferrals and diagnostics. A probe never touches another probe's devices.
- **`ProbeResult`**: `devices: list[Device]`, built from the model types in [`../data-model.md`](../data-model.md), and `source: str`.

## Rules

1. **Discovery.** The node imports every module of `cuemshardwaremanager.probes` and collects its `PROBE`. Tests may call `registry.register(probe)`. No other code lists class names.
2. **Order.** Probes run in topological order of `requires`, with ties broken by `cls`. A cycle is an internal error.
3. **Forbidden.** Opening device nodes, spawning processes, writing files, binding sockets, and JACK clients (FR-021, FR-024). The test harness enforces this by patching `open` for `/dev/`, `subprocess`, `os.exec*`, `socket.bind` and `os.fork`, and failing any probe that reaches them.
4. **Failure is a result, not an exception.** An unreadable or unresponsive source becomes a fallback plus `report.degraded`. An exception that escapes a probe makes the run exit `1`, and a test must cover it.
5. **Ids.** A probe builds `port_id`s only from the physical-key helpers (`identity.py`). The node checks uniqueness across all probes.
6. **Authored inputs.** A probe may read an operator-authored file only to fill `report`, never `twin` (FR-008). In 001 only the continuity and hazard checks read such files, and they run as a report step, not as a probe.
