/**
 * Some utilities for working with bytes.
 */
module handy_httpd.util.byte_utils;

import streams;

/**
 * Reads data from a network stream, that is, one with network byte order,
 * which is big endian. This means that for reading arithmetic values, we need
 * to swap the byte order if the native endianness is little endian.
 * Params:
 *   stream = The stream to read from.
 * Returns: The result of reading a value from the stream.
 */
DataReadResult!T readNetworkData(T, S)(S stream) if (isByteInputStream!S) {
    auto dIn = dataInputStreamFor(stream);
    DataReadResult!T result = dIn.readFromStream!T();
    if (result.hasError) return result;
    // Network byte order is always Big Endian, so if we are opposite, we must swap byte order.
    version (LittleEndian) {
        static if (T.sizeof > 1 && __traits(isArithmetic, T)) {
            return DataReadResult!T(swapByteOrder(result.value));
        } else {
            return result;
        }
    } else {
        return result;
    }
}

/**
 * Swaps the byte order of a value.
 * Params:
 *   value = The value to swap the byte order of.
 * Returns: The value with its bytes swapped.
 */
T swapByteOrder(T)(T value) {
    static if (T.sizeof == 1) {
        return value;
    } else {
        union U {
            ubyte[T.sizeof] bytes;
            T value;
        }
        U u;
        u.value = value;
        ubyte tmp;
        static foreach (i; 0 .. T.sizeof / 2) {
            tmp = u.bytes[i];
            u.bytes[i] = u.bytes[T.sizeof - i - 1];
            u.bytes[T.sizeof - i - 1] = tmp;
        }
        return u.value;
    }
}

unittest {
    assert(swapByteOrder(cast(ubyte) 1) == 1);
}
