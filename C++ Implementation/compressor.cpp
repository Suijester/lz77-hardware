#include "binaryStream.h"

std::vector<uint8_t> compress(const std::string& inStream) {
    binaryStream binEncoder;
    const uint16_t windowSize = 4095;
    const uint8_t bufferSize = 63;

    unsigned int position = 0;

    if (inStream.empty()) {
        return {};
    }

    while (position < inStream.size()) {
        uint8_t bestLength = 0;
        uint16_t bestOffset = 0;

        unsigned int windowStart = 0;
        if (position > windowSize) {
            windowStart = position - windowSize;
        }

        for (unsigned int i = windowStart; i < position; i++) {
            int slidingLength = 0;
            while (position + slidingLength < inStream.size() &&
                  inStream[i + slidingLength] == inStream[position + slidingLength] && 
                  slidingLength < bufferSize) {
                slidingLength++;
            }
                
            if (slidingLength > bestLength) {
                bestLength = slidingLength;
                bestOffset = position - i;
            }
        }
        if (bestLength >= 3) { // match of 2 emits 19 bits, two literals emits 18, so length of 3 is when match is better than literals
            binEncoder.writeBit(0);
            binEncoder.writeBits(bestOffset, 12);
            binEncoder.writeBits(bestLength, 6);
            position += bestLength;
        } else {
            binEncoder.writeBit(1);
            binEncoder.writeBits((uint8_t)inStream[position], 8);
            position++;
        }
    }
    binEncoder.flushByte();
    return binEncoder.getByteStream();
}