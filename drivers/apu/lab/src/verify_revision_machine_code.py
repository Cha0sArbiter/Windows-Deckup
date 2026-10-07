"""Run the actual AMD comparison-loop instructions in an isolated emulator."""
import hashlib
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).parent / "python-libs"))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_64
from unicorn.x86_const import UC_X86_REG_RAX, UC_X86_REG_RBX, UC_X86_REG_RDI, UC_X86_REG_RSI, UC_X86_REG_R8, UC_X86_REG_R9, UC_X86_REG_R14

original_path = Path(sys.argv[1])
patched_path = Path(sys.argv[2])
raw = original_path.read_bytes()
patched = patched_path.read_bytes()
if hashlib.sha256(raw).hexdigest() != "ae975bbb56282be1471b9a91407f0155c087b619f99d2731d4e7989720522152":
    raise SystemExit("Wrong original driver build")
if hashlib.sha256(patched).hexdigest() != "039cb63834051fe37251f7c942b3714e258e43d4347b2eac7f574543d01f7962":
    raise SystemExit("Wrong patched driver build")

def execute(binary, device, revision):
    uc = Uc(UC_ARCH_X86, UC_MODE_64)
    code_base, table_base = 0x100000, 0x200000
    uc.mem_map(code_base, 0x1000)
    uc.mem_map(table_base, 0x1000)
    uc.mem_write(code_base, binary[0x56990:0x569cb])
    # One configuration record: encoded device ID plus the ASUS revision AF.
    uc.mem_write(table_base, struct.pack("<HB", 0x163F + 12, 0xAF))
    for register, value in [(UC_X86_REG_RAX,0), (UC_X86_REG_RBX,table_base),
                            (UC_X86_REG_RDI,0xC0000001), (UC_X86_REG_RSI,device),
                            (UC_X86_REG_R8,1), (UC_X86_REG_R9,0),
                            (UC_X86_REG_R14,revision)]:
        uc.reg_write(register, value)
    uc.emu_start(code_base, code_base + 0x3b, count=100)
    return uc.reg_read(UC_X86_REG_RDI) & 0xffffffff

cases = [
    ("Original ASUS AF accepted", raw, 0x163F, 0xAF, 0),
    ("Original Deck AE rejected", raw, 0x163F, 0xAE, 0xC0000001),
    ("Patched Deck AE accepted", patched, 0x163F, 0xAE, 0),
    ("Patched ASUS AF still accepted", patched, 0x163F, 0xAF, 0),
    ("Patched lower mismatched device rejected", patched, 0x163E, 0xAE, 0xC0000001),
    ("Patched higher mismatched device rejected", patched, 0x1640, 0xAE, 0xC0000001),
]
results = []
for name, binary, device, revision, expected in cases:
    actual = execute(binary, device, revision)
    if actual != expected:
        raise SystemExit(f"FAIL: {name}: got {actual:#x}, expected {expected:#x}")
    results.append({"test": name, "status": "pass", "returned_status": hex(actual)})
Path(__file__).with_name("emulation-results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
print(json.dumps(results, indent=2))
