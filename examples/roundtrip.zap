import msgpack

def main():
    auto value = msgpack.Value.Map([
        (msgpack.Value.Str("id"), msgpack.Value.Int(7)),
        (msgpack.Value.Str("payload"), msgpack.Value.Bin(bytes([0, 255]))),
    ])
    auto wire = msgpack.packb(value)
    match msgpack.unpackb(wire, max_map_len=2, max_bin_len=2):
        case msgpack.Value.Map(pairs):
            for pair in pairs:
                match pair[1]:
                    case msgpack.Value.Int(number):
                        print("id=" + str(number))
                    case msgpack.Value.Bin(payload):
                        print("payload bytes=" + str(len(payload)))
                    case _:
                        raise ValueError("Unexpected map value")
        case _:
            raise ValueError("Expected a map")
