def check(bool condition, str label):
    assert condition, label

def fails(bytes wire, str expected, str label, bool raw = False):
    auto caught = ""
    try:
        unpackb(wire, raw=raw)
    except OutOfData:
        caught = "incomplete"
    except ExtraData:
        caught = "trailing"
    except FormatError:
        caught = "format"
    except StackError:
        caught = "stack"
    check(caught == expected, label + " expected " + expected + ", got " + caught)

def canonical(bytes wire, bytes expected, str label):
    check(packb(unpackb(wire)) == expected, label)

def expect_int(Value value, int64 expected, str label):
    match value:
        case Value.Int(number):
            check(number == expected, label)
        case _:
            raise ValueError("Expected Int: " + label)

@test
def test_numeric_decoding():
    expect_int(unpackb(bytes([0xd0, 1])), 1, "positive int8")
    expect_int(unpackb(bytes([0xd1, 0, 1])), 1, "positive int16")
    expect_int(unpackb(bytes([0xd2, 0, 0, 0, 1])), 1, "positive int32")
    expect_int(unpackb(bytes([0xd3, 0, 0, 0, 0, 0, 0, 0, 1])), 1, "positive int64")
    expect_int(unpackb(bytes([0xcf, 0, 0, 0, 0, 0, 0, 0, 1])), 1, "small uint64")
    expect_int(unpackb(bytes([0xcf, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])), 9223372036854775807, "uint64 at Int maximum")
    auto wide = unpackb(bytes([0xcf, 0x80, 0, 0, 0, 0, 0, 0, 0]))
    match wide:
        case Value.UInt(number):
            check(number == uint64(-9223372036854775807 - 1), "uint64 above Int maximum")
        case _:
            raise ValueError("Expected UInt above Int maximum")
    canonical(bytes([0xcd, 0, 127]), bytes([127]), "noncanonical unsigned width")
    canonical(bytes([0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]), bytes([0xff]), "noncanonical signed width")
    canonical(bytes([0xca, 0x3f, 0xc0, 0, 0]), bytes([0xcb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0]), "float32 widens to float64")
    canonical(bytes([0xcb, 0xff, 0xf8, 0, 0, 0, 0, 0, 1]), bytes([0xcb, 0x7f, 0xf8, 0, 0, 0, 0, 0, 0]), "noncanonical quiet NaN")

@test
def test_raw_text_and_map_keys():
    auto text = bytes([0xa2, 0xc3, 0xa9])
    match unpackb(text):
        case Value.Str(value):
            check(value == "é", "default string is UTF-8 text")
        case _:
            raise ValueError("Expected Str")
    match unpackb(text, raw=True):
        case Value.Bin(value):
            check(value == bytes([0xc3, 0xa9]), "raw string keeps UTF-8 bytes")
        case _:
            raise ValueError("Expected Bin")

    auto mixed_keys = bytes([0x83, 0xa1, 0x6b, 1, 0xc4, 1, 0x6b, 2, 0xa1, 0x6b, 3])
    canonical(mixed_keys, mixed_keys, "strict accepts string and binary keys in input order")
    auto raw_keys = unpackb(mixed_keys, raw=True)
    check(packb(raw_keys) == bytes([0x83, 0xc4, 1, 0x6b, 1, 0xc4, 1, 0x6b, 2, 0xc4, 1, 0x6b, 3]), "raw keeps all key pairs even when keys coincide")

    list[bytes] disallowed = [
        bytes([0xc0]), bytes([0xc2]), bytes([1]),
        bytes([0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
        bytes([0xca, 0, 0, 0, 0]), bytes([0x91, 1]), bytes([0x80]),
    ]
    for key in disallowed:
        auto map_wire = bytes([0x81]) + key + bytes([0xc0])
        fails(map_wire, "format", "strict map key")
        fails(map_wire, "format", "raw does not disable strict keys", raw=True)
        auto permissive = unpackb(map_wire, strict_map_key=False)
        if key[0] == 0xca:
            check(packb(permissive, use_single_float=True) == map_wire, "nonstrict float key")
        else:
            check(packb(permissive) == map_wire, "nonstrict accepts arbitrary key")
    fails(bytes([0x81, 0xa1, 0x6b, 0x91, 0x81, 1, 2]), "format", "strict checks nested map keys")

def check_prefixes(bytes wire):
    auto end = 0
    while end < len(wire):
        fails(wire[0:end], "incomplete", "truncated tag " + str(wire[0]) + " at " + str(end))
        end = end + 1

@test
def test_malformed_and_trailing_input():
    list[bytes] valid = [
        bytes([0xc0]), bytes([0xcc, 128]), bytes([0xcd, 1, 0]), bytes([0xce, 0, 1, 0, 0]),
        bytes([0xcf, 0, 0, 0, 1, 0, 0, 0, 0]), bytes([0xd0, 0xdf]), bytes([0xd1, 0xff, 0x7f]),
        bytes([0xd2, 0xff, 0xff, 0x7f, 0xff]), bytes([0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff]),
        bytes([0xca, 0x3f, 0xc0, 0, 0]), bytes([0xcb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0]),
        bytes([0xa2, 0xc3, 0xa9]), bytes([0xd9, 1, 0x78]), bytes([0xda, 0, 1, 0x78]), bytes([0xdb, 0, 0, 0, 1, 0x78]),
        bytes([0xc4, 1, 0xff]), bytes([0xc5, 0, 1, 0xff]), bytes([0xc6, 0, 0, 0, 1, 0xff]),
        bytes([0x91, 0xcc, 128]), bytes([0xdc, 0, 1, 0xcc, 128]), bytes([0xdd, 0, 0, 0, 1, 0xcc, 128]),
        bytes([0x81, 0xa1, 0x6b, 0xcc, 128]), bytes([0xde, 0, 1, 0xa1, 0x6b, 0xcc, 128]), bytes([0xdf, 0, 0, 0, 1, 0xa1, 0x6b, 0xcc, 128]),
    ]
    for wire in valid:
        unpackb(wire)
        check_prefixes(wire)
        fails(wire + bytes([0xc0]), "trailing", "extra valid value")
        fails(wire + bytes([0xc1, 0xcc]), "trailing", "extra invalid bytes")
    for tag in [0xc6, 0xdb, 0xdd, 0xdf]:
        fails(bytes([tag, 0xff, 0xff, 0xff, 0xff]), "incomplete", "oversized claimed length")
    fails(bytes([0xc1]), "format", "reserved tag")
    fails(bytes([0x91, 0xc1]), "format", "reserved tag inside array")
    fails(bytes([0x81, 0xa1, 0x6b, 0xc1]), "format", "reserved tag inside map")
    for tag in [0xc7, 0xc8, 0xc9, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8]:
        fails(bytes([tag]), "incomplete", "extension tag needs code and payload")

    for wire in [bytes([0xa1, 0xff]), bytes([0xa1, 0xc3]), bytes([0xa2, 0xc0, 0x80]), bytes([0xa3, 0xed, 0xa0, 0x80])]:
        fails(wire, "format", "malformed UTF-8 string")
        auto payload = wire[1:len(wire)]
        check(packb(unpackb(wire, raw=True)) == bytes([0xc4, len(payload)]) + payload, "raw bypasses UTF-8 validation")
    fails(bytes([0x81, 0xa1, 0xff, 0xc0]), "format", "malformed UTF-8 key")
    auto raw_key = unpackb(bytes([0x81, 0xa1, 0xff, 0xc0]), raw=True)
    check(packb(raw_key) == bytes([0x81, 0xc4, 1, 0xff, 0xc0]), "strict raw mode accepts non-UTF-8 string key as bytes")

@test
def test_decode_nesting_limit():
    auto prefix = bytes([0x91])
    auto levels = 1
    while levels < 1024:
        prefix = prefix + prefix
        levels = levels * 2
    auto accepted = prefix + bytes([0xc0])
    canonical(accepted, accepted, "maximum nesting depth")
    fails(bytes([0x91]) + accepted, "stack", "nested arrays exceed depth limit")
    fails(bytes([0x81, 0xa1, 0x6b]) + accepted, "stack", "nested map values count toward depth")
