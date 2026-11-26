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

struct SerdeOpt:
    int64 id
    Optional[int64] maybe
    Optional[str] note

@test
def test_optional_some_and_none_round_trip():
    auto r = SerdeOpt(1, Optional.Some(9), Optional.None)
    auto r2 = unpack[SerdeOpt](pack(r))
    _ok(r2.id == 1, "id")
    bool some_ok = False
    match r2.maybe:
        case Optional.Some(x):
            some_ok = x == 9
        case Optional.None:
            some_ok = False
    _ok(some_ok, "Optional[int64] Some round-trip")
    bool none_ok = False
    match r2.note:
        case Optional.Some(y):
            none_ok = False
        case Optional.None:
            none_ok = True
    _ok(none_ok, "Optional[str] None round-trip")

@test
def test_optional_both_some_round_trip():
    # Two adjacent Some values: the key-skip suppression must reset after each,
    # so the second Optional's key is still consumed correctly.
    auto r = SerdeOpt(3, Optional.Some(-5), Optional.Some("hi"))
    auto r2 = unpack[SerdeOpt](pack(r))
    _ok(r2.id == 3, "id")
    bool a_ok = False
    match r2.maybe:
        case Optional.Some(x):
            a_ok = x == -5
        case Optional.None:
            a_ok = False
    _ok(a_ok, "first Optional Some")
    bool b_ok = False
    match r2.note:
        case Optional.Some(y):
            b_ok = y == "hi"
        case Optional.None:
            b_ok = False
    _ok(b_ok, "second Optional Some (suppression reset)")

@test
def test_optional_matches_the_dom():
    auto r = SerdeOpt(1, Optional.Some(9), Optional.None)
    auto dom = Value.Map([
        (Value.Str("id"), Value.Int(1)),
        (Value.Str("maybe"), Value.Int(9)),
        (Value.Str("note"), Value.Nil),
    ])
    _ok(pack(r) == packb(dom), "Optional Some=inner / None=nil packs byte-identical to the DOM")

enum SerdeStatus:
    Active
    Paused
    Done

@test
def test_enum_constant_variant_round_trips():
    auto s = unpack[SerdeStatus](pack(SerdeStatus.Paused))
    bool is_paused = False
    match s:
        case SerdeStatus.Active:
            is_paused = False
        case SerdeStatus.Paused:
            is_paused = True
        case SerdeStatus.Done:
            is_paused = False
    _ok(is_paused, "enum constant variant round-trip")

@test
def test_enum_round_trips_every_variant():
    auto a = unpack[SerdeStatus](pack(SerdeStatus.Active))
    bool a_ok = False
    match a:
        case SerdeStatus.Active:
            a_ok = True
        case SerdeStatus.Paused:
            a_ok = False
        case SerdeStatus.Done:
            a_ok = False
    _ok(a_ok, "Active round-trip")
    auto d = unpack[SerdeStatus](pack(SerdeStatus.Done))
    bool d_ok = False
    match d:
        case SerdeStatus.Active:
            d_ok = False
        case SerdeStatus.Paused:
            d_ok = False
        case SerdeStatus.Done:
            d_ok = True
    _ok(d_ok, "Done round-trip")

@test
def test_enum_encodes_as_its_variant_name_string():
    _ok(pack(SerdeStatus.Paused) == packb(Value.Str("Paused")), "enum encodes as a MessagePack string of the variant name")

@test
def test_unpack_rejects_an_unknown_variant_tag():
    bool raised = False
    try:
        auto _s = unpack[SerdeStatus](packb(Value.Str("Nope")))
    except ValueError:
        raised = True
    _ok(raised, "an unknown enum variant tag raises ValueError")
