# Edge AI Hardware Accelerator Engine

A real-time, fully parallelized TinyML hardware accelerator written in structural Verilog HDL, optimized for handwritten digit recognition (MNIST dataset). The design is mapped onto a Xilinx Artix-7 (XC7A35T) FPGA architecture using the Digilent Basys3 development board, featuring an end-to-end telemetry loop with a host PC python vision sensor.

Rather than executing abstract software on an embedded microprocessor, this project builds dedicated physical arithmetic silicon to run low-latency neural network inferences completely inside a single hardware clock domain.

## Key Micro-Architectural Highlights

**4-Way Vector MAC Architecture (mac_unit.v):** Developed a custom parallel dot-product engine running a 4-input signed arithmetic pipeline tree; engineered an 18-bit bit-growth safe accumulator that eliminates arithmetic overflow while maximizing $F_{max}$ throughput.

**4-Way Parallel Interleaved Memory (nn_core.v):** Subdivided the 784-byte image array across 4 independent RAM banks. Utilized an address multiplexing matrix to bypass standard single-port memory bottlenecks, extracting 4 sequential pixels simultaneously per clock cycle.

**High-Speed Telemetry Pipeline (uart_rx.v, uart_tx.v):** Implemented an asynchronous serial receiver operating at 115,200 baud to stream 784-byte image payloads into hardware memory over a ~68.06 ms transmission window; integrated a robust start-bit validation mechanism to reject line noise and prevent false FSM triggers.

**CDC Metastability Hardening (uart_rx.v):** Integrated a localized double-flop synchronizer layer to safely step external asynchronous PC telemetry bits into the local 100 MHz clock domain, mitigating metastability and violating no setup/hold timing paths.

**Piecewise SoftMax Approximation Engine (nn_core.v):** Replaced hardware-heavy floating-point division and Euler’s constant (e^x) calculations with an optimized fixed-point bit-shift look-up matrix mapping out reliable 0–99% confidence ratings using minimal logic resources.

**Physical Interface Driver (seven_seg.v, top.v):** Authored a resource-optimized, time-multiplexed 4-digit 7-segment display driver to continuously project the winning predicted integer alongside live scalar certainty metrics without inferring a hardware divider.
