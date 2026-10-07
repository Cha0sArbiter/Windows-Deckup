"""Compare the two private packages without changing Windows or vendor files.

The emulator covers the checksum and acceptance loop only. It does not emulate
device startup, firmware, display output, or sleep/resume.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

from build_config_candidate import DonorEmulator
import pefile

ORIGINAL = 'ae975bbb56282be1471b9a91407f0155c087b619f99d2731d4e7989720522152'
PATCHED = 'e1b4dbfb807a59971bfc90e8139e35f96b4adedfd773695dbdca5568b83d1adf'
RENAME = {'decklcd-config.inf': 'u0202038.inf', 'decklcd-config.cat': 'u0202038.cat',
          'decklcd-config-extension.inf': 'amduw23e.inf',
          'decklcd-config-extension.cat': 'amduw23e.cat'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inventory(root):
    return {RENAME.get(p.relative_to(root).as_posix(), p.relative_to(root).as_posix()): p
            for p in root.rglob('*') if p.is_file()}


def compare(prototype, candidate):
    left, right = inventory(prototype), inventory(candidate)
    changes, identical = [], 0
    for key in sorted(set(left) | set(right)):
        if key not in left or key not in right:
            changes.append({'path': key, 'missing_from': 'prototype' if key not in left else 'candidate'})
            continue
        a, b = left[key].read_bytes(), right[key].read_bytes()
        if a == b:
            identical += 1
            continue
        row = {'path': key, 'prototype_sha256': digest(a), 'candidate_sha256': digest(b),
               'prototype_size': len(a), 'candidate_size': len(b)}
        if key.endswith('.inf'):
            # Only installation catalog names are normalized, not registry data.
            normalized = b
            for old, new in RENAME.items():
                if old.endswith('.cat'):
                    normalized = normalized.replace(old.encode('ascii'), new.encode('ascii'))
            row['identical_after_catalog_name_normalization'] = a == normalized
        changes.append(row)

    a = left['B026204/amdkmdag.sys'].read_bytes()
    b = right['B026204/amdkmdag.sys'].read_bytes()
    if digest(a) != PATCHED or digest(b) != ORIGINAL:
        raise ValueError('Unexpected signed prototype or original candidate kernel.')
    pa, pb = pefile.PE(data=a, fast_load=True), pefile.PE(data=b, fast_load=True)
    sections = []
    if len(pa.sections) != len(pb.sections):
        raise ValueError('Unexpected PE section count difference.')
    for sa, sb in zip(pa.sections, pb.sections):
        if (sa.Name, sa.VirtualAddress, sa.SizeOfRawData) != (sb.Name, sb.VirtualAddress, sb.SizeOfRawData):
            raise ValueError('Unexpected PE layout difference.')
        da, db = sa.get_data(), sb.get_data()
        if len(da) != len(db):
            raise ValueError('Unexpected PE section data length difference.')
        differences = [i for i, (x, y) in enumerate(zip(da, db)) if x != y]
        sections.append({'name': sa.Name.rstrip(b'\0').decode(),
                         'executable': bool(sa.Characteristics & 0x20000000),
                         'differing_bytes': len(differences),
                         'changes': [{'rva': hex(sa.VirtualAddress+i),
                                      'prototype': hex(da[i]), 'candidate': hex(db[i])}
                                     for i in differences[:50]]})
    code_changes = [c for s in sections if s['executable'] for c in s['changes']]
    if code_changes != [{'rva': '0x56fb1', 'prototype': '0xeb', 'candidate': '0x74'}]:
        raise ValueError('Unexpected executable differences.')

    original_config = left['B026204/amdgcf.dat'].read_bytes()
    candidate_config = right['B026204/amdgcf.dat'].read_bytes()
    inf = left['u0202038.inf'].read_bytes().decode('utf-8-sig')
    release = re.search(r'^HKR,,ReleaseVersion,,"([^"]+)"', inf, re.M).group(1).encode('ascii')
    original_emu, patched_emu = DonorEmulator(b), DonorEmulator(a)
    results = []
    for label, emu, config, rev, expected in (
        ('Prototype patched code with AF config on AE Deck', patched_emu, original_config, 0xae, 0),
        ('Candidate original code with AE config on AE Deck', original_emu, candidate_config, 0xae, 0),
        ('Original code with AF config on AE Deck', original_emu, original_config, 0xae, 0xc0000001),
    ):
        status = emu.check(config, release, revision=rev)
        if status != expected:
            raise ValueError(f'Unexpected result in {label}: {status:#x}')
        results.append({'case': label, 'result': hex(status), 'expected': hex(expected)})
    return {'files_in_prototype': len(left), 'files_in_candidate': len(right),
            'identical_files': identical, 'changed_files': changes,
            'kernel_sections': sections, 'executable_byte_changes': code_changes,
            'prototype_config': original_config.hex(), 'candidate_config': candidate_config.hex(),
            'release_version': release.decode(), 'actual_code_emulation': results,
            'limitation': 'Equivalent acceptance status does not establish equivalent hardware behavior, '
                          'runtime registry values, resident image identity, or sleep/resume reliability.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prototype', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    report = compare(args.prototype, args.candidate)
    args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'kernel_sections'}, indent=2))
