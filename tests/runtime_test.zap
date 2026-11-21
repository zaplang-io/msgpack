@test
def test_binary_runtime():
    bytes payload = bytes([196, 3]) + bytes([0, 128, 255])
    bytes expected = bytes([196, 3, 0, 128, 255])
    assert len(payload) == 5 and payload == expected
