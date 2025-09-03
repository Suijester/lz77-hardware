#include "binaryStream.h"

int readBits(const int bitPosition, const std::vector<uint8_t>& byteStream, const int bitCount) {
    uint16_t result = 0;
    for (uint8_t i = 0; i < bitCount; i++) {
        int byteIndex = (bitPosition + i) / 8;
        int bitIndex = 7 - ((bitPosition + i) % 8);
        uint8_t bit = (byteStream[byteIndex] >> bitIndex) & 1;
        result = (result << 1) | bit;
    }
    return result;
}

std::string decompress(const std::vector<uint8_t>& byteStream) {
    std::string data = "";
    int bitPosition = 0;
    while (bitPosition < byteStream.size() * 8) {
        int flag = readBits(bitPosition, byteStream, 1);
        bitPosition++;
        if (flag == 1) {
            char literal = static_cast<char>(readBits(bitPosition, byteStream, 8));
            bitPosition += 8;
            data.push_back(literal);
        } else {
            int offset = readBits(bitPosition, byteStream, 12);
            bitPosition += 12;
            int length = readBits(bitPosition, byteStream, 6);
            bitPosition += 6;
            int currentPosition = data.size() - offset;
            for (int i = 0; i < length; i++) {
                data.push_back(data[currentPosition + i]);
            }
        }
    }
    return data;
}