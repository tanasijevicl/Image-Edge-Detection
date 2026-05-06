## Image Edge Detection

### Overview
This project implements a **hardware-accelerated image edge detection system** on the Zynq platform. It compares a **software solution running on the CPU** with a **custom FPGA accelerator**, demonstrating significant performance improvements.

The system computes image gradients and detects edges using a configurable threshold.

### Features
- Gradient computation (horizontal & vertical)
- Gradient magnitude approximation
- Threshold-based edge detection
- Software (CPU) and hardware (FPGA) implementations
- AXI DMA for high-speed data transfer
- Configurable parameters (image size, threshold, modes)
- Execution time measurement and speedup analysis
- Result verification (SW vs HW)

### Architecture
- **PS (CPU):** control, software processing, DMA setup
- **PL (FPGA):** streaming edge detection accelerator
- **Interfaces:** AXI Stream (data), AXI Lite (control)

### Technologies
- C/C++, VHDL
- Xilinx Zynq-7000
- Vivado, Vitis
- AXI DMA, AXI Timer

### Usage
1. Load image into memory
2. Run software version (`EdgeDetectionSW`)
3. Run hardware version (`EdgeDetectionHW`)
4. Compare execution time and results

### Notes
- Streaming hardware design with line buffers
- Supports border handling and bypass mode
- Educational project focused on HW/SW co-design