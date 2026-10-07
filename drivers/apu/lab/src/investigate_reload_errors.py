"""Inspect vendor code and diagnostics without installing or editing a driver."""
import argparse
import bisect
import hashlib
import json
from pathlib import Path
import re
import struct

import capstone
from capstone.x86_const import X86_OP_IMM, X86_OP_MEM, X86_REG_RIP
import pefile

EXPECTED = 'ae975bbb56282be1471b9a91407f0155c087b619f99d2731d4e7989720522152'
NEEDLES = (
    b'Failed to release hardware access during uninitialization',
    b'Create SOC Service Manager failed',
    b'AMDGCF verification',
)


def inspect(path):
    raw = Path(path).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED:
        raise ValueError('This analysis requires the exact verified ASUS donor kernel.')
    pe = pefile.PE(data=raw, fast_load=True)
    pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXCEPTION'],
                                           pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_IMPORT']])
    base = pe.OPTIONAL_HEADER.ImageBase
    functions = sorted((e.struct.BeginAddress, e.struct.EndAddress)
                       for e in pe.DIRECTORY_ENTRY_EXCEPTION)
    starts = [f[0] for f in functions]
    engine = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    engine.detail = True

    def containing(rva):
        index = bisect.bisect_right(starts, rva)-1
        return functions[index] if index >= 0 and rva < functions[index][1] else None

    def instructions(rva, size):
        offset = pe.get_offset_from_rva(rva)
        return list(engine.disasm(raw[offset:offset+size], base+rva))

    def instruction_json(ins):
        return {'rva': hex(ins.address-base), 'bytes': ins.bytes.hex(),
                'mnemonic': ins.mnemonic, 'operands': ins.op_str}

    targets = []
    for needle in NEEDLES:
        for match in re.finditer(re.escape(needle), raw):
            offset = match.start()
            start = raw.rfind(b'\0', max(0, offset-256), offset)+1
            end = raw.find(b'\0', offset)
            if end < 0 or end-start > 512:
                continue
            text = raw[start:end].decode('ascii', errors='replace')
            targets.append({'needle': needle.decode(), 'text': text,
                            'offset': hex(start), 'rva': hex(pe.get_rva_from_offset(start))})
    target_rvas = {int(t['rva'], 16) for t in targets}
    references = []
    executable_sections = [s for s in pe.sections if s.Characteristics & 0x20000000]
    for section in executable_sections:
        data = section.get_data()
        for match in re.finditer(rb'[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]', data):
            pos = match.start()
            if pos+7 > len(data):
                continue
            rva = section.VirtualAddress+pos
            destination = rva+7+struct.unpack_from('<i', data, pos+3)[0]
            if destination not in target_rvas:
                continue
            function = containing(rva)
            block = instructions(function[0], function[1]-function[0]) if function else instructions(rva, 160)
            references.append({'instruction_rva': hex(rva), 'string_rva': hex(destination),
                               'function': [hex(v) for v in function] if function else None,
                               'instructions': [instruction_json(i) for i in block]})
    imports = {}
    for library in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', []):
        for entry in library.imports:
            imports[hex(entry.address-base)] = library.dll.decode(errors='replace')+'!'+(
                entry.name.decode(errors='replace') if entry.name else f'ordinal{entry.ordinal}')
    related = []
    for match in re.finditer(rb'[\x20-\x7e]{12,220}\x00', raw):
        text = match.group()[:-1].decode('ascii')
        if re.search(r'(hardware access|SOC Service|AMDGCF|POST display|display ownership)', text, re.I):
            related.append({'rva': hex(pe.get_rva_from_offset(match.start())), 'text': text})
    # Verified whole logical functions can span several exception-table ranges.
    # These ranges belong only to the exact pinned donor build above.
    trace_ranges = {
        'SOC factory virtual method': (0x4a000, 0x4a01f),
        'SOC object construction and initialization': (0x111d10, 0x111fb1),
        'SOC initialize method': (0x1120b0, 0x1121e3),
        'SOC hardware-services initialization': (0x1126d0, 0x112e1c),
        'TTL initialize including failure cleanup': (0x4663d4, 0x4667db),
        'BGM hardware initialization and cleanup': (0x48edf0, 0x48f625),
        'Hardware-manager destructor wrapper': (0x494d5c, 0x494d7a),
        'Release hardware access during uninitialization': (0x4952dc, 0x495327),
        'AMDGCF accepted and rejected branches and cleanup': (0x56f0d, 0x5701d),
    }
    traces = {name: {'range': [hex(start), hex(end)],
                     'instructions': [instruction_json(i) for i in instructions(start, end-start)]}
              for name, (start, end) in trace_ranges.items()}
    factory_slot = struct.unpack_from('<Q', raw, pe.get_offset_from_rva(0x7a1678+0x310))[0]-base
    if factory_slot != 0x4a000:
        raise ValueError('The traced SOC factory vtable slot changed.')
    return {'kernel': str(Path(path).resolve()), 'sha256': digest, 'base': hex(base),
            'targets': targets, 'references': references, 'imports': imports,
            'related_diagnostics': related, 'traced_error_paths': traces,
            'soc_factory_vtable_slot': {'rva': '0x7a1988', 'target': hex(factory_slot)},
            'limitation': 'Static analysis identifies failure conditions and possible cleanup paths; '
                          'it does not reveal the runtime callback address, callback return code, '
                          'resident kernel image, or failed display-resume stage.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('kernel')
    parser.add_argument('output')
    args = parser.parse_args()
    report = inspect(args.kernel)
    Path(args.output).write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: report[k] for k in ('sha256', 'targets', 'related_diagnostics')}, indent=2))
    print(f"Located {len(report['references'])} diagnostic references; disassembly is saved separately.")
