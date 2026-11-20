import math
import msgpack

def check(bool condition, str label):
    if not condition:
        raise ValueError("FAIL: " + label)

def golden(msgpack.Value value, bytes expected, str label):
    check(msgpack.packb(value) == expected, label)
    auto decoded = msgpack.unpackb(expected, strict_map_key=False)
    check(msgpack.packb(decoded) == expected, "round-trip " + label)

def integers():
    golden(msgpack.Value.Int(0), bytes([0x00]), "int 0")
    golden(msgpack.Value.Int(127), bytes([0x7f]), "int 127")
    golden(msgpack.Value.Int(128), bytes([0xcc, 0x80]), "int 128")
    golden(msgpack.Value.Int(255), bytes([0xcc, 0xff]), "int 255")
    golden(msgpack.Value.Int(256), bytes([0xcd, 0x01, 0x00]), "int 256")
    golden(msgpack.Value.Int(65535), bytes([0xcd, 0xff, 0xff]), "int 65535")
    golden(msgpack.Value.Int(65536), bytes([0xce, 0x00, 0x01, 0x00, 0x00]), "int 65536")
    golden(msgpack.Value.Int(4294967295), bytes([0xce, 0xff, 0xff, 0xff, 0xff]), "int 4294967295")
    golden(msgpack.Value.Int(4294967296), bytes([0xcf, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]), "int 4294967296")
    golden(msgpack.Value.Int(9223372036854775807), bytes([0xcf, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]), "int 9223372036854775807")
    golden(msgpack.Value.Int(-1), bytes([0xff]), "int -1")
    golden(msgpack.Value.Int(-32), bytes([0xe0]), "int -32")
    golden(msgpack.Value.Int(-33), bytes([0xd0, 0xdf]), "int -33")
    golden(msgpack.Value.Int(-128), bytes([0xd0, 0x80]), "int -128")
    golden(msgpack.Value.Int(-129), bytes([0xd1, 0xff, 0x7f]), "int -129")
    golden(msgpack.Value.Int(-32768), bytes([0xd1, 0x80, 0x00]), "int -32768")
    golden(msgpack.Value.Int(-32769), bytes([0xd2, 0xff, 0xff, 0x7f, 0xff]), "int -32769")
    golden(msgpack.Value.Int(-2147483648), bytes([0xd2, 0x80, 0x00, 0x00, 0x00]), "int -2147483648")
    golden(msgpack.Value.Int(-2147483649), bytes([0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff]), "int -2147483649")
    golden(msgpack.Value.Int(-9223372036854775807 - 1), bytes([0xd3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]), "int -9223372036854775808")
    golden(msgpack.Value.UInt(uint64(0)), bytes([0x00]), "uint 0")
    golden(msgpack.Value.UInt(uint64(128)), bytes([0xcc, 0x80]), "uint 128")
    golden(msgpack.Value.UInt(uint64(-9223372036854775807 - 1)), bytes([0xcf, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]), "uint 9223372036854775808")
    golden(msgpack.Value.UInt(uint64(-1)), bytes([0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]), "uint 18446744073709551615")

def floats():
    golden(msgpack.Value.Float(1.5), bytes([0xcb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0]), "float64 1.5")
    golden(msgpack.Value.Float(0.0), bytes([0xcb, 0, 0, 0, 0, 0, 0, 0, 0]), "float64 positive zero")
    golden(msgpack.Value.Float(-0.0), bytes([0xcb, 0x80, 0, 0, 0, 0, 0, 0, 0]), "float64 negative zero")
    golden(msgpack.Value.Float(math.inf), bytes([0xcb, 0x7f, 0xf0, 0, 0, 0, 0, 0, 0]), "float64 infinity")
    golden(msgpack.Value.Float(-math.inf), bytes([0xcb, 0xff, 0xf0, 0, 0, 0, 0, 0, 0]), "float64 negative infinity")
    golden(msgpack.Value.Float(math.nan), bytes([0xcb, 0x7f, 0xf8, 0, 0, 0, 0, 0, 0]), "float64 quiet NaN")
    golden(msgpack.Value.Float(math.pow(2.0, -1074.0)), bytes([0xcb, 0, 0, 0, 0, 0, 0, 0, 1]), "float64 smallest subnormal")
    golden(msgpack.Value.Float(math.pow(2.0, -1022.0)), bytes([0xcb, 0, 0x10, 0, 0, 0, 0, 0, 0]), "float64 smallest normal")
    auto largest = math.pow(2.0, 1023.0) * (2.0 - math.pow(2.0, -52.0))
    golden(msgpack.Value.Float(largest), bytes([0xcb, 0x7f, 0xef, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]), "float64 largest finite")

    single(1.5, bytes([0xca, 0x3f, 0xc0, 0, 0]), "float32 1.5")
    single(0.0, bytes([0xca, 0, 0, 0, 0]), "float32 positive zero")
    single(-0.0, bytes([0xca, 0x80, 0, 0, 0]), "float32 negative zero")
    single(math.inf, bytes([0xca, 0x7f, 0x80, 0, 0]), "float32 infinity")
    single(-math.inf, bytes([0xca, 0xff, 0x80, 0, 0]), "float32 negative infinity")
    single(math.nan, bytes([0xca, 0x7f, 0xc0, 0, 0]), "float32 quiet NaN")
    single(math.pow(2.0, -149.0), bytes([0xca, 0, 0, 0, 1]), "float32 smallest subnormal")
    single(math.pow(2.0, -150.0), bytes([0xca, 0, 0, 0, 0]), "float32 ties to zero")
    single(-math.pow(2.0, -151.0), bytes([0xca, 0x80, 0, 0, 0]), "float32 negative underflow")
    single(math.pow(2.0, -126.0), bytes([0xca, 0, 0x80, 0, 0]), "float32 smallest normal")
    single(1.0 + math.pow(2.0, -24.0), bytes([0xca, 0x3f, 0x80, 0, 0]), "float32 even tie rounds down")
    single(1.0 + 3.0 * math.pow(2.0, -24.0), bytes([0xca, 0x3f, 0x80, 0, 2]), "float32 odd tie rounds up")
    single(2.0 - math.pow(2.0, -25.0), bytes([0xca, 0x40, 0, 0, 0]), "float32 rounding carries into exponent")
    auto largest_single = math.pow(2.0, 127.0) * (2.0 - math.pow(2.0, -23.0))
    single(largest_single, bytes([0xca, 0x7f, 0x7f, 0xff, 0xff]), "float32 largest finite")
    single(math.pow(2.0, 128.0), bytes([0xca, 0x7f, 0x80, 0, 0]), "float32 overflow to infinity")

def single(float64 value, bytes expected, str label):
    check(msgpack.packb(msgpack.Value.Float(value), use_single_float=True) == expected, label)
    auto decoded = msgpack.unpackb(expected)
    check(msgpack.packb(decoded, use_single_float=True) == expected, "round-trip " + label)

def repeat(bytes unit, int64 count) -> bytes:
    auto output = b""
    while count > 0:
        if count % 2 == 1:
            output = output + unit
        count = count // 2
        if count > 0:
            unit = unit + unit
    return output

def text_length(int64 length, bytes header):
    auto payload = repeat(b"x", length)
    golden(msgpack.Value.Str(str(payload)), header + payload, "str length " + str(length))

def binary_length(int64 length, bytes header):
    auto payload = repeat(bytes([0, 128, 255]), length // 3) + repeat(bytes([255]), length % 3)
    golden(msgpack.Value.Bin(payload), header + payload, "bin length " + str(length))

def array_length(int64 length, bytes header):
    list[msgpack.Value] items = []
    auto index = 0
    while index < length:
        items.append(msgpack.Value.Nil)
        index = index + 1
    golden(msgpack.Value.Array(items), header + repeat(bytes([0xc0]), length), "array length " + str(length))

def map_length(int64 length, bytes header):
    list[(msgpack.Value, msgpack.Value)] pairs = []
    auto index = 0
    while index < length:
        pairs.append((msgpack.Value.Str("k"), msgpack.Value.Bool(True)))
        index = index + 1
    golden(msgpack.Value.Map(pairs), header + repeat(bytes([0xa1, 0x6b, 0xc3]), length), "map length " + str(length))

def lengths():
    text_length(0, bytes([0xa0]))
    text_length(31, bytes([0xbf]))
    text_length(32, bytes([0xd9, 32]))
    text_length(255, bytes([0xd9, 255]))
    text_length(256, bytes([0xda, 1, 0]))
    text_length(65535, bytes([0xda, 255, 255]))
    text_length(65536, bytes([0xdb, 0, 1, 0, 0]))
    golden(msgpack.Value.Str("é世界"), bytes([0xa8, 0xc3, 0xa9, 0xe4, 0xb8, 0x96, 0xe7, 0x95, 0x8c]), "UTF-8 byte length")
    binary_length(0, bytes([0xc4, 0]))
    binary_length(255, bytes([0xc4, 255]))
    binary_length(256, bytes([0xc5, 1, 0]))
    binary_length(65535, bytes([0xc5, 255, 255]))
    binary_length(65536, bytes([0xc6, 0, 1, 0, 0]))
    array_length(0, bytes([0x90]))
    array_length(15, bytes([0x9f]))
    array_length(16, bytes([0xdc, 0, 16]))
    array_length(65535, bytes([0xdc, 255, 255]))
    array_length(65536, bytes([0xdd, 0, 1, 0, 0]))
    map_length(0, bytes([0x80]))
    map_length(15, bytes([0x8f]))
    map_length(16, bytes([0xde, 0, 16]))
    map_length(65535, bytes([0xde, 255, 255]))
    map_length(65536, bytes([0xdf, 0, 1, 0, 0]))

def nested():
    auto value = msgpack.Value.Map([
        (msgpack.Value.Str("k"), msgpack.Value.Array([msgpack.Value.Int(1), msgpack.Value.Bin(b"k")])),
        (msgpack.Value.Str("k"), msgpack.Value.Nil),
        (msgpack.Value.Int(2), msgpack.Value.Map([(msgpack.Value.Bin(b"k"), msgpack.Value.Bool(False))])),
    ])
    golden(value, bytes([0x83, 0xa1, 0x6b, 0x92, 1, 0xc4, 1, 0x6b, 0xa1, 0x6b, 0xc0, 2, 0x81, 0xc4, 1, 0x6b, 0xc2]), "nested maps preserve duplicate keys and pair order")
    auto float_array = msgpack.Value.Array([msgpack.Value.Float(1.5)])
    check(msgpack.packb(float_array, use_single_float=True) == bytes([0x91, 0xca, 0x3f, 0xc0, 0, 0]), "float option propagates to nested values")

def rejected(msgpack.Value value, str expected):
    auto did_reject = False
    try:
        msgpack.packb(value)
    except ValueError as error:
        check(error.find(expected) >= 0, "packb rejects with expected diagnostic")
        did_reject = True
    check(did_reject, "packb must reject " + expected)

def invalid():
    auto extension = msgpack.Value.Ext(msgpack.ExtType(128, b"x"))
    rejected(extension, "application extension code")
    rejected(msgpack.Value.Array([extension]), "application extension code")
    rejected(msgpack.Value.Timestamp(msgpack.Timestamp(0, uint32(0))), "timestamps")

    msgpack.Value deep = msgpack.Value.Nil
    auto depth = 0
    while depth < 1024:
        deep = msgpack.Value.Array([deep])
        depth = depth + 1
    golden(deep, repeat(bytes([0x91]), 1024) + bytes([0xc0]), "maximum nesting depth")
    rejected(msgpack.Value.Array([deep]), "recursion limit")

def main():
    golden(msgpack.Value.Nil, bytes([0xc0]), "nil")
    golden(msgpack.Value.Bool(False), bytes([0xc2]), "false")
    golden(msgpack.Value.Bool(True), bytes([0xc3]), "true")
    integers()
    floats()
    lengths()
    nested()
    invalid()
    print("MessagePack packb golden and rejection tests: PASS")
