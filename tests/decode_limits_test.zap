def check(bool condition, str label):
    assert condition, label

def one(bytes wire, int64 limit, int64 depth = 1024, bool raw = False) -> str:
    try:
        unpackb(wire, raw=raw, max_str_len=limit, max_bin_len=limit, max_array_len=limit, max_map_len=limit, max_ext_len=limit, max_depth=depth)
    except StrLimitError:
        return "str"
    except BinLimitError:
        return "bin"
    except ArrayLimitError:
        return "array"
    except MapLimitError:
        return "map"
    except ExtLimitError:
        return "ext"
    except StackError:
        return "depth"
    except OutOfData:
        return "incomplete"
    except ValueError:
        return "configuration"
    return "ok"

def stream(Unpacker reader) -> str:
    try:
        reader.unpack()
    except StrLimitError:
        return "str"
    except BinLimitError:
        return "bin"
    except ArrayLimitError:
        return "array"
    except MapLimitError:
        return "map"
    except ExtLimitError:
        return "ext"
    except StackError:
        return "depth"
    except OutOfData:
        return "incomplete"
    except ValueError:
        return "configuration"
    return "ok"

def check_both(bytes wire, int64 limit, str expected, int64 depth = 1024, bool raw = False):
    check(one(wire, limit, depth=depth, raw=raw) == expected, "one-shot " + expected)
    auto reader = Unpacker(raw=raw, max_str_len=limit, max_bin_len=limit, max_array_len=limit, max_map_len=limit, max_ext_len=limit, max_depth=depth)
    reader.feed(wire)
    check(stream(reader) == expected, "stream " + expected)
    if expected != "ok":
        check(stream(reader) == expected, "stream retry " + expected)

def boundary(bytes wire, int64 length, str kind):
    check_both(wire, length, "ok")
    check_both(wire, length + 1, "ok")
    check_both(wire, length - 1, kind)

@test
def test_exact_length_boundaries():
    boundary(bytes([0xa2, 0xc3, 0xa9]), 2, "str")
    boundary(bytes([0xc4, 2, 0, 255]), 2, "bin")
    boundary(bytes([0x92, 0xc0, 0xc0]), 2, "array")
    boundary(bytes([0x82, 0xa0, 0xc0, 0xa0, 0xc0]), 2, "map")
    boundary(bytes([0xd5, 42, 0, 255]), 2, "ext")
    boundary(bytes([0xd6, 255, 0, 0, 0, 0]), 4, "ext")
    for wire in [bytes([0xa0]), bytes([0xc4, 0]), bytes([0x90]), bytes([0x80]), bytes([0xc7, 0, 42])]:
        check_both(wire, 0, "ok")
    check_both(bytes([0xa2, 0xc3, 0xa9]), 1, "str", raw=True)
    check_both(bytes([0x81, 0xa2, 0x61, 0x62, 0xc0]), 1, "str")
    check_both(bytes([0x91, 0xc4, 2, 0, 255]), 1, "bin")
    check_both(bytes([0x91, 0x92, 0xc0, 0xc0]), 1, "array")
    check_both(bytes([0x91, 0x82, 0xa0, 0xc0, 0xa0, 0xc0]), 1, "map")
    check_both(bytes([0x91, 0xd5, 42, 0, 255]), 1, "ext")

    auto raw_string = unpackb(bytes([0xa1, 255]), raw=True, max_str_len=1, max_bin_len=0)
    check(packb(raw_string) == bytes([0xc4, 1, 255]), "raw strings use only the string wire limit")
    auto bin = unpackb(bytes([0xc4, 1, 255]), max_str_len=0, max_bin_len=1)
    check(packb(bin) == bytes([0xc4, 1, 255]), "bin values use only the binary wire limit")
    auto reader = Unpacker(raw=True, max_str_len=1, max_bin_len=0)
    reader.feed(bytes([0xa1, 255, 0xc4, 1, 255]))
    check(packb(reader.unpack()) == bytes([0xc4, 1, 255]), "stream yields raw string at limit")
    check(stream(reader) == "bin", "stream rejects following binary under its own cap")

@test
def test_declared_lengths_and_split_headers():
    for wire in [bytes([0xa2]), bytes([0xd9, 2]), bytes([0xda, 0, 2]), bytes([0xdb, 0, 0, 0, 2])]:
        check_both(wire, 1, "str")
        check_both(wire, -1, "incomplete")
    for wire in [bytes([0xc4, 2]), bytes([0xc5, 0, 2]), bytes([0xc6, 255, 255, 255, 255])]:
        check_both(wire, 1, "bin")
        check_both(wire, -1, "incomplete")
    for wire in [bytes([0x92]), bytes([0xdc, 0, 2]), bytes([0xdd, 255, 255, 255, 255])]:
        check_both(wire, 1, "array")
        check_both(wire, -1, "incomplete")
    for wire in [bytes([0x82]), bytes([0xde, 0, 2]), bytes([0xdf, 255, 255, 255, 255])]:
        check_both(wire, 1, "map")
        check_both(wire, -1, "incomplete")
    for wire in [bytes([0xd5]), bytes([0xc7, 2]), bytes([0xc8, 0, 2]), bytes([0xc9, 255, 255, 255, 255])]:
        check_both(wire, 1, "ext")
        check_both(wire, -1, "incomplete")

    auto split = Unpacker(max_bin_len=1)
    split.feed(bytes([0xc5, 0]))
    check(stream(split) == "incomplete", "not enough bytes for length")
    split.feed(bytes([2]))
    check(stream(split) == "bin", "rejects before missing body arrives")
    check(stream(split) == "bin", "retry preserves final length octet")
    split.max_bin_len = 2
    split.feed(bytes([0, 255]))
    check(packb(split.unpack()) == bytes([0xc4, 2, 0, 255]), "the original frame survives a rejected read")

@test
def test_depth_and_invalid_configuration():
    check_both(bytes([0xc0]), -1, "ok", depth=0)
    check_both(bytes([0x90]), -1, "ok", depth=0)
    check_both(bytes([0x91, 0xc0]), -1, "depth", depth=0)
    check_both(bytes([0x81, 0xa0, 0xc0]), -1, "depth", depth=0)
    check_both(bytes([0x91, 0x81, 0xa0, 0xc0]), -1, "ok", depth=2)
    check_both(bytes([0x91, 0x81, 0xa0, 0xc0]), -1, "depth", depth=1)
    check_both(bytes([0xc0]), -2, "configuration")
    check_both(bytes([0xc0]), -1, "configuration", depth=-1)
    check_both(bytes([0xc0]), -1, "configuration", depth=1025)
