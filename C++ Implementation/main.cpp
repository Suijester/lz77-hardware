#include "binaryStream.h"
#include <iostream>
#include <cassert>
using namespace std;

int main() {
    string data = "abracadabra"; // insert test data
    cout << compress(data).size() << ", " << data.size() << endl;

    assert(decompress(compress(data)) == data);
}