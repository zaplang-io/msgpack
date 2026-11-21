def check(bool condition, str label):
    assert condition, label

def check_timestamp(Value value, int64 seconds, uint32 nanoseconds):
    match value:
        case Value.Timestamp(timestamp):
            check(timestamp.seconds == seconds, "timestamp seconds")
            check(timestamp.nanoseconds == nanoseconds, "timestamp nanoseconds")
        case _:
            raise ValueError("Expected Timestamp")

def golden(int64 seconds, uint32 nanoseconds, bytes wire):
    auto stamp = Value.Timestamp(Timestamp(seconds, nanoseconds))
    check(packb(stamp) == wire, "timestamp wire for seconds " + str(seconds))
    check(Packer().pack(stamp) == wire, "stream packer timestamp")
    check_timestamp(unpackb(wire), seconds, nanoseconds)
    check_timestamp(unpackb(wire, raw=True), seconds, nanoseconds)

@test
def test_timestamp_wire_widths():
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
    auto epoch = Value.Timestamp(Timestamp(0))
    check(packb(epoch) == bytes([0xd6, 0xff, 0, 0, 0, 0]), "zero default nanoseconds")

def fails(bytes wire, str expected):
    auto caught = ""
    try:
        unpackb(wire)
    except OutOfData:
        caught = "incomplete"
    except FormatError as message:
        caught = message
    except ExtraData:
        caught = "trailing"
    check(caught.find(expected) >= 0, "expected " + expected + ", got " + caught)

def empty(Unpacker reader):
    try:
        reader.unpack()
    except OutOfData:
        return
    raise ValueError("Expected incomplete timestamp")

@test
def test_timestamp_prefixes_and_streaming():
    list[bytes] wires = [
        bytes([0xd6, 0xff, 0, 0, 0, 0]),
        bytes([0xd7, 0xff, 0, 0, 0, 4, 0, 0, 0, 0]),
        bytes([0xc7, 12, 0xff, 0, 0, 0, 1, 255, 255, 255, 255, 255, 255, 255, 255]),
    ]
    for wire in wires:
        auto reader = Unpacker()
        auto end = 0
        while end < len(wire):
            fails(wire[0:end], "incomplete")
            empty(reader)
            reader.feed(wire[end:end + 1])
            end = end + 1
        reader.feed(bytes([0xc0]))
        check(packb(reader.unpack()) == wire, "stream resumes through timestamp")
        check(packb(reader.unpack()) == bytes([0xc0]), "stream retains surplus after timestamp")
        fails(wire + bytes([0xc0]), "trailing")

@test
def test_noncanonical_timestamps():
    auto epoch = bytes([0xd6, 0xff, 0, 0, 0, 0])
    list[bytes] input = [
        bytes([0xc7, 4, 0xff, 0, 0, 0, 0]),
        bytes([0xd7, 0xff, 0, 0, 0, 0, 0, 0, 0, 0]),
        bytes([0xc8, 0, 4, 0xff, 0, 0, 0, 0]),
        bytes([0xc9, 0, 0, 0, 4, 0xff, 0, 0, 0, 0]),
        bytes([0xc7, 12, 0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    ]
    for wire in input:
        check(packb(unpackb(wire)) == epoch, "valid noncanonical timestamp normalizes to timestamp32")
    auto nested = bytes([0x81, 0xa1, 0x6b, 0x91]) + epoch
    check(packb(unpackb(nested)) == nested, "timestamp nested under map and array")
    auto timestamp_key = bytes([0x81]) + epoch + bytes([0xc0])
    fails(timestamp_key, "strict_map_key")
    check(packb(unpackb(timestamp_key, strict_map_key=False)) == timestamp_key, "nonstrict accepts timestamp key")

def rejects_nanoseconds(uint32 nanos):
    try:
        packb(Value.Timestamp(Timestamp(0, nanos)))
    except ValueError as message:
        check(message.find("timestamp nanoseconds") >= 0, "invalid timestamp nanoseconds")
        return
    raise ValueError("Expected invalid timestamp nanoseconds")

@test
def test_malformed_timestamps():
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
    auto stamp = timestamp_from_datetime(dt)
    check(stamp.seconds == seconds and int64(stamp.nanoseconds) == nanosecond, "aware datetime uses UTC seconds and exact fraction")
    auto wire = packb(Value.Timestamp(stamp))
    match unpackb(wire):
        case Value.Timestamp(decoded):
            auto utc = decoded.to_datetime()
            check(utc.is_aware and utc.offset == 0, "decoded datetime is aware UTC")
            check(datetime.to_timestamp(utc) == seconds, "decoded datetime seconds")
            check(utc.nanosecond == nanosecond, "decoded datetime nanosecond")
        case _:
            raise ValueError("Expected Timestamp in datetime round-trip")

def invalid_datetime(DateTime dt, str expected):
    try:
        timestamp_from_datetime(dt)
    except ValueError as message:
        check(message.find(expected) >= 0, "invalid DateTime diagnostic")
        return
    raise ValueError("Expected datetime to be rejected")

def invalid_datetime_conversion(Timestamp stamp, str expected):
    try:
        stamp.to_datetime()
    except ValueError as message:
        check(message.find(expected) >= 0, "invalid Timestamp conversion diagnostic")
        return
    raise ValueError("Expected timestamp conversion to be rejected")

@test
def test_datetime_roundtrips_and_errors():
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

    auto first = Timestamp(-62135596800).to_datetime()
    check(first.year == 1 and first.month == 1 and first.day == 1, "first supported year")
    datetime_roundtrip(first, -62135596800, 0)
    auto last = Timestamp(253402300799, uint32(999999999)).to_datetime()
    check(last.year == 9999 and last.month == 12 and last.day == 31, "last supported year")
    datetime_roundtrip(last, 253402300799, 999999999)

    invalid_datetime(datetime.from_timestamp(0), "timezone-aware")
    invalid_datetime(DateTime(1970, 1, 1, 0, 0, 0, 0, True, -1, -1), "timestamp nanoseconds")
    invalid_datetime(DateTime(1970, 1, 1, 0, 0, 0, 0, True, -1, 1000000000), "timestamp nanoseconds")
    invalid_datetime_conversion(Timestamp(-62135596801), "outside DateTime")
    invalid_datetime_conversion(Timestamp(253402300800), "outside DateTime")
    invalid_datetime_conversion(Timestamp(-9223372036854775807 - 1), "outside DateTime")
    invalid_datetime_conversion(Timestamp(9223372036854775807), "outside DateTime")
    invalid_datetime_conversion(Timestamp(0, uint32(1000000000)), "timestamp nanoseconds")
