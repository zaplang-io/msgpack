def check(bool condition, str label):
    assert condition, label

# Fixed seed and recurrence keep every generated failure reproducible.
def next_seed(int64 seed) -> int64:
    return (seed * 251 + 13849) % 65521

# Construct canonical frames independently of packb and the decoder.
def generated_value(int64 seed, int64 depth) -> bytes:
    auto kind = seed % 9
    if depth == 0:
        kind = seed % 6
    if kind == 0:
        return bytes([0xc0])
    if kind == 1:
        return bytes([seed % 128])
    if kind == 2:
        return bytes([0xd1, 0xfe, seed % 256])
    if kind == 3:
        return bytes([0xa2, 0xc3, 0xa9])
    if kind == 4:
        return bytes([0xc4, 3, 0, seed % 256, 255])
    if kind == 5:
        return bytes([0xd4, seed % 128, 255])
    auto next = next_seed(seed)
    if kind == 6:
        return bytes([0x92]) + generated_value(next, depth - 1) + generated_value(next_seed(next), depth - 1)
    if kind == 7:
        return bytes([0x81, 0xa1, 0x6b]) + generated_value(next, depth - 1)
    return bytes([0x91]) + generated_value(next, depth - 1)

def expect_incomplete(bytes wire):
    try:
        unpackb(wire)
    except OutOfData:
        return
    raise ValueError("Expected truncated generated value")

def expect_trailing(bytes wire):
    try:
        unpackb(wire)
    except ExtraData:
        return
    raise ValueError("Expected generated trailing bytes to fail")

def expect_reserved(bytes wire):
    try:
        unpackb(wire)
    except FormatError:
        return
    raise ValueError("Expected generated reserved tag to fail")

@test
def test_generated_structured_corpus():
    auto seed = 322
    for sample in range(0, 256):
        seed = next_seed(seed)
        auto wire = generated_value(seed, 5)
        check(packb(unpackb(wire)) == wire, "generated canonical frame " + str(sample))
        auto split = seed % len(wire)
        auto reader = Unpacker(max_buffer_size=len(wire))
        reader.feed(wire[0:split])
        reader.feed(wire[split:len(wire)])
        check(packb(reader.unpack()) == wire, "generated streaming frame " + str(sample))
        auto end = 0
        while end < len(wire):
            expect_incomplete(wire[0:end])
            end = end + 1
        expect_reserved(bytes([0xc1]) + wire[1:len(wire)])
        expect_trailing(wire + bytes([0xc1]))

def decode_arbitrary(bytes wire) -> bool:
    Value parsed = Value.Nil
    try:
        parsed = unpackb(wire, max_str_len=16, max_bin_len=16, max_array_len=8, max_map_len=8, max_ext_len=16, max_depth=8)
    except OutOfData:
        return False
    except FormatError:
        return False
    except ExtraData:
        return False
    except StrLimitError:
        return False
    except BinLimitError:
        return False
    except ArrayLimitError:
        return False
    except MapLimitError:
        return False
    except ExtLimitError:
        return False
    except StackError:
        return False
    auto canonical = packb(parsed)
    check(packb(unpackb(canonical)) == canonical, "accepted arbitrary input canonicalizes consistently")
    return True

@test
def test_generated_arbitrary_corpus():
    auto seed = 1919
    auto accepted = 0
    for sample in range(0, 512):
        seed = next_seed(seed)
        auto count = seed % 64
        list[int64] octets = []
        for index in range(0, count):
            seed = next_seed(seed)
            octets.append(seed % 256)
        if decode_arbitrary(bytes(octets)):
            accepted = accepted + 1
    check(accepted > 0 and accepted < 512, "arbitrary corpus includes accepted and rejected cases")
