import msgpack

def drain(msgpack.Unpacker reader):
    for value in reader:
        match value:
            case msgpack.Value.Str(text):
                print(text)
            case _:
                raise ValueError("Expected a string")

def main():
    auto writer = msgpack.Packer()
    auto wire = writer.pack(msgpack.Value.Str("one")) + writer.pack(msgpack.Value.Str("two"))
    auto reader = msgpack.Unpacker(max_buffer_size=32, max_str_len=3)
    reader.feed(wire[0:6])
    drain(reader)
    reader.feed(wire[6:len(wire)])
    drain(reader)
