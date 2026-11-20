import msgpack

def check(bool condition, str label):
    if not condition:
        raise ValueError("FAIL: " + label)

def check_extension(msgpack.Value value, int64 code, bytes payload):
    match value:
        case msgpack.Value.Ext(extension):
            check(extension.code == code and extension.data == payload, "decoded extension code and payload")
        case _:
            raise ValueError("Expected Ext")

def payload_bytes(int64 length) -> bytes:
    auto result = b""
    auto chunk = bytes([0xff])
    while length > 0:
        if length % 2 == 1:
            result = result + chunk
        length = length // 2
        if length > 0:
            chunk = chunk + chunk
    return result

def golden(int64 code, bytes payload, bytes header):
    auto wire = header + payload
    auto value = msgpack.Value.Ext(msgpack.ExtType(code, payload))
    check(msgpack.packb(value) == wire, "extension header at length " + str(len(payload)))
    check(msgpack.Packer().pack(value) == wire, "extension encoding through Packer")
    check_extension(msgpack.unpackb(wire), code, payload)
    check_extension(msgpack.unpackb(wire, raw=True), code, payload)

def widths():
    golden(0, b"", bytes([0xc7, 0, 0]))
    golden(0, bytes([0xff]), bytes([0xd4, 0]))
    golden(127, bytes([0, 0xff]), bytes([0xd5, 127]))
    golden(1, bytes([0, 0x80, 0xff, 1]), bytes([0xd6, 1]))
    golden(42, payload_bytes(8), bytes([0xd7, 42]))
    golden(127, payload_bytes(16), bytes([0xd8, 127]))
    golden(11, bytes([0, 0x80, 0xff]), bytes([0xc7, 3, 11]))
    golden(11, payload_bytes(255), bytes([0xc7, 255, 11]))
    golden(127, payload_bytes(256), bytes([0xc8, 1, 0, 127]))
    golden(0, payload_bytes(65535), bytes([0xc8, 255, 255, 0]))
    golden(127, payload_bytes(65536), bytes([0xc9, 0, 1, 0, 0, 127]))

def wire_fail(bytes wire, str expected):
    auto caught = ""
    try:
        msgpack.unpackb(wire)
    except msgpack.OutOfData:
        caught = "incomplete"
    except msgpack.FormatError as message:
        caught = message
    except msgpack.ExtraData:
        caught = "trailing"
    check(caught.find(expected) >= 0, "expected wire rejection " + expected + ", got " + caught)

def encode_fail(int64 code):
    try:
        msgpack.packb(msgpack.Value.Ext(msgpack.ExtType(code, b"")))
    except ValueError as message:
        check(message.find("0..127") >= 0, "invalid extension code range")
        return
    raise ValueError("Expected invalid extension code to fail")

def truncated_stream(msgpack.Unpacker reader):
    try:
        reader.unpack()
    except msgpack.OutOfData:
        return
    raise ValueError("Expected incomplete extension")

def prefix_cases():
    list[bytes] wires = [
        bytes([0xd4, 16, 0]), bytes([0xd5, 16, 0, 255]),
        bytes([0xd6, 16]) + payload_bytes(4), bytes([0xd7, 16]) + payload_bytes(8),
        bytes([0xd8, 16]) + payload_bytes(16),
        bytes([0xc7, 0, 16]), bytes([0xc7, 1, 16, 255]),
        bytes([0xc8, 0, 1, 16, 255]), bytes([0xc9, 0, 0, 0, 1, 16, 255]),
    ]
    for wire in wires:
        auto ext_value = msgpack.unpackb(wire)
        auto canonical = msgpack.packb(ext_value)
        auto reader = msgpack.Unpacker()
        auto end = 0
        while end < len(wire):
            wire_fail(wire[0:end], "incomplete")
            truncated_stream(reader)
            reader.feed(wire[end:end + 1])
            end = end + 1
        reader.feed(bytes([0xc0]))
        check(msgpack.packb(reader.unpack()) == canonical, "stream resumes through extension length, code, and payload")
        check(msgpack.packb(reader.unpack()) == bytes([0xc0]), "stream keeps bytes following extension")
        wire_fail(wire + bytes([0xc0]), "trailing")
    auto fixed = bytes([0xd4, 16, 255])
    check(msgpack.packb(msgpack.unpackb(bytes([0xc7, 1, 16, 255]))) == fixed, "noncanonical variable width normalizes to fixext")

def errors_and_nesting():
    for code in [-129, -128, -2, -1, 128, 255, 256]:
        encode_fail(code)
    wire_fail(bytes([0xd4, 128, 0]), "extension code -128")
    wire_fail(bytes([0xc7, 0, 254]), "extension code -2")
    wire_fail(bytes([0xd4, 255, 0]), "timestamp payload")
    wire_fail(bytes([0xc9, 255, 255, 255, 255, 0]), "incomplete")
    auto nested = bytes([0x81, 0xa1, 0x6b, 0x91, 0xd4, 42, 0xff])
    check(msgpack.packb(msgpack.unpackb(nested)) == nested, "extension nested under array and map")
    auto ext_key = bytes([0x81, 0xd4, 42, 0xff, 0xc0])
    wire_fail(ext_key, "strict_map_key")
    check(msgpack.packb(msgpack.unpackb(ext_key, strict_map_key=False)) == ext_key, "nonstrict mode accepts extension keys")

struct Record:
    bytes payload
    int64 encode_calls

def encode_record(Record value) -> msgpack.ExtType:
    value.encode_calls = value.encode_calls + 1
    return msgpack.ExtType(42, value.payload)

def decode_record(int64 code, bytes payload) -> Record:
    if code != 42:
        raise ValueError("Record decoder received an unexpected code")
    return Record(payload, 0)

def refused_record(Record value) -> msgpack.ExtType:
    raise ValueError("Record encoder refused the input")

def reserved_code(Record value) -> msgpack.ExtType:
    return msgpack.ExtType(-1, value.payload)

def reject_without_hook(bytes wire, str expected):
    auto caught = ""
    try:
        msgpack.unpackb_with_ext_hook[Record](wire, ext_hook=decode_record)
    except msgpack.OutOfData:
        caught = "incomplete"
    except msgpack.ExtraData:
        caught = "trailing"
    except msgpack.FormatError as message:
        caught = message
    check(caught.find(expected) >= 0, "typed helper validates wire before invoking hook")

def hook_failures(Record record):
    auto called = False
    try:
        msgpack.packb_with_default[Record](record, default=refused_record)
    except ValueError as message:
        called = message.find("encoder refused") >= 0
    check(called, "default hook error propagates")
    auto bad_code = False
    try:
        msgpack.packb_with_default[Record](record, default=reserved_code)
    except ValueError as message:
        bad_code = message.find("0..127") >= 0
    check(bad_code, "default hook result must use a valid application code")
    auto rejected = False
    try:
        msgpack.unpackb_with_ext_hook[Record](bytes([0xd4, 41, 0]), ext_hook=decode_record)
    except ValueError as message:
        rejected = message.find("unexpected code") >= 0
    check(rejected, "ext_hook error propagates")

def typed_hooks():
    auto record = Record(bytes([0, 0x80, 0xff]), 0)
    auto wire = msgpack.packb_with_default[Record](record, default=encode_record)
    check(wire == bytes([0xc7, 3, 42, 0, 0x80, 0xff]), "default transforms one typed record into extension bytes")
    check(record.encode_calls == 1, "default called exactly once")
    Record decoded = msgpack.unpackb_with_ext_hook[Record](wire, ext_hook=decode_record)
    check(decoded.payload == record.payload, "ext_hook returns the user record type")
    # Code 41 would raise from decode_record if it were called before validation.
    reject_without_hook(bytes([0xd4, 41]), "incomplete")
    reject_without_hook(bytes([0xd4, 41, 0, 0xc0]), "trailing")
    reject_without_hook(bytes([0xd4, 0xfe, 0]), "extension code -2")
    reject_without_hook(bytes([0xd6, 255, 0, 0, 0, 0]), "top-level")
    reject_without_hook(bytes([0xc0]), "top-level")
    reject_without_hook(bytes([0x91, 0xd4, 41, 0]), "top-level")
    hook_failures(record)

def main():
    widths()
    prefix_cases()
    errors_and_nesting()
    typed_hooks()
    print("MessagePack extension wire, hooks, and rejection tests: PASS")
