import datetime
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

def datetime_roundtrip(DateTime dt, int64 seconds, int64 nanosecond):
    auto stamp = msgpack.timestamp_from_datetime(dt)
    check(stamp.seconds == seconds and int64(stamp.nanoseconds) == nanosecond, "aware datetime uses UTC seconds and exact fraction")
    auto wire = msgpack.packb(msgpack.Value.Timestamp(stamp))
    match msgpack.unpackb(wire):
        case msgpack.Value.Timestamp(decoded):
            auto utc = decoded.to_datetime()
            check(utc.is_aware and utc.offset == 0, "decoded datetime is aware UTC")
            check(datetime.to_timestamp(utc) == seconds, "decoded datetime seconds")
            check(utc.nanosecond == nanosecond, "decoded datetime nanosecond")
        case _:
            raise ValueError("Expected Timestamp in datetime round-trip")

def invalid_datetime(DateTime dt, str expected):
    try:
        msgpack.timestamp_from_datetime(dt)
    except ValueError as message:
        check(message.find(expected) >= 0, "invalid DateTime diagnostic")
        return
    raise ValueError("Expected datetime to be rejected")

def invalid_datetime_conversion(msgpack.Timestamp stamp, str expected):
    try:
        stamp.to_datetime()
    except ValueError as message:
        check(message.find(expected) >= 0, "invalid Timestamp conversion diagnostic")
        return
    raise ValueError("Expected timestamp conversion to be rejected")

def datetime_values():
    datetime_roundtrip(datetime.rfc3339_parse("1970-01-01T00:00:00Z"), 0, 0)
    datetime_roundtrip(datetime.rfc3339_parse("1970-01-01T00:00:00.000000001Z"), 0, 1)
    datetime_roundtrip(datetime.rfc3339_parse("1970-01-01T05:30:00.123456789+05:30"), 0, 123456789)
    datetime_roundtrip(datetime.rfc3339_parse("1969-12-31T16:00:00.123456789-08:00"), 0, 123456789)
    datetime_roundtrip(datetime.rfc3339_parse("1970-01-01T05:29:59.999999999+05:30"), -1, 999999999)

    auto ny = datetime.zone("America/New_York")
    auto earlier = datetime.astimezone(datetime.rfc3339_parse("2024-11-03T05:30:00.000000007Z"), ny)
    auto later = datetime.astimezone(datetime.rfc3339_parse("2024-11-03T06:30:00.000000007Z"), ny)
    check(earlier.hour == later.hour and earlier.minute == later.minute, "named-zone fold shares a civil time")
    check(earlier.offset == -14400 and later.offset == -18000, "named-zone fold retains distinct offsets")
    datetime_roundtrip(earlier, 1730611800, 7)
    datetime_roundtrip(later, 1730615400, 7)

    auto first = msgpack.Timestamp(-62135596800).to_datetime()
    check(first.year == 1 and first.month == 1 and first.day == 1, "first supported year")
    datetime_roundtrip(first, -62135596800, 0)
    auto last = msgpack.Timestamp(253402300799, uint32(999999999)).to_datetime()
    check(last.year == 9999 and last.month == 12 and last.day == 31, "last supported year")
    datetime_roundtrip(last, 253402300799, 999999999)

    invalid_datetime(datetime.from_timestamp(0), "timezone-aware")
    invalid_datetime(DateTime(1970, 1, 1, 0, 0, 0, 0, True, -1, -1), "timestamp nanoseconds")
    invalid_datetime(DateTime(1970, 1, 1, 0, 0, 0, 0, True, -1, 1000000000), "timestamp nanoseconds")
    invalid_datetime_conversion(msgpack.Timestamp(-62135596801), "outside DateTime")
    invalid_datetime_conversion(msgpack.Timestamp(253402300800), "outside DateTime")
    invalid_datetime_conversion(msgpack.Timestamp(-9223372036854775807 - 1), "outside DateTime")
    invalid_datetime_conversion(msgpack.Timestamp(9223372036854775807), "outside DateTime")
    invalid_datetime_conversion(msgpack.Timestamp(0, uint32(1000000000)), "timestamp nanoseconds")

def main():
    widths()
    prefixes()
    noncanonical()
    malformed()
    datetime_values()
    print("MessagePack Timestamp wire, DateTime, and rejection tests: PASS")
