def main():
    bytes payload = bytes([196, 3]) + bytes([0, 128, 255])
    bytes expected = bytes([196, 3, 0, 128, 255])
    if len(payload) != 5 or payload != expected:
        raise ValueError("byte construction changed the binary payload")
    print("Zap binary runtime smoke test: PASS")
