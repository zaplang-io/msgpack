import msgpack

def check(bool condition, str label):
    if not condition:
        raise ValueError("FAIL: " + label)

def text_payload(int64 length) -> bytes:
    auto result = b""
    auto chunk = b"x"
    while length > 0:
        if length % 2 == 1:
            result = result + chunk
        length = length // 2
        if length > 0:
            chunk = chunk + chunk
    return result

def header_golden(int64 length, bytes str_header, bytes bin_header, bytes raw_header):
    auto payload = text_payload(length)
    auto text = msgpack.Value.Str(str(payload))
    auto binary = msgpack.Value.Bin(payload)
    auto legacy = msgpack.Packer(use_bin_type=False)
    check(msgpack.packb(text) == str_header + payload, "modern string width " + str(length))
    check(msgpack.packb(binary, use_bin_type=True) == bin_header + payload, "modern binary width " + str(length))
    check(msgpack.packb(text, use_bin_type=False) == raw_header + payload, "legacy string width " + str(length))
    check(msgpack.packb(binary, use_bin_type=False) == raw_header + payload, "legacy binary width " + str(length))
    check(legacy.pack(text) == raw_header + payload, "Packer legacy text width")
    check(legacy.pack(binary) == raw_header + payload, "Packer legacy binary width")

def widths():
    header_golden(0, bytes([0xa0]), bytes([0xc4, 0]), bytes([0xa0]))
    header_golden(31, bytes([0xbf]), bytes([0xc4, 31]), bytes([0xbf]))
    header_golden(32, bytes([0xd9, 32]), bytes([0xc4, 32]), bytes([0xda, 0, 32]))
    header_golden(255, bytes([0xd9, 255]), bytes([0xc4, 255]), bytes([0xda, 0, 255]))
    header_golden(256, bytes([0xda, 1, 0]), bytes([0xc5, 1, 0]), bytes([0xda, 1, 0]))
    header_golden(65535, bytes([0xda, 255, 255]), bytes([0xc5, 255, 255]), bytes([0xda, 255, 255]))
    header_golden(65536, bytes([0xdb, 0, 1, 0, 0]), bytes([0xc6, 0, 1, 0, 0]), bytes([0xdb, 0, 1, 0, 0]))

def fails(bytes wire, str reason, bool raw = False):
    try:
        msgpack.unpackb(wire, raw=raw)
    except msgpack.FormatError as message:
        check(message.find(reason) >= 0, "expected format error " + reason)
        return
    raise ValueError("Expected format error " + reason)

def stream_fails(msgpack.Unpacker reader, bytes wire, str reason):
    reader.feed(wire)
    try:
        reader.unpack()
    except msgpack.FormatError as message:
        check(message.find(reason) >= 0, "expected stream format error " + reason)
        return
    raise ValueError("Expected stream format error " + reason)

def raw_binary():
    auto raw = bytes([0xa2, 0xff, 0])
    auto modern = bytes([0xc4, 2, 0xff, 0])
    auto value = msgpack.Value.Bin(bytes([0xff, 0]))
    check(msgpack.packb(value, use_bin_type=False) == raw, "legacy writer keeps arbitrary bytes")
    check(msgpack.packb(msgpack.unpackb(modern)) == modern, "default reader accepts non-UTF-8 modern bin")
    check(msgpack.packb(msgpack.unpackb(modern, raw=True)) == modern, "raw leaves modern bin unchanged")
    fails(raw, "UTF-8")
    check(msgpack.packb(msgpack.unpackb(raw, raw=True)) == modern, "raw recovers exact legacy bytes")
    stream_fails(msgpack.Unpacker(), raw, "UTF-8")
    auto reader = msgpack.Unpacker(raw=True)
    reader.feed(raw[0:1])
    reader.feed(raw[1:len(raw)] + modern)
    check(msgpack.packb(reader.unpack()) == modern, "raw stream decodes split legacy bin")
    check(msgpack.packb(reader.unpack()) == modern, "raw stream preserves modern bin")

def nested_options():
    auto nested = msgpack.Value.Map([
        (msgpack.Value.Bin(b"k"), msgpack.Value.Array([msgpack.Value.Bin(b"v"), msgpack.Value.Float(1.5)])),
        (msgpack.Value.Str("k"), msgpack.Value.Bin(b"w")),
    ])
    auto legacy = bytes([0x82, 0xa1, 0x6b, 0x92, 0xa1, 0x76, 0xca, 0x3f, 0xc0, 0, 0, 0xa1, 0x6b, 0xa1, 0x77])
    auto modern_raw = bytes([0x82, 0xc4, 1, 0x6b, 0x92, 0xc4, 1, 0x76, 0xca, 0x3f, 0xc0, 0, 0, 0xc4, 1, 0x6b, 0xc4, 1, 0x77])
    check(msgpack.packb(nested, use_bin_type=False, use_single_float=True) == legacy, "both packing options apply to nested values and keys")
    auto writer = msgpack.Packer(use_bin_type=False, use_single_float=True)
    check(writer.pack(nested) == legacy, "Packer combines legacy raw and single precision")
    check(msgpack.packb(msgpack.unpackb(legacy), use_single_float=True) == legacy, "strict accepts legacy keys as strings and preserves both pairs")
    check(msgpack.packb(msgpack.unpackb(legacy, raw=True), use_single_float=True) == modern_raw, "raw accepts legacy keys as bytes and preserves both pairs")

    auto numeric_key = bytes([0x81, 1, 0xa1, 0x78])
    fails(numeric_key, "strict_map_key")
    fails(numeric_key, "strict_map_key", raw=True)
    stream_fails(msgpack.Unpacker(raw=True), numeric_key, "strict_map_key")
    auto permissive = msgpack.Unpacker(raw=True, strict_map_key=False)
    permissive.feed(numeric_key)
    auto expected = bytes([0x81, 1, 0xc4, 1, 0x78])
    check(msgpack.packb(msgpack.unpackb(numeric_key, raw=True, strict_map_key=False)) == expected, "one-shot raw and permissive keys are independent")
    check(msgpack.packb(permissive.unpack()) == expected, "stream raw and permissive keys are independent")

    auto extension = msgpack.Value.Ext(msgpack.ExtType(0, bytes([255])))
    auto timestamp = msgpack.Value.Timestamp(msgpack.Timestamp(0))
    check(writer.pack(extension) == bytes([0xd4, 0, 255]), "legacy mode preserves extension wire types")
    check(writer.pack(timestamp) == bytes([0xd6, 255, 0, 0, 0, 0]), "legacy mode preserves timestamp wire types")

def main():
    widths()
    raw_binary()
    nested_options()
    print("MessagePack option parity tests: PASS")
