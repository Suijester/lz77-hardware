`timescale 1ns / 1ps

module tb_lz77_compressor;

    // Parameters
parameter windowSize = 4095;
parameter bufferSize = 63;
parameter minimumMatchLength = 3;
parameter windowAddressBits = 12;
parameter bufferAddressBits = 6;
parameter clkPeriod = 10;

    // Testbench signals
reg clk;
reg rst_n;
reg start;
wire busy;
wire done;
    
reg [7:0] inputData;
reg inputValid;
wire inputReady;
reg lastInputPassed;
    
wire outputBit;
wire outputValid;
reg outputReady;
wire [31:0] bytesRead;

localparam maxFileSize = 200000; // must exceed alice29.txt size
reg [7:0] fileMemory [0:maxFileSize-1];
integer fileSize;
integer fd;
integer i;
integer c;

integer receivedBits = 0;
integer cycleCount = 0;

lz77_compressor #(
.windowSize(windowSize),
.bufferSize(bufferSize),
.minimumMatchLength(minimumMatchLength),
.windowAddressBits(windowAddressBits),
.bufferAddressBits(bufferAddressBits)
) dut (
.clk(clk),
.rst_n(rst_n),
.start(start),
.busy(busy),
.done(done),
.inputData(inputData),
.inputValid(inputValid),
.inputReady(inputReady),
.lastInputPassed(lastInputPassed),
.outputBit(outputBit),
.outputValid(outputValid),
.outputReady(outputReady),
.bytesRead(bytesRead)
);
    
always @(posedge clk) begin
    if (!done) begin
        cycleCount = cycleCount + 1; // benchmark our throughput and time-cost
    end
    
    if (outputValid && outputReady) begin
        receivedBits = receivedBits + 1; // find how many bits we receive from the compressor
    end
end
    

// generate our dut's clock, with period of 10ns
initial begin
    clk = 0;
    forever #(clkPeriod/2) clk = ~clk;
end

// task designed to send bytes to the dut for compression
task sendByte;
    input [7:0] data;
    input isLast;
    begin
        inputData <= data;
        lastInputPassed <= isLast;
        inputValid <= 1;
         @(posedge clk);
         while (!inputReady) begin
            @(posedge clk);
         end
         inputValid <= 0;
         lastInputPassed <= 0;
         @(posedge clk);
    end
endtask

initial begin
    $display("LZ77 Compressor Test: alice29.txt");

    fd = $fopen("alice29.txt", "rb");
    
    if (fd == 0) begin
        $fatal("Error: failed to open alice29.txt");
    end

    fileSize = 0;
    while (!$feof(fd) && fileSize < maxFileSize) begin
        c = $fgetc(fd); // read one character (if it returns -1, means there's an error)
        
        if (c == -1)begin
            break; // break if we failed to get a char
        end
        
        fileMemory[fileSize] = c & 8'hFF; // store the lowest 8 bytes of c, which will contain the character from the file, and zero extend c
        fileSize = fileSize + 1;
    end
    
    $fclose(fd);

    $display("Loaded %0d bytes from alice29.txt", fileSize);

    // reset the DUT before we begin
    rst_n <= 0;
    start <= 0;
    inputValid <= 0;
    outputReady <= 1;
    receivedBits = 0;
        
    #(clkPeriod * 5);
    rst_n <= 1;
    @(posedge clk);
        
    // begin compression
    start <= 1;
    @(posedge clk);
    start <= 0;
        
    // wait until the compressor begins compressing (it becomes busy)
    @(posedge clk);
    while (!busy) @(posedge clk);
        
    // send bytes from alice29.txt
    for (i = 0; i < fileSize; i = i + 1) begin
        sendByte(fileMemory[i], (i == fileSize - 1));
    end

    $display("Input sent, waiting for completion...");

    // wait to receive the compressed bytes (the first @always block does so)
    while (!done) @(posedge clk);

    $display("Compression complete!");
    $display("Total compressed bits = %0d", receivedBits);
    $display("Bytes Read by Compressor = %0d, Expected Bytes Read = %0d", bytesRead, fileSize);
    $display("Time taken: %0d", cycleCount * 10);
    $finish;
end

endmodule
