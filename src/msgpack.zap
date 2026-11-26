import datetime
import math
import serde

# The application code and payload of a MessagePack extension.
struct ExtType:
    int64 code
    bytes data

# Signed Unix seconds and a nonnegative fractional nanosecond component.
struct Timestamp:
    int64 seconds
    uint32 nanoseconds = uint32(0)

    def to_datetime(self) -> DateTime:
        """Return a timezone-aware UTC datetime, preserving nanoseconds."""
        _check_timestamp_nanoseconds(int64(self.nanoseconds))
        # The UTC instants at 0001-01-01T00:00:00 and 9999-12-31T23:59:59.
        if self.seconds < -62135596800 or self.seconds > 253402300799:
            raise ValueError("MessagePack timestamp is outside DateTime years 1..9999")
        auto whole = datetime.from_timestamp(self.seconds)
        auto utc = datetime.astimezone(whole, datetime.fixed_offset(0))
        return datetime.replace(utc, nanosecond=int64(self.nanoseconds))

def _check_timestamp_nanoseconds(int64 nanos):
    if nanos < 0 or nanos > 999999999:
        raise ValueError("MessagePack timestamp nanoseconds must be in 0..999999999")

def timestamp_from_datetime(DateTime dt) -> Timestamp:
    """Convert a timezone-aware datetime to exact Unix seconds and nanoseconds."""
    if not dt.is_aware:
        raise ValueError("MessagePack requires a timezone-aware DateTime")
    _check_timestamp_nanoseconds(dt.nanosecond)
    return Timestamp(datetime.to_timestamp(dt), uint32(dt.nanosecond))

# A MessagePack document. Maps retain input order and duplicate keys.
enum Value:
    Nil
    Bool(bool value)
    Int(int64 value)
    UInt(uint64 value)
    Float(float64 value)
    Str(str value)
    Bin(bytes value)
    Array(list[Value] items)
    Map(list[(Value, Value)] pairs)
    Ext(ExtType value)
    Timestamp(Timestamp value)

def _append_word(list[int64] octets, uint64 word, int64 width):
    auto shift = (width - 1) * 8
    while shift >= 0:
        octets.append(int64((word >> uint64(shift)) & uint64(255)))
        shift = shift - 8

# The `_put_*` helpers append MessagePack bytes straight into a growable
# `list[int64]` output buffer (the streaming `MsgpackSerializer`'s hot path), so a
# whole record serializes into ONE buffer with no per-value `bytes` allocation. The
# `bytes`-returning forms below delegate to them and stay the API the `Value` DOM
# codec uses, so both paths emit byte-identical output.
def _put_unsigned(list[int64] buf, uint64 value):
    if value <= uint64(127):
        buf.append(int64(value))
    elif value <= uint64(255):
        buf.append(0xcc)
        _append_word(buf, value, 1)
    elif value <= uint64(65535):
        buf.append(0xcd)
        _append_word(buf, value, 2)
    elif value <= uint64(4294967295):
        buf.append(0xce)
        _append_word(buf, value, 4)
    else:
        buf.append(0xcf)
        _append_word(buf, value, 8)

def _unsigned(uint64 value) -> bytes:
    list[int64] octets = []
    _put_unsigned(octets, value)
    return bytes(octets)

def _put_integer(list[int64] buf, int64 value):
    if value >= 0:
        _put_unsigned(buf, uint64(value))
    elif value >= -32:
        buf.append(value + 256)
    elif value >= -128:
        buf.append(0xd0)
        _append_word(buf, uint64(value), 1)
    elif value >= -32768:
        buf.append(0xd1)
        _append_word(buf, uint64(value), 2)
    elif value >= -2147483648:
        buf.append(0xd2)
        _append_word(buf, uint64(value), 4)
    else:
        buf.append(0xd3)
        _append_word(buf, uint64(value), 8)

def _integer(int64 value) -> bytes:
    list[int64] octets = []
    _put_integer(octets, value)
    return bytes(octets)

def _put_length_header(list[int64] buf, int64 length, int64 fix_tag, int64 fix_max, int64 tag8, int64 tag16, int64 tag32):
    if length <= fix_max:
        buf.append(fix_tag + length)
    elif tag8 >= 0 and length <= 255:
        buf.append(tag8)
        _append_word(buf, uint64(length), 1)
    elif length <= 65535:
        buf.append(tag16)
        _append_word(buf, uint64(length), 2)
    elif length <= 4294967295:
        buf.append(tag32)
        _append_word(buf, uint64(length), 4)
    else:
        raise ValueError("MessagePack length exceeds 32 bits")

def _length_header(int64 length, int64 fix_tag, int64 fix_max, int64 tag8, int64 tag16, int64 tag32) -> bytes:
    list[int64] octets = []
    _put_length_header(octets, length, fix_tag, fix_max, tag8, tag16, tag32)
    return bytes(octets)

def _extension_header(ExtType extension) -> bytes:
    auto code = extension.code
    if code < 0 or code > 127:
        raise ValueError("MessagePack application extension code must be in 0..127")
    auto length = len(extension.data)
    if length == 1:
        return bytes([0xd4, code])
    if length == 2:
        return bytes([0xd5, code])
    if length == 4:
        return bytes([0xd6, code])
    if length == 8:
        return bytes([0xd7, code])
    if length == 16:
        return bytes([0xd8, code])
    return _length_header(length, 0, -1, 0xc7, 0xc8, 0xc9) + bytes([code])

def _timestamp_wire(Timestamp timestamp) -> bytes:
    _check_timestamp_nanoseconds(int64(timestamp.nanoseconds))
    auto seconds = timestamp.seconds
    auto nanos = uint64(timestamp.nanoseconds)
    list[int64] octets = []
    if seconds >= 0 and seconds <= 4294967295 and nanos == uint64(0):
        octets = [0xd6, 0xff]
        _append_word(octets, uint64(seconds), 4)
    elif seconds >= 0 and seconds <= 17179869183:
        octets = [0xd7, 0xff]
        _append_word(octets, (nanos << uint64(34)) | uint64(seconds), 8)
    else:
        octets = [0xc7, 12, 0xff]
        _append_word(octets, nanos, 4)
        _append_word(octets, uint64(seconds), 8)
    return bytes(octets)

def _float_bits(float64 value, int64 bias, int64 fraction_bits, float64 fraction_scale) -> uint64:
    auto infinity = uint64(2 * bias + 1) << uint64(fraction_bits)
    if math.isnan(value):
        return infinity | (uint64(1) << uint64(fraction_bits - 1))
    auto sign = uint64(0)
    if value < 0.0 or (value == 0.0 and math.atan2(value, -1.0) < 0.0):
        sign = uint64(2 * (bias + 1)) << uint64(fraction_bits)
    if math.isinf(value):
        return sign | infinity
    if value == 0.0:
        return sign

    # Normalize using exact powers of two. Stop at the minimum normal
    # exponent so smaller magnitudes keep their subnormal significands.
    auto magnitude = math.fabs(value)
    auto exponent = 0
    auto min_exponent = 1 - bias
    while magnitude >= 4294967296.0:
        magnitude = magnitude / 4294967296.0
        exponent = exponent + 32
    while magnitude >= 2.0:
        magnitude = magnitude / 2.0
        exponent = exponent + 1
    while magnitude < 1.0 / 4294967296.0 and exponent - 32 >= min_exponent:
        magnitude = magnitude * 4294967296.0
        exponent = exponent - 32
    while magnitude < 1.0 and exponent > min_exponent:
        magnitude = magnitude * 2.0
        exponent = exponent - 1
    if exponent > bias:
        return sign | infinity

    auto biased_exponent = 0
    if magnitude >= 1.0:
        biased_exponent = exponent + bias
        magnitude = magnitude - 1.0
    auto scaled = magnitude * fraction_scale
    auto fraction = int64(scaled)
    auto remainder = scaled - float64(fraction)
    if remainder > 0.5 or (remainder == 0.5 and (fraction & 1) == 1):
        fraction = fraction + 1
    if fraction == int64(fraction_scale):
        fraction = 0
        biased_exponent = biased_exponent + 1
    return sign | (uint64(biased_exponent) << uint64(fraction_bits)) | uint64(fraction)

def _put_float(list[int64] buf, float64 value, bool use_single_float):
    if use_single_float:
        buf.append(0xca)
        _append_word(buf, _float_bits(value, 127, 23, 8388608.0), 4)
    else:
        buf.append(0xcb)
        _append_word(buf, _float_bits(value, 1023, 52, 4503599627370496.0), 8)

def _float(float64 value, bool use_single_float) -> bytes:
    list[int64] octets = []
    _put_float(octets, value, use_single_float)
    return bytes(octets)

def _put_text_header(list[int64] buf, int64 length, bool use_bin_type):
    auto tag8 = -1
    if use_bin_type:
        tag8 = 0xd9
    _put_length_header(buf, length, 0xa0, 31, tag8, 0xda, 0xdb)

def _text_header(int64 length, bool use_bin_type) -> bytes:
    list[int64] octets = []
    _put_text_header(octets, length, use_bin_type)
    return bytes(octets)

# Append a raw byte payload (string / binary contents) into the buffer.
def _put_payload(list[int64] buf, bytes payload):
    auto n = len(payload)
    for i in range(n):
        buf.append(int64(payload[i]))

def _pack(Value value, bool use_single_float, bool use_bin_type, int64 depth, list[bytes] parts):
    if depth > 1024:
        raise ValueError("MessagePack recursion limit exceeded")
    match value:
        case Value.Nil:
            parts.append(bytes([0xc0]))
        case Value.Bool(flag):
            if flag:
                parts.append(bytes([0xc3]))
            else:
                parts.append(bytes([0xc2]))
        case Value.Int(number):
            parts.append(_integer(number))
        case Value.UInt(number):
            parts.append(_unsigned(number))
        case Value.Float(number):
            parts.append(_float(number, use_single_float))
        case Value.Str(text):
            auto payload = bytes(text)
            parts.append(_text_header(len(payload), use_bin_type))
            parts.append(payload)
        case Value.Bin(payload):
            if use_bin_type:
                parts.append(_length_header(len(payload), 0, -1, 0xc4, 0xc5, 0xc6))
            else:
                parts.append(_text_header(len(payload), False))
            parts.append(payload)
        case Value.Array(items):
            parts.append(_length_header(len(items), 0x90, 15, -1, 0xdc, 0xdd))
            for item in items:
                _pack(item, use_single_float, use_bin_type, depth + 1, parts)
        case Value.Map(pairs):
            parts.append(_length_header(len(pairs), 0x80, 15, -1, 0xde, 0xdf))
            for pair in pairs:
                _pack(pair[0], use_single_float, use_bin_type, depth + 1, parts)
                _pack(pair[1], use_single_float, use_bin_type, depth + 1, parts)
        case Value.Ext(extension):
            parts.append(_extension_header(extension))
            parts.append(extension.data)
        case Value.Timestamp(timestamp):
            parts.append(_timestamp_wire(timestamp))

# Join fragments without repeatedly copying an ever-growing output prefix.
def _join_bytes(list[bytes] parts, int64 start, int64 stop) -> bytes:
    if stop - start == 1:
        return parts[start]
    auto middle = start + (stop - start) // 2
    return _join_bytes(parts, start, middle) + _join_bytes(parts, middle, stop)

def packb(Value value, bool use_single_float = False, bool use_bin_type = True) -> bytes:
    """Serialize a MessagePack value to bytes.

    Floats use binary64 by default. Set use_single_float=True for binary32.
    Set use_bin_type=False for legacy raw headers for strings and bytes.
    Raises ValueError for invalid extension codes or timestamp nanoseconds,
    oversized lengths, or nesting beyond 1,024 levels.
    """
    list[bytes] parts = []
    _pack(value, use_single_float, use_bin_type, 0, parts)
    return _join_bytes(parts, 0, len(parts))

def packb_with_default[T](T value, fn(T) -> ExtType default) -> bytes:
    """Convert one custom value to an application extension and encode it."""
    auto extension = default(value)
    return packb(Value.Ext(extension))

# Raised when the input ends before a complete value is available.
@exception
struct OutOfData:
    str message

# Raised when bytes remain after the first complete value.
@exception
struct ExtraData:
    str message

# Raised for an invalid tag, string payload, or strict map key.
@exception
struct FormatError:
    str message

# Raised when decoding would exceed the nesting limit.
@exception
struct StackError:
    str message

@exception
struct StrLimitError:
    str message

@exception
struct BinLimitError:
    str message

@exception
struct ArrayLimitError:
    str message

@exception
struct MapLimitError:
    str message

@exception
struct ExtLimitError:
    str message

value struct _DecodeLimits:
    int64 str_len
    int64 bin_len
    int64 array_len
    int64 map_len
    int64 ext_len
    int64 depth

    def validate(self):
        if self.str_len < -1 or self.bin_len < -1 or self.array_len < -1 or self.map_len < -1 or self.ext_len < -1:
            raise ValueError("MessagePack length limits must be -1 or nonnegative")
        if self.depth < 0 or self.depth > 1024:
            raise ValueError("MessagePack max_depth must be in 0..1024")

    def check_str(self, int64 length):
        if self.str_len >= 0 and length > self.str_len:
            raise StrLimitError("MessagePack string exceeds max_str_len")

    def check_bin(self, int64 length):
        if self.bin_len >= 0 and length > self.bin_len:
            raise BinLimitError("MessagePack binary exceeds max_bin_len")

    def check_array(self, int64 length):
        if self.array_len >= 0 and length > self.array_len:
            raise ArrayLimitError("MessagePack array exceeds max_array_len")

    def check_map(self, int64 length):
        if self.map_len >= 0 and length > self.map_len:
            raise MapLimitError("MessagePack map exceeds max_map_len")

    def check_ext(self, int64 length):
        if self.ext_len >= 0 and length > self.ext_len:
            raise ExtLimitError("MessagePack extension exceeds max_ext_len")

    def check_depth(self, int64 level):
        if level > self.depth:
            raise StackError("MessagePack recursion limit exceeded")

def _decoded_unsigned(uint64 word) -> Value:
    if word <= uint64(9223372036854775807):
        return Value.Int(int64(word))
    return Value.UInt(word)

def _decoded_signed(uint64 word, int64 width) -> int64:
    if width == 8:
        return int64(word)
    auto bits = width * 8
    auto value = int64(word)
    if value >= 1 << (bits - 1):
        return value - (1 << bits)
    return value

def _integer_width(int64 tag) -> int64:
    return 1 << ((tag - 0xcc) & 3)

def _length_width(int64 tag) -> int64:
    if tag >= 0xc4 and tag <= 0xc6:
        return 1 << (tag - 0xc4)
    if tag >= 0xc7 and tag <= 0xc9:
        return 1 << (tag - 0xc7)
    if tag >= 0xd9 and tag <= 0xdb:
        return 1 << (tag - 0xd9)
    if tag >= 0xdc and tag <= 0xdf:
        return 2 << ((tag - 0xdc) & 1)
    return 0

def _fixed_extension_length(int64 tag) -> int64:
    return 1 << (tag - 0xd4)

def _decoded_float(uint64 word, int64 bias, int64 fraction_bits, float64 fraction_scale) -> float64:
    auto fraction_mask = (uint64(1) << uint64(fraction_bits)) - uint64(1)
    auto fraction = int64(word & fraction_mask)
    auto exponent_mask = uint64(2 * bias + 1)
    auto exponent = int64((word >> uint64(fraction_bits)) & exponent_mask)
    auto negative = (word & (uint64(2 * (bias + 1)) << uint64(fraction_bits))) != uint64(0)
    auto magnitude = 0.0
    if exponent == int64(exponent_mask):
        if fraction != 0:
            return math.nan
        magnitude = math.inf
    elif exponent == 0:
        # The minimum normal exponent also scales subnormals and zero.
        magnitude = (float64(fraction) / fraction_scale) * math.pow(2.0, float64(1 - bias))
    else:
        magnitude = (1.0 + float64(fraction) / fraction_scale) * math.pow(2.0, float64(exponent - bias))
    if negative:
        return -magnitude
    return magnitude

def _check_map_key(Value key):
    match key:
        case Value.Str(text):
            return
        case Value.Bin(payload):
            return
        case _:
            raise FormatError("strict_map_key requires string or binary keys")

struct _Decoder:
    bytes data
    int64 pos
    bool raw
    bool strict_map_key
    _DecodeLimits limits

    def _require(self, int64 count):
        if count > len(self.data) - self.pos:
            raise OutOfData("Incomplete MessagePack value at byte " + str(self.pos))

    def _word(self, int64 width) -> uint64:
        self._require(width)
        auto word = uint64(0)
        auto end = self.pos + width
        while self.pos < end:
            word = (word << uint64(8)) | uint64(self.data[self.pos])
            self.pos = self.pos + 1
        return word

    def _payload(self, int64 length) -> bytes:
        self._require(length)
        auto start = self.pos
        self.pos = start + length
        return self.data[start:self.pos]

    def _text(self, int64 length) -> Value:
        self.limits.check_str(length)
        auto payload = self._payload(length)
        if self.raw:
            return Value.Bin(payload)
        auto text = ""
        try:
            text = str(payload)
        except Exception:
            raise FormatError("MessagePack string is not valid UTF-8")
        return Value.Str(text)

    def _binary(self, int64 length) -> Value:
        self.limits.check_bin(length)
        return Value.Bin(self._payload(length))

    def _extension(self, int64 length) -> Value:
        self.limits.check_ext(length)
        self._require(length + 1)
        auto code = int64(self._word(1))
        if code == 255:
            return self._timestamp(length)
        if code >= 128:
            raise FormatError("Reserved MessagePack extension code " + str(code - 256))
        return Value.Ext(ExtType(code, self._payload(length)))

    def _timestamp(self, int64 length) -> Value:
        auto seconds = 0
        auto nanos = uint64(0)
        if length == 4:
            seconds = int64(self._word(4))
        elif length == 8:
            auto word = self._word(8)
            seconds = int64(word & uint64(17179869183))
            nanos = word >> uint64(34)
        elif length == 12:
            nanos = self._word(4)
            seconds = int64(self._word(8))
        else:
            raise FormatError("MessagePack timestamp payload must be 4, 8, or 12 bytes")
        if nanos > uint64(999999999):
            raise FormatError("MessagePack timestamp nanoseconds must be in 0..999999999")
        return Value.Timestamp(Timestamp(seconds, uint32(nanos)))

    def _array(self, int64 length, int64 depth) -> Value:
        self.limits.check_array(length)
        # Each item needs a tag byte. Check before allocating the output list.
        self._require(length)
        list[Value] items = []
        auto index = 0
        while index < length:
            items.append(self._value(depth + 1))
            index = index + 1
        return Value.Array(items)

    def _map(self, int64 length, int64 depth) -> Value:
        self.limits.check_map(length)
        # Each pair needs two tags. Wire lengths are at most 2^32 - 1.
        self._require(2 * length)
        list[(Value, Value)] pairs = []
        auto index = 0
        while index < length:
            auto key = self._value(depth + 1)
            if self.strict_map_key:
                _check_map_key(key)
            auto value = self._value(depth + 1)
            pairs.append((key, value))
            index = index + 1
        return Value.Map(pairs)

    def _value(self, int64 depth) -> Value:
        self.limits.check_depth(depth)
        auto tag = int64(self._word(1))
        if tag <= 0x7f:
            return Value.Int(tag)
        if tag >= 0xe0:
            return Value.Int(tag - 256)
        if tag <= 0x8f:
            return self._map(tag - 0x80, depth)
        if tag <= 0x9f:
            return self._array(tag - 0x90, depth)
        if tag <= 0xbf:
            return self._text(tag - 0xa0)
        if tag == 0xc0:
            return Value.Nil
        if tag == 0xc2:
            return Value.Bool(False)
        if tag == 0xc3:
            return Value.Bool(True)
        if tag >= 0xc4 and tag <= 0xc6:
            return self._binary(int64(self._word(_length_width(tag))))
        if tag >= 0xc7 and tag <= 0xc9:
            return self._extension(int64(self._word(_length_width(tag))))
        if tag == 0xca:
            return Value.Float(_decoded_float(self._word(4), 127, 23, 8388608.0))
        if tag == 0xcb:
            return Value.Float(_decoded_float(self._word(8), 1023, 52, 4503599627370496.0))
        if tag >= 0xcc and tag <= 0xcf:
            return _decoded_unsigned(self._word(_integer_width(tag)))
        if tag >= 0xd0 and tag <= 0xd3:
            auto width = _integer_width(tag)
            return Value.Int(_decoded_signed(self._word(width), width))
        if tag >= 0xd4 and tag <= 0xd8:
            return self._extension(_fixed_extension_length(tag))
        if tag >= 0xd9 and tag <= 0xdb:
            return self._text(int64(self._word(_length_width(tag))))
        if tag == 0xdc or tag == 0xdd:
            return self._array(int64(self._word(_length_width(tag))), depth)
        if tag == 0xde or tag == 0xdf:
            return self._map(int64(self._word(_length_width(tag))), depth)
        raise FormatError("Reserved MessagePack tag 0xc1")

def _unpackb(bytes data, bool raw, bool strict_map_key, _DecodeLimits limits) -> Value:
    auto decoder = _Decoder(data, 0, raw, strict_map_key, limits)
    auto value = decoder._value(0)
    if decoder.pos != len(data):
        raise ExtraData("Trailing data after MessagePack value at byte " + str(decoder.pos))
    return value

def unpackb(
    bytes data,
    bool raw = False,
    bool strict_map_key = True,
    int64 max_str_len = -1,
    int64 max_bin_len = -1,
    int64 max_array_len = -1,
    int64 max_map_len = -1,
    int64 max_ext_len = -1,
    int64 max_depth = 1024,
) -> Value:
    """Decode exactly one MessagePack value.

    Set raw=True to decode string payloads as bytes. Map keys must be strings
    or binary values unless strict_map_key=False is set. Maps preserve pair
    order and duplicates.

    Length limits default to -1 and the input still bounds available bytes.
    Set max_depth to 0..1024, counting the root as depth zero. Length and
    nesting violations raise their typed limit errors before reading bodies.
    """
    auto limits = _DecodeLimits(max_str_len, max_bin_len, max_array_len, max_map_len, max_ext_len, max_depth)
    limits.validate()
    return _unpackb(data, raw, strict_map_key, limits)

def unpackb_with_ext_hook[T](bytes data, fn(int64, bytes) -> T ext_hook) -> T:
    """Decode one complete application extension and return the typed hook result."""
    match unpackb(data):
        case Value.Ext(extension):
            return ext_hook(extension.code, extension.data)
        case _:
            raise FormatError("Expected a top-level MessagePack application extension")

# Incremental encoding with the same options for each value in a stream.
struct Packer:
    bool use_single_float = False
    bool use_bin_type = True

    def pack(self, Value value) -> bytes:
        """Encode one value for immediate writing to a stream."""
        return packb(value, use_single_float=self.use_single_float, use_bin_type=self.use_bin_type)

# Raised when a feed would exceed the unread-byte budget.
@exception
struct BufferFull:
    str message

# Feed bytes from any source and iterate over the available complete values.
struct Unpacker:
    bool raw = False
    bool strict_map_key = True
    int64 max_buffer_size = 104857600
    int64 max_str_len = -1
    int64 max_bin_len = -1
    int64 max_array_len = -1
    int64 max_map_len = -1
    int64 max_ext_len = -1
    int64 max_depth = 1024
    list[bytes] _chunks = []
    int64 _count = 0
    int64 _head_offset = 0
    int64 _buffered = 0
    int64 _scanned = 0
    bool _ready = False
    int64 _payload_left = 0
    int64 _header_left = 0
    int64 _header_tag = 0
    int64 _length = 0
    list[int64] _children = []
    int64 _depth = 0

    def feed(self, bytes chunk):
        """Append input. Raise BufferFull without accepting any bytes if full."""
        auto limit = self.max_buffer_size
        if limit < 0:
            raise ValueError("max_buffer_size must be nonnegative")
        if limit == 0:
            limit = 4294967295
        if len(chunk) == 0:
            return
        if len(chunk) > limit - self._buffered:
            raise BufferFull("MessagePack input exceeds max_buffer_size")

        # Merge similarly sized chunks to bound fragment metadata even when
        # input arrives one byte at a time. Preserve a partially consumed head.
        auto current = chunk
        while self._count > 0:
            auto last = self._count - 1
            if last == 0 and self._head_offset != 0:
                break
            auto previous = self._chunks[last]
            if len(previous) > len(current):
                break
            self._chunks[last] = b""
            self._count = last
            current = previous + current
        if self._count == len(self._chunks):
            self._chunks.append(current)
        else:
            self._chunks[self._count] = current
        self._count = self._count + 1
        self._buffered = self._buffered + len(chunk)

    def _done(self) -> bool:
        while self._depth > 0:
            auto parent = self._depth - 1
            auto left = self._children[parent] - 1
            if left > 0:
                self._children[parent] = left
                return False
            self._depth = parent
        return True

    def _container(self, int64 children) -> bool:
        if children == 0:
            return self._done()
        if self._depth == len(self._children):
            self._children.append(children)
        else:
            self._children[self._depth] = children
        self._depth = self._depth + 1
        return False

    def _skip_payload(self, int64 length) -> bool:
        self._payload_left = length
        if length == 0:
            return self._done()
        return False

    def _framed_length(self, int64 tag, int64 length, _DecodeLimits limits) -> bool:
        if tag == 0xdc or tag == 0xdd:
            limits.check_array(length)
            return self._container(length)
        if tag == 0xde or tag == 0xdf:
            limits.check_map(length)
            return self._container(2 * length)
        if tag >= 0xc7 and tag <= 0xc9:
            limits.check_ext(length)
            return self._skip_payload(length + 1)
        if tag >= 0xc4 and tag <= 0xc6:
            limits.check_bin(length)
        else:
            limits.check_str(length)
        return self._skip_payload(length)

    def _step(self, int64 octet, _DecodeLimits limits) -> bool:
        if self._header_left > 0:
            auto length = self._length * 256 + octet
            if self._header_left > 1:
                self._length = length
                self._header_left = self._header_left - 1
                return False
            # Commit only after checking the declared length. A failed read
            # must leave the last length byte and the parser state intact.
            auto ready = self._framed_length(self._header_tag, length, limits)
            self._header_left = 0
            return ready
        limits.check_depth(self._depth)
        if octet <= 0x7f or octet >= 0xe0 or octet == 0xc0 or octet == 0xc2 or octet == 0xc3:
            return self._done()
        if octet <= 0x8f:
            auto length = octet - 0x80
            limits.check_map(length)
            return self._container(2 * length)
        if octet <= 0x9f:
            auto length = octet - 0x90
            limits.check_array(length)
            return self._container(length)
        if octet <= 0xbf:
            auto length = octet - 0xa0
            limits.check_str(length)
            return self._skip_payload(length)
        if octet == 0xca:
            return self._skip_payload(4)
        if octet == 0xcb:
            return self._skip_payload(8)
        if octet >= 0xcc and octet <= 0xd3:
            return self._skip_payload(_integer_width(octet))
        if octet >= 0xd4 and octet <= 0xd8:
            auto length = _fixed_extension_length(octet)
            limits.check_ext(length)
            return self._skip_payload(length + 1)
        auto width = _length_width(octet)
        if width > 0:
            self._header_left = width
            self._header_tag = octet
            self._length = 0
            return False
        raise FormatError("Reserved MessagePack tag 0xc1")

    def _scan(self, _DecodeLimits limits):
        # Keep the parser state and logical offset across calls. A feed may
        # merge physical chunks, so locate the saved offset before resuming.
        auto offset = self._head_offset + self._scanned
        auto index = 0
        while index < self._count and not self._ready:
            auto chunk = self._chunks[index]
            if offset >= len(chunk):
                offset = offset - len(chunk)
            else:
                while offset < len(chunk) and not self._ready:
                    auto count = 1
                    if self._payload_left > 0:
                        count = len(chunk) - offset
                        if count > self._payload_left:
                            count = self._payload_left
                        self._payload_left = self._payload_left - count
                        if self._payload_left == 0:
                            self._ready = self._done()
                    else:
                        self._ready = self._step(chunk[offset], limits)
                    offset = offset + count
                    self._scanned = self._scanned + count
                offset = 0
            index = index + 1

    def _read_frame(self, _DecodeLimits limits) -> Value:
        list[bytes] parts = []
        auto left = self._scanned
        auto offset = self._head_offset
        auto first = 0
        while left > 0:
            auto chunk = self._chunks[first]
            auto count = len(chunk) - offset
            if count > left:
                count = left
            auto end = offset + count
            if offset == 0 and end == len(chunk):
                parts.append(chunk)
            else:
                parts.append(chunk[offset:end])
            left = left - count
            offset = end
            if offset == len(chunk):
                first = first + 1
                offset = 0
        auto frame = _join_bytes(parts, 0, len(parts))
        auto value = _unpackb(frame, self.raw, self.strict_map_key, limits)
        # Advance only after validation so a data error cannot discard input.
        auto index = 0
        while index < self._count - first:
            self._chunks[index] = self._chunks[first + index]
            index = index + 1
        auto count = index
        while index < self._count:
            self._chunks[index] = b""
            index = index + 1
        self._count = count
        self._head_offset = offset
        self._buffered = self._buffered - self._scanned
        self._scanned = 0
        self._ready = False
        return value

    def unpack(self) -> Value:
        """Return the next value, or raise OutOfData until more bytes arrive."""
        auto limits = _DecodeLimits(self.max_str_len, self.max_bin_len, self.max_array_len, self.max_map_len, self.max_ext_len, self.max_depth)
        limits.validate()
        self._scan(limits)
        if not self._ready:
            raise OutOfData("Incomplete MessagePack stream value")
        return self._read_frame(limits)

    def __iter__(self) -> Unpacker:
        """Return this single-pass iterator over the unread values."""
        return self

    def __next__(self) -> Value:
        """Stop iteration on incomplete input so feed can resume it later."""
        try:
            return self.unpack()
        except OutOfData:
            raise StopIteration


# ---------------------------------------------------------------------------
# serde integration (E6.3, zaplang-io/zap#1552): typed `pack` / `unpack` for any
# struct via the bundled `serde` foundation (zaplang-io/zap#1570), with NO
# per-codec compiler support — msgpack is a pure library that implements the
# `serde.Serializer` / `serde.Deserializer` backend interfaces and reuses serde's
# generic drivers. A struct encodes as a MessagePack **map** of field name ->
# value, byte-conformant with the spec and interoperable with the `Value` DOM
# codec above. This release follows serde's current surface: scalars (`int64` /
# `uint64` / `float64` / `str` / `bool` / `bytes`), nested structs on encode,
# `list[T]` / `dict[str, V]` of scalar elements, `Optional[T]` of a scalar (both
# directions), and `enum` types (encode: all variants; decode: constant/payload-free
# variants). `float64` encodes as binary64, `bytes` as a bin header, `list` as an
# array, `dict` as a map, `uint64` as an unsigned int, `Optional` None as nil, an
# enum variant tag as its name (a string). Serde's nested-struct decode and
# payload-carrying enum decode remain later additions (tracked in
# zaplang-io/zap#1561 / zap#1606).

# A `serde.Serializer` backend that writes MessagePack bytes into ONE growable
# buffer. serde's `begin_struct` / `begin_seq` / `begin_map` carry no element count
# (a fixmap / map16 / map32 header needs it up front), so at each `begin_*` the
# serializer reserves a single placeholder byte and records its offset; `end_*`
# back-patches it. The common case — a container of <= 15 entries — patches the
# one reserved byte in place (a fixmap / fixarray tag), with NO buffer shift; only a
# container larger than 15 entries splices in a 3- or 5-byte header (rare). This
# replaces the old per-frame `list[list[bytes]]` + join, so a whole record
# serializes with one buffer and no per-value `bytes` allocation.
struct MsgpackSerializer:
    list[int64] buf = []
    # Open-container stack (parallel lists): the offset of each container's reserved
    # 1-byte header placeholder, its running entry count, and its kind
    # (0 = struct map, 1 = sequence/array, 2 = dict map — dict emits arrive as
    # alternating key, value, so its entry count is twice the pair count).
    list[int64] frame_off = []
    list[int64] frame_count = []
    list[int64] frame_kind = []
    str pending_key = ""

    def field_name(self, str name):
        self.pending_key = name

    # Called before every value (scalar or nested container). In a struct frame the
    # value is preceded by its field-name key; every frame counts the value. With no
    # frame open (a top-level enum — serde opens no struct frame for one) nothing is
    # keyed or counted; the value is written straight into the buffer.
    def _pre_value(self):
        auto top = len(self.frame_kind) - 1
        if top >= 0:
            if self.frame_kind[top] == 0:
                auto kb = bytes(self.pending_key)
                _put_text_header(self.buf, len(kb), True)
                _put_payload(self.buf, kb)
            self.frame_count[top] = self.frame_count[top] + 1

    # Open a container: emit its key (if inside a struct), reserve a placeholder
    # header byte, and push the frame.
    def _begin(self, int64 kind):
        self._pre_value()
        self.frame_off.append(len(self.buf))
        self.buf.append(0)
        self.frame_count.append(0)
        self.frame_kind.append(kind)

    def begin_struct(self):
        self._begin(0)

    def begin_seq(self):
        self._begin(1)

    def begin_map(self):
        self._begin(2)

    def emit_int(self, int64 v):
        self._pre_value()
        _put_integer(self.buf, v)

    def emit_uint(self, uint64 v):
        self._pre_value()
        _put_unsigned(self.buf, v)

    def emit_float(self, float64 v):
        self._pre_value()
        _put_float(self.buf, v, False)

    def emit_str(self, str v):
        self._pre_value()
        auto payload = bytes(v)
        _put_text_header(self.buf, len(payload), True)
        _put_payload(self.buf, payload)

    def emit_bool(self, bool v):
        self._pre_value()
        if v:
            self.buf.append(0xc3)
        else:
            self.buf.append(0xc2)

    def emit_bytes(self, bytes v):
        self._pre_value()
        _put_length_header(self.buf, len(v), 0, -1, 0xc4, 0xc5, 0xc6)
        _put_payload(self.buf, v)

    # `Optional` None encodes as the MessagePack nil byte; a `Some` emits its inner
    # value directly (serde calls the matching `emit_*`).
    def emit_nil(self):
        self._pre_value()
        self.buf.append(0xc0)

    # An enum variant tag encodes as its name (a MessagePack string); any payload
    # values follow via the matching `emit_*`.
    def emit_variant(self, str name):
        self._pre_value()
        auto payload = bytes(name)
        _put_text_header(self.buf, len(payload), True)
        _put_payload(self.buf, payload)

    # Close a container: back-patch the reserved placeholder byte. `fix_tag + n` is
    # the fixmap / fixarray tag for n <= 15 (patched in place); otherwise splice a
    # 3- or 5-byte `tag16` / `tag32` header in where the placeholder sits.
    def _end(self, int64 n, int64 fix_tag, int64 tag16, int64 tag32):
        auto off = self.frame_off.pop()
        auto _c = self.frame_count.pop()
        auto _k = self.frame_kind.pop()
        if n <= 15:
            self.buf[off] = fix_tag + n
        else:
            list[int64] hdr = []
            _put_length_header(hdr, n, fix_tag, 15, -1, tag16, tag32)
            list[int64] spliced = self.buf[0:off]
            for h in hdr:
                spliced.append(h)
            auto total = len(self.buf)
            for i in range(off + 1, total):
                spliced.append(self.buf[i])
            self.buf = spliced

    def end_struct(self):
        self._end(self.frame_count[len(self.frame_count) - 1], 0x80, 0xde, 0xdf)

    def end_seq(self):
        self._end(self.frame_count[len(self.frame_count) - 1], 0x90, 0xdc, 0xdd)

    def end_map(self):
        self._end(self.frame_count[len(self.frame_count) - 1] // 2, 0x80, 0xde, 0xdf)

# Serialize any struct `T` to MessagePack bytes (a map of field -> value) through
# the serde driver. Example: `auto wire = msgpack.pack(record)`.
def pack[T](T value) -> bytes:
    auto s = MsgpackSerializer()
    serde.serialize(value, s)
    return bytes(s.buf)

# A `serde.Deserializer` backend that serves decoded map entries positionally, in
# field-declaration order (the order `pack` writes them). It decodes the wire via
# A STREAMING `serde.Deserializer`: it decodes straight from the wire into the
# struct, with no intermediate `Value` DOM. It wraps a `_Decoder` cursor and a
# context stack (0 = struct, 1 = sequence, 2 = map). In a struct context each
# field's entry is a key + value, so a read first skips the key; in a sequence or
# map context the reads are positional (array elements, or a dict's alternating
# key, value). `begin_seq` / `begin_map` read only the array / map **header** (the
# count) — the elements are then streamed one at a time — so a nested collection is
# never materialized as a whole, and there is no second pass over a DOM. Scalars
# reuse the proven `_Decoder._value` (one transient leaf, no container allocation).
struct MsgpackDeserializer:
    _Decoder dec
    list[int64] ctx = []
    # `begin_optional` consumes the field key itself (to peek the value for nil),
    # so the following `read_*` of a `Some` value must NOT skip a key again. This
    # one-shot flag suppresses exactly that next key-skip.
    bool suppress_key = False

    # In a struct context the next wire item is the field key; consume and discard
    # it so the following read lands on the value. A pending suppression (set by
    # `begin_optional`, which already consumed the key) is honored once.
    def _skip_key(self):
        if self.suppress_key:
            self.suppress_key = False
            return
        auto top = len(self.ctx) - 1
        if top >= 0 and self.ctx[top] == 0:
            auto _k = self.dec._value(0)

    # Read an array / map header tag and return its length, without reading a body.
    def _header_len(self, int64 fix_lo, int64 fix_hi, int64 tag16, int64 tag32, str what) -> int64:
        auto tag = int64(self.dec._word(1))
        if tag >= fix_lo and tag <= fix_hi:
            return tag - fix_lo
        if tag == tag16:
            return int64(self.dec._word(2))
        if tag == tag32:
            return int64(self.dec._word(4))
        raise FormatError("msgpack.unpack: expected " + what)

    def begin_struct(self):
        self._skip_key()
        auto _n = self._header_len(0x80, 0x8f, 0xde, 0xdf, "a map (struct)")
        self.ctx.append(0)

    def end_struct(self):
        self.ctx = self.ctx[0:len(self.ctx) - 1]

    # Native scalar reads: parse the tag + payload straight into the Zap value,
    # with no intermediate `Value` leaf. This is the hot path for list / dict
    # elements, so avoiding a per-element allocation is what lets the streaming
    # decoder beat the DOM path.
    def read_int(self, str field) -> int64:
        self._skip_key()
        auto tag = int64(self.dec._word(1))
        if tag <= 0x7f:
            return tag
        if tag >= 0xe0:
            return tag - 256
        if tag >= 0xcc and tag <= 0xcf:
            return int64(self.dec._word(_integer_width(tag)))
        if tag >= 0xd0 and tag <= 0xd3:
            auto w = _integer_width(tag)
            return _decoded_signed(self.dec._word(w), w)
        raise FormatError("msgpack.unpack: expected an integer for field '" + field + "'")

    def read_uint(self, str field) -> uint64:
        self._skip_key()
        auto tag = int64(self.dec._word(1))
        if tag <= 0x7f:
            return uint64(tag)
        if tag >= 0xcc and tag <= 0xcf:
            return self.dec._word(_integer_width(tag))
        if tag >= 0xd0 and tag <= 0xd3:
            auto w = _integer_width(tag)
            return uint64(_decoded_signed(self.dec._word(w), w))
        raise FormatError("msgpack.unpack: expected an unsigned integer for field '" + field + "'")

    def read_float(self, str field) -> float64:
        self._skip_key()
        auto tag = int64(self.dec._word(1))
        if tag == 0xca:
            return _decoded_float(self.dec._word(4), 127, 23, 8388608.0)
        if tag == 0xcb:
            return _decoded_float(self.dec._word(8), 1023, 52, 4503599627370496.0)
        raise FormatError("msgpack.unpack: expected a float for field '" + field + "'")

    def read_str(self, str field) -> str:
        self._skip_key()
        auto tag = int64(self.dec._word(1))
        auto length = -1
        if tag >= 0xa0 and tag <= 0xbf:
            length = tag - 0xa0
        elif tag >= 0xd9 and tag <= 0xdb:
            length = int64(self.dec._word(_length_width(tag)))
        else:
            raise FormatError("msgpack.unpack: expected a string for field '" + field + "'")
        return str(self.dec._payload(length))

    def read_bool(self, str field) -> bool:
        self._skip_key()
        auto tag = int64(self.dec._word(1))
        if tag == 0xc2:
            return False
        if tag == 0xc3:
            return True
        raise FormatError("msgpack.unpack: expected a boolean for field '" + field + "'")

    def read_bytes(self, str field) -> bytes:
        self._skip_key()
        auto tag = int64(self.dec._word(1))
        if tag >= 0xc4 and tag <= 0xc6:
            return self.dec._payload(int64(self.dec._word(_length_width(tag))))
        raise FormatError("msgpack.unpack: expected binary for field '" + field + "'")

    # `Optional`: skip the field key, then peek the value tag. A nil (0xc0) is a
    # `None` — consume it and return False. Otherwise it is a `Some`: return True
    # and leave the value to the following `read_*`, suppressing that read's key
    # skip (this call already consumed the key).
    def begin_optional(self, str field) -> bool:
        self._skip_key()
        self.dec._require(1)
        if int64(self.dec.data[self.dec.pos]) == 0xc0:
            self.dec.pos = self.dec.pos + 1
            return False
        self.suppress_key = True
        return True

    # Read an enum variant tag: a MessagePack string. An enum decodes at the top
    # level (no struct context), so no key precedes it.
    def read_variant(self) -> str:
        self._skip_key()
        auto tag = int64(self.dec._word(1))
        auto length = -1
        if tag >= 0xa0 and tag <= 0xbf:
            length = tag - 0xa0
        elif tag >= 0xd9 and tag <= 0xdb:
            length = int64(self.dec._word(_length_width(tag)))
        else:
            raise FormatError("msgpack.unpack: expected an enum variant tag (string)")
        return str(self.dec._payload(length))

    def begin_seq(self, str field) -> int64:
        self._skip_key()
        auto n = self._header_len(0x90, 0x9f, 0xdc, 0xdd, "an array for field '" + field + "'")
        self.ctx.append(1)
        return n

    def end_seq(self):
        self.ctx = self.ctx[0:len(self.ctx) - 1]

    def begin_map(self, str field) -> int64:
        self._skip_key()
        auto n = self._header_len(0x80, 0x8f, 0xde, 0xdf, "a map for field '" + field + "'")
        self.ctx.append(2)
        return n

    def end_map(self):
        self.ctx = self.ctx[0:len(self.ctx) - 1]

# Decode MessagePack bytes into a struct `T` whose fields are scalars (int64 /
# uint64 / float64 / str / bool / bytes) and `list` / `dict[str, V]` of scalars,
# streaming straight from the wire (no `Value` DOM). Both type arguments are
# explicit, as serde requires: `msgpack.unpack[Rec](wire)`.
def unpack[T](bytes data) -> T:
    auto limits = _DecodeLimits(-1, -1, -1, -1, -1, 1024)
    auto dec = _Decoder(data, 0, False, True, limits)
    auto d = MsgpackDeserializer(dec, [])
    return serde.deserialize[T, MsgpackDeserializer](d)
