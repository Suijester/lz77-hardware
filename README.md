# LZ77 Compression Accelerator
_**Pipelined, parallel, parameterized LZ77 hardware accelerator in Verilog <br> ~48% compression, ~9 MB/s throughput simulated on standard corpus text.**_

Verilog-implemented LZ77 greedy compressor designed for FPGAs. Designed for instantiable parameterization, with sliding window, buffer, and parallel search size all adjustable. Throughput directly increases with parallel threads. Larger sliding window and buffer increase compression ratio, but simulataneously decrease throughput/cost more FPGA resources. Compression ratio is proportional to text length.

Parallelization is achieved through multiple parallel threads searching different positions within the sliding window at any given time, increasing throughput significantly. 

Benchmarked 48.1% on alice29.txt at window size of 4096, and buffer size of 64, although compression can reach higher ratios with larger windows and buffers. Approximately 5 MB/s throughput at 256 parallel threads. SystemVerilog testbench included.

## How It Works (Input -> Greedy Search -> Encoding & Outputting -> Completion)
![LZ77 Pipeline State Diagram](https://github.com/user-attachments/assets/f1e4c520-bd96-4956-985f-4a06b3fadcce)
_Above is the state diagram of the LZ77 Implementation, with short summary of how each state operates._
- **Idle State:** Initializes variables, waits until the start signal is passed to begin compression.
- **Input State:** Fills circular buffer with input data until buffer is full or no input data remains.
- **Search State:** Performs parallel greedy searches throughout the circular window to find the best match.
- **Encode State:** Generates an output of either a match or literal token, based on best match length.
- **Wait State:** Updates circular window with searched and encoded bytes.
- **Complete State:** Completed compression successfully, signal for end of program.

![LZ77 Hardware Block Diagram](https://github.com/user-attachments/assets/c40e7219-f886-48e0-9e70-6622fdc249c6)
_Above is the hardware diagram of the LZ77 Implementation, with threads being permitted in any power of two under the window size._ <br> 

## Benchmarking
For simulation and synthesis, LUT arrays were used for parallelism for easier read/write access to minimize synthesis and simulation times. Real FPGA deployment would require BRAM usage. Additionally, for synthesis, lower parameters were used to fit within LUT cost. Timing violations did occur, but synthesis with lower parameters avoids this better.

### Simulation Results (High Instantiated Parameters)
| Benchmark         | Value |
|-------------------|-------|
| Threads           | 256    |
| Window Size       | 4096  |
| Buffer Size       | 64    |
| Throughput        | 9 MB/s |
| Compression Ratio | ~48% (alice29.txt) |

### Synthesis Results (Low Instantiated Parameters)
_Project Device: Artix-7, xc7a100tcsg324-1_

| Threads | Window | Buffer | LUTs  | FFs  |
|--------|--------|--------|-------|-------|
|  16    | 1024   | 32     | 65.94%| 7.09% |

### Timing & Power
- **Timing:** Timing violations were significant, with major worst negative slack, as a result of complex combinational logic.
- **Power:** Total On-Chip Power (Simulated): 0.144 W
- **Junction Temp:** Estimated 25.7 C

## Challenges Solved & Performance Bottlenecks (for short)

During the implementation of this program, I ran into multiple challenges, notably deadlock between states. This deadlock was certainly lethal to the outcome of the program, preventing advancement, caused by undefined behavior in improperly initialized variables (accessed before the clock enabled them to have a different value). Similar deadlock was faced during the implementation of the parallel search. Deadlock was essentially the primary difficulty, as state locking was difficult to recover from, and required long times of staring at waveforms.

Parallel Search traverses through the window by some (power of two) number of threads, dependent on the instantiated module the user creates. Each thread performs approximately (window size / number of threads) search tasks, logging its current search length. Combinationally, an overhanging comparator identifies which thread has the best match length, and saves that thread's current position in the window, alongside the length of the match. This repeats until all threads complete their search tasks, at which point the comparator has the best possible match length, at the corresponding window position.

Performance bottlenecks currently remain twofold; one within the bit output method (every output bit requires one cycle), and one within the circular window (the window is an LUT array, although deployment will require it to be Block RAM). Implementing the latter is beyond the scope of this project, as it would be rather difficult to retain throughput with dual port BRAM, and the former can be implemented rather easily compared to the latter, although I haven't done so, as to leave the option to add other compression methods onto the current LZ77 output (any entropy coder will suffice).

## Development Process & Debugging (at length)
### C++ Development
A classical LZ77 Greedy Compressor, I initially sought to implement this in C++. The goal of the LZ77 Compressor is to compress by maintaining a sliding window and a buffer. We search the sliding window to find the longest match starting from the first character of the buffer, and if we find a sufficient match, then rather than save characters, we save a token that points to the offset of the start of the match, and the length of the match. LZ77 tends to be most effective in repetitive data, e.g. books, human speech. 

Every compressed token was either a match token or a literal token, if the literal token bit output was more optimal than the match token output. Literal tokens simply had a high flag bit, to identify that they are literals, then spent an additional to directly encode the character. Match tokens, used if the match found is better than directly encoding all characters involved into literals, had a low flag bit, offset bits (at most clog2(sliding window length)), and length bits (at most clog2(buffer length)). 

My first solution was to immediately keep all compressed outputs inside of a struct of Tokens, which although effective and easy to model, lost a significant chunk of compression as a product of inherent C++ struct packing. While bit fields enabled me to minimize bit usage as much as possible, compression was overall hindered by compiler structure optimization. To minimize compression losses in software, I then implemented a minimal bit-packing solution, where we packed bits directly into bytes, utilizing a simple class to write bits into bytes and flush empty bytes. This method maximized compression, although somewhat complicated working directly with bytes, and had a rather good output.

### Verilog Development
After writing the C++ framework and code to better understand the algorithm, I implemented the algorithm into Verilog. LZ77 is highly sequential, so gains are limited to parallelism in search (increasing the number of searches at any time) or instantiation (you can break up text into smaller chunks managed by different instances of the module). Initially, I focused on a sequential implementation by pipelining it into stages, while utilizing sequential search. Debugging was certainly a lengthy struggle, with deadlock often occurring.

Primarily occurring in searchStage, deadlock was certainly a notorious bug to deal with for me. Notably caused by improper initialization of certain variables, searchState would go into deadlock from undefined behavior. However, resolving this deadlock occurred quickly after staring at the waveform generator. After completion of the initial development of the sequential code, which can be found in previous versions of this repository, I sought to implement parallel searching. Sequential Search's biggest bottleneck is throughput, as for any greedy search, searching such a large number of positions is time-expensive, especially in a finite state machine.

The implementation was certainly non-trivial. Threads were given different tasks to complete, but synchronizing their completion was certainly difficult, which I achieved through having an array of bits representing the completion of each bit. Once completed, the time it took to complete compression significantly increased, boosting throughput excellently. As it stands, the primary improvement that could be made to the accelerator in terms of throughput is byte packing. Currently, encodeState has to spend an equivalent number of cycles outputting bits as the number of bits output, which is exceptionally expensive. Byte Packing would reduce the number of cycle to an eight of what it is currently, increasing throughput by a decent amount.

Additionally, for actual FPGA deployment, I would advise not implementing this code directly onto an FPGA, but rather modifying it so that the circular window is dual-port BRAM based. Single-port is too expensive in throughput, and if properly implemented, throughput will be minimally effected. BRAM implementation is out of the scope of this project, so it remains undone.

## Acknowledgements
- Canterbury Corpus (alice29.txt)
- Vivado (simulation)
