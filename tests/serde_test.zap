# E6.3: the serde-based typed codec (`pack` / `unpack` over the bundled `serde`
# foundation). Proves the serde path is byte-identical to the hand-rolled `Value`
# DOM map, round-trips, and interoperates with the DOM codec in both directions.

def _ok(bool condition, str label):
    assert condition, label

struct SerdeRec:
    int64 id
    str name
    bool active
    int64 count

def _rec_dom() -> Value:
    return Value.Map([
        (Value.Str("id"), Value.Int(7)),
        (Value.Str("name"), Value.Str("item-7")),
        (Value.Str("active"), Value.Bool(True)),
        (Value.Str("count"), Value.Int(42)),
    ])

@test
def test_pack_is_byte_identical_to_the_dom_map():
    auto r = SerdeRec(7, "item-7", True, 42)
    _ok(pack(r) == packb(_rec_dom()), "serde pack equals the hand-built Value.Map wire")

@test
def test_round_trip_reconstructs_every_field():
    auto r = SerdeRec(7, "item-7", True, 42)
    auto r2 = unpack[SerdeRec](pack(r))
    _ok(r2.id == 7, "id")
    _ok(r2.name == "item-7", "name")
    _ok(r2.active == True, "active")
    _ok(r2.count == 42, "count")

@test
def test_unpack_decodes_hand_rolled_dom_bytes():
    auto r = unpack[SerdeRec](packb(_rec_dom()))
    _ok(r.id == 7 and r.name == "item-7" and r.active == True and r.count == 42, "interop: serde decodes DOM bytes")

@test
def test_edge_scalars_round_trip():
    auto r = SerdeRec(-9223372036854775807 - 1, "", False, 0)
    auto r2 = unpack[SerdeRec](pack(r))
    _ok(r2.id == -9223372036854775807 - 1, "int64 min")
    _ok(r2.name == "", "empty string")
    _ok(r2.active == False, "false bool")
    _ok(r2.count == 0, "zero")

struct SerdeInner:
    int64 a
    bool flag

struct SerdeOuter:
    int64 id
    SerdeInner inner

@test
def test_nested_struct_encodes_as_a_nested_map():
    auto o = SerdeOuter(5, SerdeInner(9, True))
    auto dom = Value.Map([
        (Value.Str("id"), Value.Int(5)),
        (Value.Str("inner"), Value.Map([
            (Value.Str("a"), Value.Int(9)),
            (Value.Str("flag"), Value.Bool(True)),
        ])),
    ])
    _ok(pack(o) == packb(dom), "nested struct packs as a nested map, byte-identical to the DOM")

struct SerdeMeasure:
    int64 id
    float64 score
    bytes blob

@test
def test_float_and_bytes_round_trip():
    auto r = SerdeMeasure(1, 2.5, bytes([1, 2, 255]))
    auto r2 = unpack[SerdeMeasure](pack(r))
    _ok(r2.id == 1, "id")
    _ok(r2.score == 2.5, "float64 round-trip")
    _ok(r2.blob == bytes([1, 2, 255]), "raw bytes round-trip")

@test
def test_float_and_bytes_match_the_dom():
    auto r = SerdeMeasure(1, 2.5, bytes([1, 2, 255]))
    auto dom = Value.Map([
        (Value.Str("id"), Value.Int(1)),
        (Value.Str("score"), Value.Float(2.5)),
        (Value.Str("blob"), Value.Bin(bytes([1, 2, 255]))),
    ])
    _ok(pack(r) == packb(dom), "float64 + bytes pack equals the hand-built DOM")

struct SerdeColl:
    int64 id
    list[int64] nums
    dict[str, int64] tags
    uint64 big

@test
def test_collections_round_trip():
    auto r = SerdeColl(7, [10, 20, 30], {"k": 9}, uint64(42))
    auto r2 = unpack[SerdeColl](pack(r))
    _ok(r2.id == 7, "id")
    _ok(len(r2.nums) == 3 and r2.nums[2] == 30, "list[int64] round-trip")
    _ok(len(r2.tags) == 1 and r2.tags["k"] == 9, "dict[str,int64] round-trip")
    _ok(r2.big == uint64(42), "uint64 round-trip")

@test
def test_collections_match_the_dom():
    auto r = SerdeColl(7, [10, 20], {"k": 9}, uint64(42))
    auto dom = Value.Map([
        (Value.Str("id"), Value.Int(7)),
        (Value.Str("nums"), Value.Array([Value.Int(10), Value.Int(20)])),
        (Value.Str("tags"), Value.Map([(Value.Str("k"), Value.Int(9))])),
        (Value.Str("big"), Value.UInt(uint64(42))),
    ])
    _ok(pack(r) == packb(dom), "list + dict + uint64 pack equals the hand-built DOM")
