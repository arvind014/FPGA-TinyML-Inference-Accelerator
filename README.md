# FPGA-MNIST-Inference-Accelerator
Real-time TinyML hardware inference accelerator in structural Verilog for Xilinx Artix-7 (Basys3). Implements parallel MNIST digit recognition using a custom 4-way vector MAC pipeline, 4-way interleaved RAM banks, fixed-point piecewise SoftMax approximation, and an ultra-fast 460,800 baud UART telemetry link connecting a host PC webcam loop.
