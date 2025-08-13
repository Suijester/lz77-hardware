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
    parameter windowSize = 4095, // window of past data holds 2^12 items
    parameter bufferSize = 63, // buffer of upcoming data holds 2^6 items
    parameter minimumMatchLength = 3, // minimum match length that makes it worth encoding is a match length of 3
    
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
reg [7:0] circularWindow [0:windowSize - 1];
reg [7:0] circularBuffer [0:bufferSize - 1];

reg [windowAddressBits - 1:0] windowPtr; // points to current first position in the circularWindow
reg [windowAddressBits:0] charsInWindow; // number of characters in the window
reg [bufferAddressBits:0] charsInBuffer; // contains the current number of characters in the buffer
reg [bufferAddressBits - 1:0] bufferPtr; // points to the current erasable element in the buffer
reg [bufferAddressBits - 1:0] readPtr; // points to the zero element of the buffer

reg [31:0] acceptedInputBytes; // number of input characters accepted
reg [bufferAddressBits - 1:0] bestIterator;

// search tools for greedy algorithm
reg [windowAddressBits - 1:0] bestOffset;
reg [bufferAddressBits - 1:0] bestMatchLength;
reg [windowAddressBits - 1:0] currentSearchPosition;
reg [windowAddressBits - 1:0] currentLength;
reg maxSearchFound;

// output register holding all the bytes, we dispense each to outpitBit one by one
reg [windowAddressBits + bufferAddressBits:0] outputBitRegister;
reg [4:0] outputBitsLeft; // log2(windowAddressBits + bufferAddressBits + 1)
reg resetSearch;
reg lastInputReceived;

// location in circular arrays of 
reg [bufferAddressBits - 1:0] bufferAddress;
reg [windowAddressBits - 1:0] windowAddress;

wire [18:0] token; // combinationally assign the token we're going to output

assign token = (bestMatchLength >= minimumMatchLength) ? {1'b0, bestOffset[11:0], bestMatchLength[5:0]} : {1'b1, circularBuffer[readPtr], 10'b0};
assign inputReady = (currentState == inputState) && (charsInBuffer < bufferSize) && (lastInputReceived == 0); // check if we're ready to take an input combinationally

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin // reset goes low, program starts
        currentState <= idleState;
        nextState <= currentState;
        
        // current state is starting up, can set busy/done to low
        busy <= 0;
        done <= 0;
        
        // window and buffers start empty
        windowPtr <= 0;
        charsInBuffer <= 0;
        bufferPtr <= 0;
        readPtr <= 0;
        
        // no input accepted or processed yet, 
        acceptedInputBytes <= 0;
        bytesRead <= 0;
        lastInputReceived <= 0;
        charsInWindow <= 0;
        outputValid <= 0;
        
        // outputting bits to testbench or fpga
        outputBit <= 0;
        outputBitsLeft <= 0;
        
        // greedy option for search
        bestMatchLength <= 0;
        bestOffset <= 0;
        
    end else begin 
        // advance state and total number of bytes 
        currentState <= nextState;
        
        if (resetSearch) begin
            bestOffset <= 0;
            bestMatchLength <= 0;
            currentSearchPosition <= 0;
            currentLength <= 0;
            maxSearchFound <= 0;
        end
    
        case (currentState)
            idleState: begin
                if (start) begin
                    // begin setup, we are now busy
                    busy <= 1;
                    
                    // setup search variables
                    bestOffset <= 0;
                    bestMatchLength <= 0;
                    currentSearchPosition <= 0;
                    currentLength <= 0;
                    bestIterator <= 0;
                    
                end
            end
            
            inputState: begin
                // accept data from tb or some other input source
                if (inputValid && inputReady) begin
                    circularBuffer[bufferPtr] <= inputData;
                    bufferPtr <= (bufferPtr + 1) % bufferSize;
                    charsInBuffer <= charsInBuffer + 1;
                    acceptedInputBytes <= acceptedInputBytes + 1;
                    bytesRead <= bytesRead + 1;
                    
                    if (lastInputPassed) begin
                        lastInputReceived <= 1;
                    end
                end
            end

            searchState: begin
                // find the addresses of the index we want to access in both window and buffer
                windowAddress = (windowPtr + currentSearchPosition + currentLength) % (windowSize);
                bufferAddress = (readPtr + currentLength) % bufferSize;

                // check if our position + length exceeds the number of elements in array, if the next characters match, and if our string is shorter than the buffer, which it should be
                if (currentSearchPosition + currentLength < charsInWindow && 
                   circularWindow[windowAddress] == circularBuffer[bufferAddress] &&
                   currentLength < bufferSize) begin
                    currentLength <= currentLength + 1;
                end else begin
                    if (currentLength > bestMatchLength) begin
                        bestMatchLength <= currentLength;
                        bestOffset <= currentSearchPosition;
                        if (currentLength >= bufferSize) begin
                            maxSearchFound <= 1;
                        end
                    end
                    // restart the search one position ahead, since we've now failed to match, so we can find the local best choice
                    currentSearchPosition <= currentSearchPosition + 1;
                    currentLength <= 0;
                end
            end

            encodeState: begin
                if (!outputValid) begin
                    maxSearchFound <= 0;
                    // encode our token, and encode the very first one into outputBit
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
                    // pass bits out to the tb or output source
                    outputBit <= outputBitRegister[18];
                    outputBitRegister <= outputBitRegister << 1;
                    outputBitsLeft <= outputBitsLeft - 1;
                    // reset when we only have 1 bit left
                    if (outputBitsLeft == 1) begin
                        outputValid <= 0;
                    end
                end 
            end
                
            waitState: begin
                // cleanup process
                if (bestIterator > 0) begin
                    if (charsInWindow < windowSize) begin
                        // write chars to our window from buffer, since we just encoded
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
                nextState <= currentState;
            end
        endcase
    end
end

// next state combinational logic
always @(*) begin
    resetSearch = 0;
    case (currentState)
        // if given command to start, begin compression
        idleState: begin
            if (start) begin
                nextState = inputState;
            end else begin
                nextState = idleState;
            end
        end
        
        // continue to search if we fill buffer or if we have no chars left to receive
        inputState: begin
            if ((charsInBuffer == bufferSize && lastInputReceived == 0) || (lastInputReceived == 1 && charsInBuffer > 0)) begin
                nextState = searchState;
            end else begin
                nextState = inputState;
            end
        end
        
        // search unless we've exhausted all positions or found the best search plausible
        searchState: begin
            if (currentSearchPosition >= charsInWindow || maxSearchFound) begin
                nextState = encodeState;
            end else begin
                nextState = searchState;
            end
        end
        
        // encode while we have bits to encode, otherwise begin cleanup
        encodeState: begin
            if (outputValid && outputBitsLeft == 1 && outputReady) begin
                nextState = waitState;
            end else begin
                nextState = encodeState;
            end
        end
    
        // continue cleanup unless we're out of chars to write to window, then accept more chars if we can, or just search, and if we're out of chars completely, finish compression
        waitState: begin
            if (bestIterator > 0) begin
                nextState = waitState;
            end else begin
                resetSearch = 1;
                if (lastInputReceived == 1 && charsInBuffer == 0) begin
                    nextState = completeState;
                end else if (lastInputReceived == 1 && charsInBuffer > 0) begin
                    nextState = searchState;
                end else begin
                    nextState = inputState;
                end
            end
        end 
    endcase
end

endmodule