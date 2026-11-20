import msgpack

def check(bool condition, str label):
    if not condition:
        raise ValueError("FAIL: " + label)

def check_timestamp(msgpack.Value value, int64 seconds, uint32 nanoseconds):
    match value:
        case msgpack.Value.Timestamp(timestamp):
            check(timestamp.seconds == seconds, "timestamp seconds")
            check(timestamp.nanoseconds == nanoseconds, "timestamp nanoseconds")
        case _:
            raise ValueError("Expected Timestamp")

def golden(int64 seconds, uint32 nanoseconds, bytes wire):
    auto stamp = msgpack.Value.Timestamp(msgpack.Timestamp(seconds, nanoseconds))
    check(msgpack.packb(stamp) == wire, "timestamp wire for seconds " + str(seconds))
    check(msgpack.Packer().pack(stamp) == wire, "stream packer timestamp")
    check_timestamp(msgpack.unpackb(wire), seconds, nanoseconds)
    check_timestamp(msgpack.unpackb(wire, raw=True), seconds, nanoseconds)

def widths():
    golden(0, uint32(0), bytes([0xd6, 0xff, 0x00, 0x00, 0x00, 0x00]))
    golden(1, uint32(0), bytes([0xd6, 0xff, 0x00, 0x00, 0x00, 0x01]))
    golden(4294967295, uint32(0), bytes([0xd6, 0xff, 0xff, 0xff, 0xff, 0xff]))
    golden(4294967296, uint32(0), bytes([0xd7, 0xff, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]))
    golden(0, uint32(1), bytes([0xd7, 0xff, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]))
    golden(0, uint32(999999999), bytes([0xd7, 0xff, 0xee, 0x6b, 0x27, 0xfc, 0x00, 0x00, 0x00, 0x00]))
    golden(4294967295, uint32(1), bytes([0xd7, 0xff, 0x00, 0x00, 0x00, 0x04, 0xff, 0xff, 0xff, 0xff]))
    golden(17179869183, uint32(999999999), bytes([0xd7, 0xff, 0xee, 0x6b, 0x27, 0xff, 0xff, 0xff, 0xff, 0xff]))
    golden(17179869184, uint32(0), bytes([0xc7, 0x0c, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]))
    golden(17179869184, uint32(999999999), bytes([0xc7, 0x0c, 0xff, 0x3b, 0x9a, 0xc9, 0xff, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]))
    golden(-1, uint32(0), bytes([0xc7, 0x0c, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]))
    golden(-1, uint32(999999999), bytes([0xc7, 0x0c, 0xff, 0x3b, 0x9a, 0xc9, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]))
    golden(-9223372036854775807 - 1, uint32(1), bytes([0xc7, 0x0c, 0xff, 0x00, 0x00, 0x00, 0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    golden(9223372036854775807, uint32(999999999), bytes([0xc7, 0x0c, 0xff, 0x3b, 0x9a, 0xc9, 0xff, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]))
    auto epoch = msgpack.Value.Timestamp(msgpack.Timestamp(0))
    check(msgpack.packb(epoch) == bytes([0xd6, 0xff, 0, 0, 0, 0]), "zero default nanoseconds")

def fails(bytes wire, str expected):
    auto caught = ""
    try:
        msgpack.unpackb(wire)
    except msgpack.OutOfData:
        caught = "incomplete"
    except msgpack.FormatError as message:
        caught = message
    except msgpack.ExtraData:
        caught = "trailing"
    check(caught.find(expected) >= 0, "expected " + expected + ", got " + caught)

def empty(msgpack.Unpacker reader):
    try:
        reader.unpack()
    except msgpack.OutOfData:
        return
    raise ValueError("Expected incomplete timestamp")

def prefixes():
    list[bytes] wires = [
        bytes([0xd6, 0xff, 0, 0, 0, 0]),
        bytes([0xd7, 0xff, 0, 0, 0, 4, 0, 0, 0, 0]),
        bytes([0xc7, 12, 0xff, 0, 0, 0, 1, 255, 255, 255, 255, 255, 255, 255, 255]),
    ]
    for wire in wires:
        auto reader = msgpack.Unpacker()
        auto end = 0
        while end < len(wire):
            fails(wire[0:end], "incomplete")
            empty(reader)
            reader.feed(wire[end:end + 1])
            end = end + 1
        reader.feed(bytes([0xc0]))
        check(msgpack.packb(reader.unpack()) == wire, "stream resumes through timestamp")
        check(msgpack.packb(reader.unpack()) == bytes([0xc0]), "stream retains surplus after timestamp")
        fails(wire + bytes([0xc0]), "trailing")

def noncanonical():
    auto epoch = bytes([0xd6, 0xff, 0, 0, 0, 0])
    list[bytes] input = [
        bytes([0xc7, 4, 0xff, 0, 0, 0, 0]),
        bytes([0xd7, 0xff, 0, 0, 0, 0, 0, 0, 0, 0]),
        bytes([0xc8, 0, 4, 0xff, 0, 0, 0, 0]),
        bytes([0xc9, 0, 0, 0, 4, 0xff, 0, 0, 0, 0]),
        bytes([0xc7, 12, 0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    ]
    for wire in input:
        check(msgpack.packb(msgpack.unpackb(wire)) == epoch, "valid noncanonical timestamp normalizes to timestamp32")
    auto nested = bytes([0x81, 0xa1, 0x6b, 0x91]) + epoch
    check(msgpack.packb(msgpack.unpackb(nested)) == nested, "timestamp nested under map and array")
    auto timestamp_key = bytes([0x81]) + epoch + bytes([0xc0])
    fails(timestamp_key, "strict_map_key")
    check(msgpack.packb(msgpack.unpackb(timestamp_key, strict_map_key=False)) == timestamp_key, "nonstrict accepts timestamp key")

def rejects_nanoseconds(uint32 nanos):
    try:
        msgpack.packb(msgpack.Value.Timestamp(msgpack.Timestamp(0, nanos)))
    except ValueError as message:
        check(message.find("timestamp nanoseconds") >= 0, "invalid timestamp nanoseconds")
        return
    raise ValueError("Expected invalid timestamp nanoseconds")

def malformed():
    for length in [0, 1, 2, 3, 5, 7, 9, 11, 13, 16]:
        list[int64] octets = [0xc7, length, 0xff]
        auto index = 0
        while index < length:
            octets.append(0)
            index = index + 1
        fails(bytes(octets), "timestamp payload")
    fails(bytes([0xd7, 0xff, 0xee, 0x6b, 0x28, 0, 0, 0, 0, 0]), "timestamp nanoseconds")
    fails(bytes([0xd7, 0xff, 0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0]), "timestamp nanoseconds")
    fails(bytes([0xc7, 12, 0xff, 0x3b, 0x9a, 0xca, 0, 0, 0, 0, 0, 0, 0, 0, 0]), "timestamp nanoseconds")
    fails(bytes([0xc7, 12, 0xff, 0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0, 0, 0, 0, 0]), "timestamp nanoseconds")
    rejects_nanoseconds(uint32(1000000000))
    rejects_nanoseconds(uint32(-1))

def main():
    widths()
    prefixes()
    noncanonical()
    malformed()
    print("MessagePack Timestamp wire and rejection tests: PASS")
