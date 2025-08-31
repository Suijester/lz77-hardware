`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/20/2025 02:56:01 PM
// Design Name: 
// Module Name: lz77_compressor
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module lz77_compressor #(
    parameter windowSize = 1023, // window of past data holds 2^12 items
    parameter bufferSize = 31, // buffer of upcoming data holds 2^6 items
    parameter minimumMatchLength = 3, // minimum match length that makes it worth encoding is a match length of 3
    parameter maxParallelSearches = 16, // any power of two will work s.t. maxParallelSearches < windowSize
    
    // bit size to contain window and buffer
    parameter windowAddressBits = 12,
    parameter bufferAddressBits = 6
    ) (
    // clock and reset wires
    input wire clk,
    input wire rst_n,
    
    // program states
    input wire start,
    output reg busy,
    output reg done,
    
    // input data
    input wire [7:0] inputData,
    input wire inputValid,
    output wire inputReady,
    input wire lastInputPassed,
    
    // output data
    output reg outputBit,
    output reg outputValid,
    input wire outputReady,
    output reg [31:0] bytesRead // number of bytes read in stream
);

// FSM states
parameter idleState = 3'd0;
parameter inputState = 3'd1;
parameter searchState = 3'd2;
parameter encodeState = 3'd3;
parameter waitState = 3'd4;
parameter completeState = 3'd5;

// state identifiers
reg [2:0] currentState, nextState;

// circular arrays that use BRAM and distributed RAM, since the arrays are large and small respectively
(*ram_style = "block"*)reg [7:0] circularWindow [0:windowSize - 1];
reg [7:0] circularBuffer [0:bufferSize - 1];

reg [windowAddressBits - 1:0] windowPtr; // points to current first position in the circularWindow
reg [windowAddressBits:0] charsInWindow; // number of characters in the window
reg [bufferAddressBits:0] charsInBuffer; // contains the current number of characters in the buffer
reg [bufferAddressBits - 1:0] bufferPtr; // points to the current erasable element in the buffer
reg [bufferAddressBits - 1:0] readPtr; // points to the zero element of the buffer

reg [bufferAddressBits - 1:0] bestIterator;

// search tools for greedy algorithm
reg [windowAddressBits - 1:0] bestOffset;
reg [bufferAddressBits - 1:0] bestMatchLength;

reg maxSearchFound;

reg [windowAddressBits:0] currentPositions [0:maxParallelSearches - 1];
reg [windowAddressBits - 1:0] currentLengths [0:maxParallelSearches - 1];
integer i;

reg [maxParallelSearches - 1:0] threadSync;

reg [bufferAddressBits - 1:0] combinationalLength;
reg [windowAddressBits - 1:0] combinationalOffset;
integer j;

// output register holding all the bytes, we dispense each to outpitBit one by one
reg [windowAddressBits + bufferAddressBits:0] outputBitRegister;
reg [4:0] outputBitsLeft; // log2(windowAddressBits + bufferAddressBits + 1)
reg lastInputReceived;

reg waitCycle;
reg delayBeforeEncode;

// location in circular arrays
reg [bufferAddressBits:0] bufferAddress;
reg [windowAddressBits:0] windowAddress;

wire [18:0] token;

assign token = (bestMatchLength >= minimumMatchLength) ? {1'b0, bestOffset[11:0], bestMatchLength[5:0]} : {1'b1, circularBuffer[readPtr], 10'b0};
assign inputReady = (currentState == inputState) && (charsInBuffer < bufferSize) && (lastInputReceived == 0);

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin // reset goes low, program starts
        currentState <= idleState;
        
        // current state is starting up, can set busy/done to low
        busy <= 0;
        done <= 0;
        
        // window and buffers start empty
        windowPtr <= 0;
        charsInBuffer <= 0;
        bufferPtr <= 0;
        readPtr <= 0;
        
        // no input accepted or processed yet,
        bytesRead <= 0;
        lastInputReceived <= 0;
        charsInWindow <= 0;
        outputValid <= 0;
        
        outputBit <= 0;
        outputBitsLeft <= 0;
        
        for (i = 0; i < maxParallelSearches; i = i + 1) begin
            currentPositions[i] <= i;
            currentLengths[i] <= 0;
        end
        
        bestMatchLength <= 0;
        bestOffset <= 0;
        maxSearchFound <= 0;
        
        waitCycle <= 0;
        delayBeforeEncode <= 0;
        
        threadSync <= {maxParallelSearches{1'b0}};
        
    end else begin 
        // advance state and total number of bytes 
        currentState <= nextState;
    
        case (currentState)
            idleState: begin
                if (start) begin
                    // begin setup, we are now busy
                    busy <= 1;
                    
                    // setup search variables
                    bestOffset <= 0;
                    bestMatchLength <= 0;
                    
                    for (i = 0; i < maxParallelSearches; i = i + 1) begin
                        currentPositions[i] <= i;
                        currentLengths[i] <= 0;
                    end
                    
                    bestIterator <= 0;
                    
                end
            end
            
            inputState: begin
                if (inputValid && inputReady) begin
                    circularBuffer[bufferPtr] <= inputData;
                    bufferPtr <= (bufferPtr + 1) % bufferSize;
                    charsInBuffer <= charsInBuffer + 1;
                    bytesRead <= bytesRead + 1;
                    
                    if (lastInputPassed) begin
                        lastInputReceived <= 1;
                    end
                end
            end

            searchState: begin
                for (i = 0; i < maxParallelSearches; i = i + 1) begin
                    windowAddress = (windowPtr + currentPositions[i] + currentLengths[i]) % windowSize;
                    bufferAddress = (readPtr + currentLengths[i]) % bufferSize;

                    if ((currentPositions[i] + currentLengths[i] < charsInWindow) &&
                        (currentLengths[i] < charsInBuffer) &&
                        (circularWindow[windowAddress] == circularBuffer[bufferAddress])) begin
                        currentLengths[i] <= currentLengths[i] + 1;
                    end else begin
                        currentPositions[i] <= (currentPositions[i] + maxParallelSearches >= charsInWindow) ? charsInWindow : (currentPositions[i] + maxParallelSearches);
                        if (currentPositions[i] + maxParallelSearches >= charsInWindow) begin
                            threadSync[i] <= 1;
                        end
                        currentLengths[i] <= 0;
                    end
                    
                    if (combinationalLength > bestMatchLength && waitCycle) begin // for the very first cycle, combinational length will hold undefined values, so we need to wait for a cycle until it's updated.
                        bestMatchLength <= combinationalLength;
                        bestOffset <= combinationalOffset;
                    end else begin
                        waitCycle <= 1;
                    end
                    
                    if (&threadSync) begin
                        delayBeforeEncode <= 1;
                    end
                end
            end

            encodeState: begin
                maxSearchFound <= 0;
                bestMatchLength <= 0;
                bestOffset <= 0;
                threadSync <= 0;
                    
                for (i = 0; i < maxParallelSearches; i = i + 1) begin
                    currentLengths[i] <= 0;
                    currentPositions[i] <= i;
                end
                
                if (!outputValid) begin
                    outputBitRegister <= token << 1;
                    outputBit <= token[18]; 
                    
                    if (bestMatchLength >= minimumMatchLength) begin
                        outputBitsLeft <= 19;
                        bestIterator <= (bestMatchLength > charsInBuffer) ? charsInBuffer : bestMatchLength;
                    end else begin
                        outputBitsLeft <= 9;
                        bestIterator <= 1;
                    end
                    outputValid <= 1;
                end else if (outputValid && outputBitsLeft > 0 && outputReady) begin
                    outputBit <= outputBitRegister[18];
                    outputBitRegister <= outputBitRegister << 1;
                    outputBitsLeft <= outputBitsLeft - 1;
                    
                    if (outputBitsLeft == 1) begin
                        outputValid <= 0;
                    end
                end 
            end
                
            waitState: begin
                if (bestIterator > 0) begin
                    if (charsInWindow < windowSize) begin
                        circularWindow[(windowPtr + charsInWindow) % windowSize] <= circularBuffer[readPtr];
                        charsInWindow <= charsInWindow + 1;
                    end else begin
                        circularWindow[windowPtr] <= circularBuffer[readPtr];
                        windowPtr <= (windowPtr + 1) % windowSize;
                    end
                    charsInBuffer <= charsInBuffer - 1;
                    readPtr <= (readPtr + 1) % bufferSize;
                    bestIterator <= bestIterator - 1;
                end
            end

            completeState: begin
                busy <= 0;
                done <= 1;
            end
        endcase
    end
end

always @(*) begin
    case (currentState)
        idleState: begin
            if (start) begin
                nextState = inputState;
            end else begin
                nextState = idleState;
            end
        end
        
        inputState: begin
            if ((charsInBuffer == bufferSize && lastInputReceived == 0) || (lastInputReceived == 1 && charsInBuffer > 0)) begin
                nextState = searchState;
            end else begin
                nextState = inputState;
            end
        end

        searchState: begin
            if (&threadSync && delayBeforeEncode) begin
                nextState = encodeState;
            end else begin
                nextState = searchState;
            end
        end

        encodeState: begin
            if (outputValid && outputBitsLeft == 1 && outputReady) begin
                nextState = waitState;
            end else begin
                nextState = encodeState;
            end
        end

        waitState: begin
            if (bestIterator > 0) begin
                nextState = waitState;
            end else begin
                if (lastInputReceived == 1 && charsInBuffer == 0) begin
                    nextState = completeState;
                end else if (lastInputReceived == 1 && charsInBuffer > 0) begin
                    nextState = searchState;
                end else begin
                    nextState = inputState;
                end
            end
        end
        
        completeState: begin
            nextState = completeState;
        end
    endcase
end

always @(*) begin
    combinationalLength = 0;
    combinationalOffset = 0;
    for (j = 0; j < maxParallelSearches; j = j + 1) begin
        if (currentLengths[j] > combinationalLength) begin
            combinationalLength = currentLengths[j];
            combinationalOffset = currentPositions[j];
        end
    end
end

endmodule