import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent / "python-libs"))
import capstone
import pefile

path, start, length = sys.argv[1], int(sys.argv[2], 0), int(sys.argv[3], 0)
raw = Path(path).read_bytes()
pe = pefile.PE(data=raw, fast_load=True)
offset = pe.get_offset_from_rva(start)
base = pe.OPTIONAL_HEADER.ImageBase
engine = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
for ins in engine.disasm(raw[offset:offset+length], start + base):
    print(f"RVA {ins.address-base:08x} FILE {pe.get_offset_from_rva(ins.address-base):08x}  {ins.bytes.hex(' '):<38} {ins.mnemonic} {ins.op_str}")
