# Edge AI Hardware Accelerator Engine

A real-time, fully parallelized TinyML hardware accelerator written in structural Verilog HDL, optimized for handwritten digit recognition (MNIST dataset). The design is mapped onto a Xilinx Artix-7 (XC7A35T) FPGA architecture using the Digilent Basys3 development board, featuring an end-to-end telemetry loop with a host PC python vision sensor.

Rather than executing abstract software on an embedded microprocessor, this project builds dedicated physical arithmetic silicon to run low-latency neural network inferences completely inside a single hardware clock domain.

## Key Micro-Architectural Highlights

* **4-Way Vector MAC Architecture (`mac_unit.v`):** Custom parallel dot-product workhorse running a 4-input signed arithmetic pipeline tree, calculating an 18-bit bit-growth safe accumulation step within a single system clock frame.
* **4-Way Parallel Interleaved Memory (`nn_core.v`):** Subdivides the 784-byte image array across 4 distinct independent RAM banks (Bank 0–3). By utilizing an address modulo-4 multiplexing matrix, the math engine bypasses standard single-port memory bottlenecks to extract 4 sequential pixels simultaneously.
* **High-Speed Telemetry Pipeline (`uart_rx.v`, `uart_tx.v`):** Upgraded un-clocked asynchronous handshake link operating at **115,200 baud**, shrinking multi-byte frame payload transfers down to an ultralow ~17.01ms delivery window.
* **CDC Metastability Hardening (`uart_rx.v`):** Integrates a localized double-flop shift register synchronization layer to safely step external PC telemetry bits into the local 100 MHz clock domain without timing violations.
* **Piecewise SoftMax Approximation Engine (`nn_core.v`):** Replaces hardware-heavy floating-point division and Euler’s constant calculation ($e^x$) with an optimized fixed-point bit-shift look-up matrix mapping out reliable 0–99% confidence ratings.
* **Physical Interface Dashboard (`seven_seg.v`, `top.v`):** Refreshes a multiplexed 4-digit 7-Segment HUD display to continuously project the winning predicted integer on the left and live scalar certainty metrics alongside it.
