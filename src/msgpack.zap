import math

# The application code and payload of a MessagePack extension.
struct ExtType:
    int64 code
    bytes data

# Signed Unix seconds and a nonnegative fractional nanosecond component.
struct Timestamp:
    int64 seconds
    uint32 nanoseconds

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

def _tagged_word(int64 tag, uint64 word, int64 width) -> bytes:
    list[int64] octets = [tag]
    auto shift = (width - 1) * 8
    while shift >= 0:
        octets.append(int64((word >> uint64(shift)) & uint64(255)))
        shift = shift - 8
    return bytes(octets)

def _unsigned(uint64 value) -> bytes:
    if value <= uint64(127):
        return bytes([int64(value)])
    if value <= uint64(255):
        return _tagged_word(0xcc, value, 1)
    if value <= uint64(65535):
        return _tagged_word(0xcd, value, 2)
    if value <= uint64(4294967295):
        return _tagged_word(0xce, value, 4)
    return _tagged_word(0xcf, value, 8)

def _integer(int64 value) -> bytes:
    if value >= 0:
        return _unsigned(uint64(value))
    if value >= -32:
        return bytes([value + 256])
    if value >= -128:
        return _tagged_word(0xd0, uint64(value), 1)
    if value >= -32768:
        return _tagged_word(0xd1, uint64(value), 2)
    if value >= -2147483648:
        return _tagged_word(0xd2, uint64(value), 4)
    return _tagged_word(0xd3, uint64(value), 8)

def _length_header(int64 length, int64 fix_tag, int64 fix_max, int64 tag8, int64 tag16, int64 tag32) -> bytes:
    if length <= fix_max:
        return bytes([fix_tag + length])
    if tag8 >= 0 and length <= 255:
        return _tagged_word(tag8, uint64(length), 1)
    if length <= 65535:
        return _tagged_word(tag16, uint64(length), 2)
    if length <= 4294967295:
        return _tagged_word(tag32, uint64(length), 4)
    raise ValueError("MessagePack length exceeds 32 bits")

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

def _float(float64 value, bool use_single_float) -> bytes:
    if use_single_float:
        return _tagged_word(0xca, _float_bits(value, 127, 23, 8388608.0), 4)
    return _tagged_word(0xcb, _float_bits(value, 1023, 52, 4503599627370496.0), 8)

def _pack(Value value, bool use_single_float, int64 depth, list[bytes] parts):
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
            parts.append(_length_header(len(payload), 0xa0, 31, 0xd9, 0xda, 0xdb))
            parts.append(payload)
        case Value.Bin(payload):
            parts.append(_length_header(len(payload), 0, -1, 0xc4, 0xc5, 0xc6))
            parts.append(payload)
        case Value.Array(items):
            parts.append(_length_header(len(items), 0x90, 15, -1, 0xdc, 0xdd))
            for item in items:
                _pack(item, use_single_float, depth + 1, parts)
        case Value.Map(pairs):
            parts.append(_length_header(len(pairs), 0x80, 15, -1, 0xde, 0xdf))
            for pair in pairs:
                _pack(pair[0], use_single_float, depth + 1, parts)
                _pack(pair[1], use_single_float, depth + 1, parts)
        case Value.Ext(extension):
            raise ValueError("MessagePack application extensions are not supported yet")
        case Value.Timestamp(timestamp):
            raise ValueError("MessagePack timestamps are not supported yet")

# Join fragments without repeatedly copying an ever-growing output prefix.
def _join_bytes(list[bytes] parts, int64 start, int64 stop) -> bytes:
    if stop - start == 1:
        return parts[start]
    auto middle = start + (stop - start) // 2
    return _join_bytes(parts, start, middle) + _join_bytes(parts, middle, stop)

def packb(Value value, bool use_single_float = False) -> bytes:
    """Serialize one base MessagePack value to bytes.

    Floats use binary64 by default. Set use_single_float=True for binary32.
    Raises ValueError for extensions, oversized lengths, or nesting beyond
    1,024 levels.
    """
    list[bytes] parts = []
    _pack(value, use_single_float, 0, parts)
    return _join_bytes(parts, 0, len(parts))

# Raised when the input ends before a complete value is available.
struct OutOfData:
    str message

# Raised when bytes remain after the first complete value.
struct ExtraData:
    str message

# Raised for an invalid tag, string payload, or strict map key.
struct FormatError:
    str message

# Raised when decoding would exceed the nesting limit.
struct StackError:
    str message

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
    if tag >= 0xd9 and tag <= 0xdb:
        return 1 << (tag - 0xd9)
    if tag >= 0xdc and tag <= 0xdf:
        return 2 << ((tag - 0xdc) & 1)
    return 0

def _invalid_tag_message(int64 tag) -> str:
    if tag == 0xc1:
        return "Reserved MessagePack tag 0xc1"
    return "MessagePack extensions are not supported yet"

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
        auto payload = self._payload(length)
        if self.raw:
            return Value.Bin(payload)
        auto text = ""
        try:
            text = str(payload)
        except Exception:
            raise FormatError("MessagePack string is not valid UTF-8")
        return Value.Str(text)

    def _array(self, int64 length, int64 depth) -> Value:
        # Each item needs a tag byte. Check before allocating the output list.
        self._require(length)
        list[Value] items = []
        auto index = 0
        while index < length:
            items.append(self._value(depth + 1))
            index = index + 1
        return Value.Array(items)

    def _map(self, int64 length, int64 depth) -> Value:
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
        if depth > 1024:
            raise StackError("MessagePack recursion limit exceeded")
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
            return Value.Bin(self._payload(int64(self._word(_length_width(tag)))))
        if tag == 0xca:
            return Value.Float(_decoded_float(self._word(4), 127, 23, 8388608.0))
        if tag == 0xcb:
            return Value.Float(_decoded_float(self._word(8), 1023, 52, 4503599627370496.0))
        if tag >= 0xcc and tag <= 0xcf:
            return _decoded_unsigned(self._word(_integer_width(tag)))
        if tag >= 0xd0 and tag <= 0xd3:
            auto width = _integer_width(tag)
            return Value.Int(_decoded_signed(self._word(width), width))
        if tag >= 0xd9 and tag <= 0xdb:
            return self._text(int64(self._word(_length_width(tag))))
        if tag == 0xdc or tag == 0xdd:
            return self._array(int64(self._word(_length_width(tag))), depth)
        if tag == 0xde or tag == 0xdf:
            return self._map(int64(self._word(_length_width(tag))), depth)
        raise FormatError(_invalid_tag_message(tag))

def unpackb(bytes data, bool raw = False, bool strict_map_key = True) -> Value:
    """Decode exactly one base MessagePack value.

    Set raw=True to decode string payloads as bytes. Map keys must be strings
    or binary values unless strict_map_key=False is set. Maps preserve pair
    order and duplicates.

    Raises OutOfData for incomplete input, ExtraData for trailing bytes,
    FormatError for invalid or unsupported values, and StackError for nesting
    beyond 1,024 levels.
    """
    auto decoder = _Decoder(data, 0, raw, strict_map_key)
    auto value = decoder._value(0)
    if decoder.pos != len(data):
        raise ExtraData("Trailing data after MessagePack value at byte " + str(decoder.pos))
    return value

# Incremental encoding with the same float policy for each value in a stream.
struct Packer:
    bool use_single_float = False

    def pack(self, Value value) -> bytes:
        """Encode one value for immediate writing to a stream."""
        return packb(value, use_single_float=self.use_single_float)

# Raised when a feed would exceed the unread-byte budget.
struct BufferFull:
    str message

# Feed bytes from any source and iterate over the available complete values.
struct Unpacker:
    bool raw = False
    bool strict_map_key = True
    int64 max_buffer_size = 104857600
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

    def _step(self, int64 octet) -> bool:
        if self._header_left > 0:
            self._length = self._length * 256 + octet
            self._header_left = self._header_left - 1
            if self._header_left > 0:
                return False
            if self._header_tag == 0xdc or self._header_tag == 0xdd:
                return self._container(self._length)
            if self._header_tag == 0xde or self._header_tag == 0xdf:
                return self._container(2 * self._length)
            return self._skip_payload(self._length)
        if self._depth > 1024:
            raise StackError("MessagePack recursion limit exceeded")
        if octet <= 0x7f or octet >= 0xe0 or octet == 0xc0 or octet == 0xc2 or octet == 0xc3:
            return self._done()
        if octet <= 0x8f:
            return self._container(2 * (octet - 0x80))
        if octet <= 0x9f:
            return self._container(octet - 0x90)
        if octet <= 0xbf:
            return self._skip_payload(octet - 0xa0)
        if octet == 0xca:
            return self._skip_payload(4)
        if octet == 0xcb:
            return self._skip_payload(8)
        if octet >= 0xcc and octet <= 0xd3:
            return self._skip_payload(_integer_width(octet))
        auto width = _length_width(octet)
        if width > 0:
            self._header_left = width
            self._header_tag = octet
            self._length = 0
            return False
        raise FormatError(_invalid_tag_message(octet))

    def _scan(self):
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
                        self._ready = self._step(chunk[offset])
                    offset = offset + count
                    self._scanned = self._scanned + count
                offset = 0
            index = index + 1

    def _read_frame(self) -> Value:
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
        auto value = unpackb(frame, raw=self.raw, strict_map_key=self.strict_map_key)
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
        self._scan()
        if not self._ready:
            raise OutOfData("Incomplete MessagePack stream value")
        return self._read_frame()

    def __iter__(self) -> Unpacker:
        """Return this single-pass iterator over the unread values."""
        return self

    def __next__(self) -> Value:
        """Stop iteration on incomplete input so feed can resume it later."""
        try:
            return self.unpack()
        except OutOfData:
            raise StopIteration
