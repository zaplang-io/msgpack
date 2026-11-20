import msgpack

def check(bool condition, str label):
    if not condition:
        raise ValueError("FAIL: " + label)

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
        msgpack.unpackb(wire)
    except msgpack.OutOfData:
        return
    raise ValueError("Expected truncated generated value")

def expect_trailing(bytes wire):
    try:
        msgpack.unpackb(wire)
    except msgpack.ExtraData:
        return
    raise ValueError("Expected generated trailing bytes to fail")

def expect_reserved(bytes wire):
    try:
        msgpack.unpackb(wire)
    except msgpack.FormatError:
        return
    raise ValueError("Expected generated reserved tag to fail")

def structured_corpus():
    auto seed = 322
    for sample in range(0, 256):
        seed = next_seed(seed)
        auto wire = generated_value(seed, 5)
        check(msgpack.packb(msgpack.unpackb(wire)) == wire, "generated canonical frame " + str(sample))
        auto split = seed % len(wire)
        auto reader = msgpack.Unpacker(max_buffer_size=len(wire))
        reader.feed(wire[0:split])
        reader.feed(wire[split:len(wire)])
        check(msgpack.packb(reader.unpack()) == wire, "generated streaming frame " + str(sample))
        auto end = 0
        while end < len(wire):
            expect_incomplete(wire[0:end])
            end = end + 1
        expect_reserved(bytes([0xc1]) + wire[1:len(wire)])
        expect_trailing(wire + bytes([0xc1]))

def decode_arbitrary(bytes wire) -> bool:
    msgpack.Value parsed = msgpack.Value.Nil
    try:
        parsed = msgpack.unpackb(wire, max_str_len=16, max_bin_len=16, max_array_len=8, max_map_len=8, max_ext_len=16, max_depth=8)
    except msgpack.OutOfData:
        return False
    except msgpack.FormatError:
        return False
    except msgpack.ExtraData:
        return False
    except msgpack.StrLimitError:
        return False
    except msgpack.BinLimitError:
        return False
    except msgpack.ArrayLimitError:
        return False
    except msgpack.MapLimitError:
        return False
    except msgpack.ExtLimitError:
        return False
    except msgpack.StackError:
        return False
    auto canonical = msgpack.packb(parsed)
    check(msgpack.packb(msgpack.unpackb(canonical)) == canonical, "accepted arbitrary input canonicalizes consistently")
    return True

def arbitrary_corpus():
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

def main():
    structured_corpus()
    arbitrary_corpus()
    print("Generated MessagePack corpus seeds 322 and 1919: PASS")
