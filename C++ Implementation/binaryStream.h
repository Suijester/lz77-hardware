#ifndef BINSTREAM_H
#define BINSTREAM_H

#include <vector>
#include <string>

#pragma pack(push, 1)
class binaryStream {
public:
    void writeBit(bool bit); // write a single bit (flag)
    void writeBits(uint32_t value, int length); // write a number to bits
    void flushByte(); // push a non-full byte to bitStream
    void pushByte(); // push a full byte to bitStream
    const std::vector<uint8_t>& getByteStream(); // 
private:
    std::vector<uint8_t> bitStream;
    int bitPosition = 0;
    uint8_t currentByte = 0;
};
#pragma pack(pop)

std::vector<uint8_t> compress(const std::string& stream);
std::string decompress(const std::vector<uint8_t>& tokens);

#endif