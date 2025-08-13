# LZ77 Compression Accelerator
Verilog-implemented LZ77 greedy compressor designed for FPGAs. Designed for smaller windows and buffers, as throughput is most optimal then, with lowest memory usage. Benchmarked 48.1% on alice29.txt at window size of 4096, and buffer size of 64, although compression can reach higher ratios with larger windows and buffers. SystemVerilog testbench included.

## Acknowledgements
- Canterbury Corpus (used alice29.txt)
- Vivado (simulation)
