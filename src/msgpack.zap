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
