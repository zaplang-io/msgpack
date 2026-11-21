import msgpack

def drain(msgpack.Unpacker reader) -> list[str]:
    list[str] drained = []
    for value in reader:
        match value:
            case msgpack.Value.Str(text):
                drained.append(text)
                print(text)
            case _:
                raise ValueError("Expected a string")
    return drained

def main():
    auto writer = msgpack.Packer()
    auto wire = writer.pack(msgpack.Value.Str("one")) + writer.pack(msgpack.Value.Str("two"))
    auto reader = msgpack.Unpacker(max_buffer_size=32, max_str_len=3)
    reader.feed(wire[0:6])
    auto first = drain(reader)
    assert len(first) == 1 and first[0] == "one"
    reader.feed(wire[6:len(wire)])
    auto second = drain(reader)
    assert len(second) == 1 and second[0] == "two"
