#include "binaryStream.h"

void binaryStream::writeBit(bool bit) {
    if (bit == 1) {
        currentByte |= (1 << (7 - bitPosition)); // if bit is 1, then shift the 1 bit to the left and add it to the current byte
    }
    bitPosition++;
    if (bitPosition == 8) { // if bitPosition == 8, we've exceeded a byte, so push byte into bitStream
        pushByte();
    }
}

void binaryStream::writeBits(uint32_t value, int length) {
    if (length <= 0) {
        return;
    }
    for (int i = length - 1; i >= 0; i--) {
        writeBit((value >> i) & 1);
    }
}

void binaryStream::pushByte() {
    bitStream.push_back(currentByte);
    currentByte = 0;
    bitPosition = 0;
}

void binaryStream::flushByte() {
    if (bitPosition > 0) {
        pushByte();
    }
}

const std::vector<uint8_t>& binaryStream::getByteStream() {
    return bitStream;
}