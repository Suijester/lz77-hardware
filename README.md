# LZ77 Compression Accelerator
Verilog-implemented LZ77 greedy compressor designed for FPGAs. Designed for adjustable parameterization, with sliding window, buffer, and parallel search size all adjustable. Throughput increases with parallel threads. Benchmarked 48.1% on alice29.txt at window size of 4096, and buffer size of 64, although compression can reach higher ratios with larger windows and buffers. SystemVerilog testbench included.

## Development Process
### C++ Development
A classical LZ77 Greedy Compressor, I initially sought to implement this in C++. The goal of the LZ77 Compressor is to compress by maintaining a sliding window and a buffer. We search the sliding window to find the longest match starting from the first character of the buffer, and if we find a sufficient match, then rather than save characters, we save a token that points to the offset of the start of the match, and the length of the match. LZ77 tends to be most effective in repetitive data, e.g. books, human speech. 

Every compressed token was either a match token or a literal token, if the literal token bit output was more optimal than the match token output. Literal tokens simply had a high flag bit, to identify that they are literals, then spent an additional to directly encode the character. Match tokens, used if the match found is better than directly encoding all characters involved into literals, had a low flag bit, offset bits (at most clog2(sliding window length)), and length bits (at most clog2(buffer length)). 

My first solution was to immediately keep all compressed outputs inside of a struct of Tokens, which although effective and easy to model, lost a significant chunk of compression as a product of inherent C++ struct packing. While bit fields enabled me to minimize bit usage as much as possible, compression was overall hindered by compiler structure optimization. To minimize compression losses in software, I then implemented a minimal bit-packing solution, where we packed bits directly into bytes, utilizing a simple class to write bits into bytes and flush empty bytes. This method maximized compression, although somewhat complicated working directly with bytes, and had a rather good output.

### Verilog Development
After writing the C++ framework and code to better understand the algorithm, I implemented the algorithm into Verilog. LZ77 is highly sequential, so gains are limited to , although minor gains can be achieved through parallelism during searching. 

## Acknowledgements
- Canterbury Corpus (used alice29.txt)
- Vivado (simulation)
