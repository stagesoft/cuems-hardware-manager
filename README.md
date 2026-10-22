# cuems-hardware-manager

Hardware outputs manager and discovery service for the CueMS system.

> **Status: design phase.** No code yet. The architecture proposal and its open decisions are in
> [`specs/planning/`](specs/planning/README.md).

## What it does

Every CUEMS node drives physical outputs: video connectors and the displays or projectors behind
them, audio interfaces, DMX interfaces. Until now no part of the system described that hardware on
its own. The port inventory lived inside project mappings (`default_mappings.xml`), and display
geometry lived in hand-edited files. This repository is that missing layer. It runs the whole
chain:

```
real hardware ─▶ digital twin ─▶ node promotion ─▶ system total ─▶ operator agreement ─▶ system setup
availability     (per node)      (node → ctrl)     capabilities     (selection +          (apply to
                                                                     configuration)        each box)
```

1. **Availability.** Probes on each host find what is attached: through the videocomposer's
   management contract, DRM, ALSA/JACK and OLA.
2. **Digital twin.** Each node keeps a stable, named description of its hardware in
   `/etc/cuems/hardware_outputs.xml`.
3. **Promotion.** Each node serves its twin to the controller over a versioned node API.
4. **System capabilities.** The controller combines the twins of every adopted node into one
   catalogue of what the cluster can do.
5. **Operator agreement.** The operator picks which elements the system uses and how they are set
   up: video modes and regions, audio routing, DMX universe patching.
6. **System setup.** Each node applies its share of the agreement, and only when no show is
   loaded.

Stages 1 to 5 only observe and record. Only stage 6 changes anything on a box, and only from an
agreement the operator made.

## How it fits

| Runs as | Where |
|---|---|
| `cuems-hardware-node` | every host, part of `cuems-node.target`. The only writer of the node's twin |
| `cuems-hardware-controller` | the controller, part of `cuems-controller.target` |

It **reads**: the videocomposer contract, `network_map.xml` (from `cuems-nodeconf`),
`power-bridge.conf`, and the `cuems-utils` schemas through public accessors.
It **writes**: the node's twin, the operator agreement, and the rendered subsystem config
(`display.conf`, ALSA/JACK, OLA patching).
It **does not**: control cues (`cuems-engine`), configure the network (`cuems-nodeconf`), power
projectors or nodes (`cuems-power-bridge`), or define schemas (`cuems-utils`).

The system index, protocols and port map for the whole ecosystem are in
[`cuems-RELATIONS`](https://github.com/stagesoft/cuems-RELATIONS).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
