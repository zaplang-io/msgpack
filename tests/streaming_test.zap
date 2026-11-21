def check(bool condition, str label):
    assert condition, label

def empty(Unpacker reader, str label):
    try:
        reader.unpack()
    except OutOfData:
        return
    raise ValueError("Expected OutOfData: " + label)

def expect(Unpacker reader, bytes wire, str label):
    check(packb(reader.unpack()) == wire, label)

def split(bytes wire):
    auto offset = 0
    while offset < len(wire):
        auto reader = Unpacker()
        reader.feed(wire[0:offset])
        empty(reader, "prefix")
        empty(reader, "retry with no new bytes")
        reader.feed(wire[offset:len(wire)])
        expect(reader, wire, "once completed")
        empty(reader, "after one value")
        offset = offset + 1

@test
def test_value_splits():
    list[bytes] wires = [
        bytes([0xc0]), bytes([0xc2]), bytes([0xc3]), bytes([127]), bytes([0xe0]),
        bytes([0xcc, 128]), bytes([0xcd, 1, 0]), bytes([0xce, 0, 1, 0, 0]), bytes([0xcf, 0, 0, 0, 1, 0, 0, 0, 0]),
        bytes([0xd0, 0xdf]), bytes([0xd1, 0xff, 0x7f]), bytes([0xd2, 0xff, 0xff, 0x7f, 0xff]),
        bytes([0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff]),
        bytes([0xcb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0]), bytes([0xa0]), bytes([0xa2, 0xc3, 0xa9]),
        bytes([0xc4, 0]), bytes([0xc4, 1, 0xff]), bytes([0x90]), bytes([0x80]),
        bytes([0x83, 0xa1, 0x6b, 0x92, 0xcc, 128, 0x80, 0xa1, 0x6b, 0xc0, 0xc4, 1, 0x6b, 0x81, 0xa0, 0x90]),
    ]
    for wire in wires:
        split(wire)

    # Exercise every length-header width, including valid noncanonical forms.
    list[bytes] long_headers = [
        bytes([0xc5, 0, 1, 0xff]), bytes([0xc6, 0, 0, 0, 1, 0xff]),
        bytes([0xd9, 1, 0x78]), bytes([0xda, 0, 1, 0x78]), bytes([0xdb, 0, 0, 0, 1, 0x78]),
        bytes([0xdc, 0, 1, 0xc0]), bytes([0xdd, 0, 0, 0, 1, 0xc0]),
        bytes([0xde, 0, 1, 0xa0, 0xc0]), bytes([0xdf, 0, 0, 0, 1, 0xa0, 0xc0]),
        bytes([0xca, 0x3f, 0xc0, 0, 0]), bytes([0xdd, 0, 0, 0, 0]), bytes([0xdf, 0, 0, 0, 0]),
    ]
    for wire in long_headers:
        auto reader = Unpacker()
        auto expected = packb(unpackb(wire))
        auto index = 0
        while index < len(wire):
            empty(reader, "one byte at a time before final byte")
            reader.feed(wire[index:index + 1])
            index = index + 1
        expect(reader, expected, "resumed wire header")

@test
def test_coalesced_values():
    auto writer = Packer()
    auto single = Packer(use_single_float=True)
    check(single.pack(Value.Float(1.5)) == bytes([0xca, 0x3f, 0xc0, 0, 0]), "packer retains float option")
    check(writer.pack(Value.Float(1.5)) == bytes([0xcb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0]), "independent default packer")
    auto reader = Unpacker()
    auto independent = Unpacker()
    reader.feed(writer.pack(Value.Int(7)) + writer.pack(Value.Nil) + bytes([0xc4]))
    empty(independent, "unpackers do not share input")
    auto drained = b""
    for value in reader:
        drained = drained + writer.pack(value)
    check(drained == bytes([7, 0xc0]), "iteration drains complete values in order")
    empty(reader, "coalesced buffer retains an incomplete header")
    reader.feed(bytes([2, 0xff]))
    reader.feed(bytes([0, 8]))
    expect(reader, bytes([0xc4, 2, 0xff, 0]), "resumes partial head and keeps surplus")
    drained = b""
    for value in reader:
        drained = drained + writer.pack(value)
    check(drained == bytes([8]), "iteration resumes after more data")
    empty(reader, "coalesced input drained")

def full(Unpacker reader, bytes chunk):
    try:
        reader.feed(chunk)
    except BufferFull:
        return
    raise ValueError("Expected BufferFull")

@test
def test_stream_buffer_limits():
    auto reader = Unpacker(max_buffer_size=4)
    full(reader, bytes([0xc0, 0xc0, 0xc0, 0xc0, 0xc0]))
    empty(reader, "rejected chunk is atomic")
    reader.feed(bytes([0xc4, 2]))
    empty(reader, "stalled frame")
    full(reader, bytes([1, 2, 3]))
    reader.feed(bytes([1, 2]))
    reader.feed(b"")
    full(reader, bytes([3]))
    expect(reader, bytes([0xc4, 2, 1, 2]), "exact cap succeeds after rejected feed")
    reader.feed(bytes([3, 4, 5, 6]))
    expect(reader, bytes([3]), "consumption releases capacity")
    reader.feed(bytes([7]))
    full(reader, bytes([8]))
    expect(reader, bytes([4]), "partial-head consumption releases capacity")

    auto large_claim = Unpacker(max_buffer_size=8)
    large_claim.feed(bytes([0xc6, 0xff, 0xff, 0xff, 0xff, 1, 2, 3]))
    empty(large_claim, "declared length alone cannot allocate the payload")
    full(large_claim, bytes([4]))
    empty(large_claim, "full buffer retained consistently")

    auto zero = Unpacker(max_buffer_size=0)
    zero.feed(bytes([0xc0]))
    expect(zero, bytes([0xc0]), "zero selects the protocol-scale default")
    auto negative = Unpacker(max_buffer_size=-1)
    try:
        negative.feed(bytes([0xc0]))
    except ValueError:
        return
    raise ValueError("Expected negative max_buffer_size rejection")

@test
def test_bytewise_payload():
    auto reader = Unpacker(max_buffer_size=1027)
    reader.feed(bytes([0xc5, 4, 0]))
    auto index = 0
    auto payload = b"x"
    while len(payload) < 1024:
        payload = payload + payload
    while index < len(payload):
        empty(reader, "partial body while chunks are merged")
        reader.feed(b"x")
        index = index + 1
    expect(reader, bytes([0xc5, 4, 0]) + payload, "one-byte feeds reconstruct entire body")

def invalid(Unpacker reader):
    try:
        for value in reader:
            raise ValueError("Malformed payload unexpectedly yielded a value")
    except FormatError:
        return
    raise ValueError("Expected FormatError during iteration")

@test
def test_malformed_streams():
    for wire in [bytes([0xc1]), bytes([0xa1, 0xff]), bytes([0x81, 1, 0xc0]), bytes([0xd4, 0xfe, 0])]:
        auto reader = Unpacker()
        reader.feed(bytes([0xc0]) + wire)
        expect(reader, bytes([0xc0]), "valid prefix before malformed value")
        invalid(reader)
        invalid(reader)

    auto raw = Unpacker(raw=True, strict_map_key=False)
    raw.feed(bytes([0x81, 1, 0xa1, 0xff]))
    expect(raw, bytes([0x81, 1, 0xc4, 1, 0xff]), "stream options forwarded to decoder")

    auto deep = Unpacker()
    auto prefix = bytes([0x91])
    while len(prefix) < 1024:
        prefix = prefix + prefix
    deep.feed(prefix + bytes([0xc0]))
    expect(deep, prefix + bytes([0xc0]), "maximum nesting depth")
    deep.feed(prefix + bytes([0x91, 0xc0]))
    try:
        deep.unpack()
    except StackError:
        return
    raise ValueError("Expected StackError")
