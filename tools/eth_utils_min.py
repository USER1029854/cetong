"""Minimal pure-Python keccak-256 + EIP-55 checksum. No external deps."""

_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
_ROT = [
    [0, 36, 3, 41, 18],
    [1, 44, 10, 45, 2],
    [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56],
    [27, 20, 39, 8, 14],
]
_MASK = (1 << 64) - 1

def _rol(x, n):
    return ((x << n) | (x >> (64 - n))) & _MASK

def _keccak_f(state):
    A = [[state[x + 5 * y] for y in range(5)] for x in range(5)]
    for rnd in range(24):
        C = [A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4] for x in range(5)]
        D = [C[(x - 1) % 5] ^ _rol(C[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                A[x][y] ^= D[x]
        B = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                B[y][(2 * x + 3 * y) % 5] = _rol(A[x][y], _ROT[x][y])
        for x in range(5):
            for y in range(5):
                A[x][y] = B[x][y] ^ ((~B[(x + 1) % 5][y]) & B[(x + 2) % 5][y])
        A[0][0] ^= _RC[rnd]
    for x in range(5):
        for y in range(5):
            state[x + 5 * y] = A[x][y]

def keccak(data: bytes) -> bytes:
    rate = 136  # 1088 bits for keccak-256
    state = [0] * 25
    # absorb
    msg = bytearray(data)
    msg.append(0x01)  # keccak padding (NOT 0x06)
    while len(msg) % rate != 0:
        msg.append(0x00)
    msg[-1] ^= 0x80
    for off in range(0, len(msg), rate):
        block = msg[off:off + rate]
        for i in range(rate // 8):
            state[i] ^= int.from_bytes(block[i * 8:i * 8 + 8], "little")
        _keccak_f(state)
    # squeeze (32 bytes fits in first block)
    out = b"".join(state[i].to_bytes(8, "little") for i in range(rate // 8))
    return out[:32]

def to_checksum(addr: str) -> str:
    addr = addr.lower().replace("0x", "")
    h = keccak(addr.encode()).hex()
    out = "0x"
    for i, c in enumerate(addr):
        if c in "0123456789":
            out += c
        else:
            out += c.upper() if int(h[i], 16) >= 8 else c
    return out

# storage slot for mapping(key => value) at base slot p: keccak(pad(key) . pad(p))
def map_slot(key_hex, base_slot):
    k = key_hex.lower().replace("0x", "").rjust(64, "0")
    p = hex(base_slot)[2:].rjust(64, "0")
    return "0x" + keccak(bytes.fromhex(k + p)).hex()

if __name__ == "__main__":
    # Known-answer tests
    assert keccak(b"").hex() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470", keccak(b"").hex()
    assert keccak(b"transfer(address,uint256)").hex()[:8] == "a9059cbb", keccak(b"transfer(address,uint256)").hex()[:8]
    assert keccak(b"balanceOf(address)").hex()[:8] == "70a08231"
    assert to_checksum("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed") == "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    print("eth_utils_min self-test PASSED")
