"""Read-only inspection of the donor's configuration and its call sites."""
import bisect
import json
from pathlib import Path
import re
import struct
import sys

sys.path.insert(0, str(Path(__file__).parent / 'python-libs'))
import capstone
import pefile

p = Path(sys.argv[1])
raw = p.read_bytes()
pe = pefile.PE(data=raw)
base = pe.OPTIONAL_HEADER.ImageBase
cs = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
functions = sorted((e.struct.BeginAddress, e.struct.EndAddress)
                   for e in pe.DIRECTORY_ENTRY_EXCEPTION)
starts = [f[0] for f in functions]

def instructions(start, length):
    offset = pe.get_offset_from_rva(start)
    return [f'{i.address-base:08x}: {i.mnemonic} {i.op_str}'
            for i in cs.disasm(raw[offset:offset+length], start+base)]

def containing(rva):
    n = bisect.bisect_right(starts, rva) - 1
    return functions[n] if n >= 0 and rva < functions[n][1] else None

strings = {}
for rva in (0x7a3640, 0x7a3658):
    offset = pe.get_offset_from_rva(rva)
    end = offset
    while raw[end:end+2] != b'\0\0' and end < offset+512:
        end += 2
    strings[hex(rva)] = raw[offset:end].decode('utf-16le', errors='replace')

targets = {0x56d40, 0x12e6370}
callers = []
for section in pe.sections:
    if not section.Characteristics & 0x20000000:
        continue
    data = section.get_data()
    for m in re.finditer(b'\xe8', data):
        pos = m.start()
        if pos + 5 > len(data):
            continue
        rva = section.VirtualAddress + pos
        target = rva + 5 + struct.unpack_from('<i', data, pos+1)[0]
        if target not in targets:
            continue
        f = containing(rva)
        start = max(f[0] if f else 0, rva-150)
        callers.append({'call_rva': hex(rva), 'target_rva': hex(target),
                        'function': [hex(x) for x in f] if f else None,
                        'instructions': instructions(start, rva-start+90)})

hash_range = containing(0x12e6370)
result = {'strings': strings, 'callers': callers,
          'hash_function': {'range': [hex(x) for x in hash_range],
                            'instructions': instructions(hash_range[0],
                                                         hash_range[1]-hash_range[0])}}
Path(__file__).with_name('signed-route-inspection.json').write_text(
    json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
