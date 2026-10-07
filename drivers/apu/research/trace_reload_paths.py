"""Read-only, exact-build helpers for the reload-error investigation."""
import bisect
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
sys.path.insert(0, str(Path(__file__).parent / 'python-libs'))
import capstone
import pefile

raw = Path(sys.argv[1]).read_bytes()
assert hashlib.sha256(raw).hexdigest() == 'ae975bbb56282be1471b9a91407f0155c087b619f99d2731d4e7989720522152'
pe = pefile.PE(data=raw, fast_load=True)
pe.parse_data_directories(directories=[1, 3])
base = pe.OPTIONAL_HEADER.ImageBase
cs = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
cs.detail = True
entries = sorted(pe.DIRECTORY_ENTRY_EXCEPTION, key=lambda e: e.struct.BeginAddress)
starts = [e.struct.BeginAddress for e in entries]
imports = {i.address-base: (d.dll.decode()+'!'+(i.name.decode() if i.name else str(i.ordinal)))
           for d in pe.DIRECTORY_ENTRY_IMPORT for i in d.imports}

def enclosing(rva):
    n = bisect.bisect_right(starts, rva)-1
    return entries[n] if n >= 0 and rva < entries[n].struct.EndAddress else None

def decode(rva, size):
    pos = pe.get_offset_from_rva(rva)
    out = []
    for i in cs.disasm(raw[pos:pos+size], base+rva):
        notes = []
        for op in i.operands:
            if op.type == capstone.x86.X86_OP_MEM and op.mem.base == capstone.x86.X86_REG_RIP:
                dest = i.address+i.size+op.mem.disp-base
                if dest in imports:
                    notes.append(imports[dest])
                else:
                    try:
                        p = pe.get_offset_from_rva(dest)
                        s = raw[p:p+220].split(b'\0', 1)[0]
                        if len(s) >= 5 and all(32 <= b <= 126 for b in s):
                            notes.append(s.decode())
                    except Exception:
                        pass
                notes.append('rip-target='+hex(dest))
        out.append({'rva': hex(i.address-base), 'bytes': i.bytes.hex(),
                    'mnemonic': i.mnemonic, 'operands': i.op_str, 'notes': notes})
    return out

def function(rva):
    e = enclosing(rva)
    if not e:
        return {'rva': hex(rva), 'instructions': decode(rva, 160)}
    unwind = pe.get_offset_from_rva(e.struct.UnwindData)
    flags = raw[unwind] >> 3
    count = raw[unwind+2]
    trailer = unwind+4+((count+1)&~1)*2
    chain = [hex(v) for v in struct.unpack_from('<III', raw, trailer)] if flags & 4 else None
    return {'range': [hex(e.struct.BeginAddress), hex(e.struct.EndAddress)],
            'unwind_flags': flags, 'chain': chain,
            'instructions': decode(e.struct.BeginAddress, e.struct.EndAddress-e.struct.BeginAddress)}

targets = {int(s, 0) for s in sys.argv[3:]}
refs = []
for s in pe.sections:
    data = s.get_data()
    if s.Characteristics & 0x20000000:
        for m in re.finditer(rb'\xe8|[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]', data):
            p = m.start()
            rva = s.VirtualAddress+p
            size = 5 if data[p] == 0xe8 else 7
            if p+size > len(data):
                continue
            dest = rva+size+struct.unpack_from('<i', data, p+size-4)[0]
            if dest not in targets:
                continue
            f = function(rva)
            # Confirm the match occurs at a decoded instruction boundary.
            if not any(int(i['rva'],16) == rva for i in f['instructions']):
                continue
            window = [i for i in f['instructions'] if rva-100 <= int(i['rva'],16) <= rva+80]
            refs.append({'type': 'call' if size == 5 else 'lea', 'target': hex(dest),
                         'rva': hex(rva), 'function': f.get('range'), 'window': window})
    for target in targets:
        for m in re.finditer(re.escape(struct.pack('<Q', base+target)), data):
            refs.append({'type': 'pointer', 'target': hex(target), 'rva': hex(s.VirtualAddress+m.start())})
out = {'functions': {hex(t): function(t) for t in sorted(targets)}, 'references': refs}
Path(sys.argv[2]).write_text(json.dumps(out, indent=2), encoding='utf-8')
print(json.dumps({'functions': {k: {a:b for a,b in v.items() if a != 'instructions'} for k,v in out['functions'].items()},
                  'references': [{k:v for k,v in r.items() if k != 'window'} for r in refs]}, indent=2))
