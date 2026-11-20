import datetime
import msgpack

struct Note:
    str text

def encode_note(Note note) -> msgpack.ExtType:
    return msgpack.ExtType(42, bytes(note.text))

def decode_note(int64 code, bytes payload) -> Note:
    if code != 42:
        raise ValueError("Expected Note extension code 42")
    return Note(str(payload))

def main():
    auto wire = msgpack.packb_with_default[Note](Note("hello"), default=encode_note)
    auto note = msgpack.unpackb_with_ext_hook[Note](wire, ext_hook=decode_note)
    print("note=" + note.text)

    auto dt = datetime.rfc3339_parse("1970-01-01T05:30:00.123456789+05:30")
    auto stamp = msgpack.timestamp_from_datetime(dt)
    auto packed = msgpack.packb(msgpack.Value.Timestamp(stamp))
    match msgpack.unpackb(packed):
        case msgpack.Value.Timestamp(decoded):
            auto utc = decoded.to_datetime()
            print("UTC seconds=" + str(datetime.to_timestamp(utc)))
            print("nanoseconds=" + str(utc.nanosecond))
        case _:
            raise ValueError("Expected a timestamp")
