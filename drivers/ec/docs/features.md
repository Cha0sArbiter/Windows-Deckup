# EC features: what exists and what works

The implementation described here exists in the local prototype, not as downloadable source or an installer in this repository. “Implemented” means the code exists; “hardware-tested” means we observed it on a real Deck. Those are different milestones. Start with the [EC overview](../README.md).

| Feature | 0.2.0 source | Hardware validation / limits |
| --- | --- | --- |
| Original ten telemetry fields | Implemented; compatible V1 API | New binary read successfully on B030/06; longer stability/lifecycle checks pending |
| Charge-rate configuration / panel ID | Extended telemetry implemented | Sampled successfully: GCHR raw 0, PANR raw 1; meanings/charging units not physically validated |
| Fan target and firmware automatic mode | Experimental controls implemented | Brief boost and explicit recovery passed; lease expiry, cleanup and lifecycle tests pending |
| Fan fault / high-temperature status | Read and used by health check | FANC interpretation comes from this BIOS; not a continuous APU-temperature sensor |
| Charge LED | Experimental setter implemented | No public getter; visual test pending |
| Charge-rate configuration | Experimental setter with readback | Raw 250–2500; units and enforcement unverified; invalid baseline rejects setter |
| Maximum charge level | Experimental setter with readback | Board 0A only; board 06 disabled; physical enforcement unverified |
| PD connection / voltage / current | Telemetry implemented | Firmware reports, not actual APU consumption |
| USB Type-C notifications / role integration | Planned, not implemented | Firmware status-change notification exists; Windows notification/USB-stack bridge pending; no USB role writes |
| Panel diagnostics / display controls | Documented, not exposed | Firmware handshake loops and Windows display ownership need validation |
| SCBP charging/battery-related control | Documented, not exposed | Exact semantics and restoration unverified |
| Fan gain, ramp, hysteresis, target CPU temperature | Not available in this BIOS | STCT, SGAN, SFRR, SHTS absent from VFCD |
| Charge recalculation | Not available in this BIOS | SCHG absent from VFCD |
| TDP, CPU/GPU clocks, throttle reasons | Outside EC driver | Requires a separate compatible AMD APU interface |
| Ambient light / automatic brightness | Outside EC driver | Separate PRP0001 I2C devices and Windows integration |
| Game controls without Steam | Outside this project | Separate Valve USB HID device |

## Definition of a fully featured release

The project should support the meaningful public EC methods on each explicitly
supported hardware/firmware combination, explain unavailable features through
capability reporting, and pass installation, control, recovery and power-cycle
tests. It must not treat a method's presence or a matching register readback as
proof of the corresponding physical feature.

For this Deck, longer telemetry checks, remaining fan recovery tests, LED validation, charge-rate behavior,
USB notifications and a disposition for the display/SCBP methods remain work.
The development package is therefore not a fully featured production release.
