import msgpack

def main():
    auto value = msgpack.Value.Map([
        (msgpack.Value.Str("id"), msgpack.Value.Int(7)),
        (msgpack.Value.Str("payload"), msgpack.Value.Bin(bytes([0, 255]))),
    ])
    auto wire = msgpack.packb(value)
    match msgpack.unpackb(wire, max_map_len=2, max_bin_len=2):
        case msgpack.Value.Map(pairs):
            assert len(pairs) == 2
            match pairs[0][1]:
                case msgpack.Value.Int(number):
                    assert number == 7
                    print("id=" + str(number))
                case _:
                    raise ValueError("Expected an integer ID")
            match pairs[1][1]:
                case msgpack.Value.Bin(payload):
                    assert payload == bytes([0, 255])
                    print("payload bytes=" + str(len(payload)))
                case _:
                    raise ValueError("Expected a binary payload")
        case _:
            raise ValueError("Expected a map")
