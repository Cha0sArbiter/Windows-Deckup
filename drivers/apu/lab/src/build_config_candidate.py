"""Prepare and emulate a configuration-only donor candidate; install nothing.

The donor kernel stays byte-for-byte original. All executable instructions
run only inside Unicorn. A candidate is written only after the original
configuration checksum and the acceptance/rejection cases are verified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

sys.path.insert(0, str(Path(__file__).parent / 'python-libs'))
import pefile
from unicorn import Uc, UC_ARCH_X86, UC_MODE_64
from unicorn.x86_const import (
    UC_X86_REG_RAX, UC_X86_REG_RBP, UC_X86_REG_RCX, UC_X86_REG_RDI,
    UC_X86_REG_RDX, UC_X86_REG_RSI, UC_X86_REG_RSP, UC_X86_REG_R8,
    UC_X86_REG_R9, UC_X86_REG_R13, UC_X86_REG_R14, UC_X86_REG_R15,
)

EXPECTED_KERNEL = 'ae975bbb56282be1471b9a91407f0155c087b619f99d2731d4e7989720522152'
EXPECTED_INF = 'd92a955552f63d6eb38090a0cbed958fc9da0c3087ea247c881a40e4bbba3b16'
EXPECTED_CONFIG = bytes.fromhex('010000007ba5870fde8ec6144b16af')
HASH_START, HASH_END = 0x12e6370, 0x12e65c9
CHECK_START, CHECK_END = 0x56f0d, 0x56fcb


class DonorEmulator:
    def __init__(self, raw):
        self.raw = raw
        self.pe = pefile.PE(data=raw, fast_load=True)
        self.base = self.pe.OPTIONAL_HEADER.ImageBase

    def machine(self):
        uc = Uc(UC_ARCH_X86, UC_MODE_64)
        for start, end in ((HASH_START, HASH_END), (CHECK_START, CHECK_END)):
            page = start & ~0xfff
            uc.mem_map(self.base + page, 0x1000)
            offset = self.pe.get_offset_from_rva(start)
            uc.mem_write(self.base + start, self.raw[offset:offset+end-start])
        uc.mem_map(0x200000, 0x10000)
        uc.mem_map(0x300000, 0x10000)
        uc.mem_map(0x400000, 0x1000)
        uc.reg_write(UC_X86_REG_RSP, 0x307f00)
        uc.reg_write(UC_X86_REG_RBP, 0x308000)
        return uc

    def digest(self, payload):
        uc = self.machine()
        uc.mem_write(0x200000, payload)
        uc.mem_write(0x307f00, struct.pack('<Q', 0x400000))
        for reg, value in ((UC_X86_REG_RCX, 0x200000),
                           (UC_X86_REG_RDX, len(payload)),
                           (UC_X86_REG_R8, 0x208000), (UC_X86_REG_R9, 0)):
            uc.reg_write(reg, value)
        uc.emu_start(self.base + HASH_START, 0x400000, count=10000)
        return bytes(uc.mem_read(0x208000, 8))

    def check(self, config, release, device=0x163f, revision=0xae):
        uc = self.machine()
        payload = config + release
        uc.mem_write(0x200000, payload)
        for reg, value in ((UC_X86_REG_R15, 0x200000),
                           (UC_X86_REG_R13, len(payload)),
                           (UC_X86_REG_RSI, device),
                           (UC_X86_REG_R14, revision),
                           (UC_X86_REG_RDI, 0xc0000001)):
            uc.reg_write(reg, value)
        uc.emu_start(self.base + CHECK_START, self.base + CHECK_END, count=10000)
        return uc.reg_read(UC_X86_REG_RDI) & 0xffffffff


def build(kernel_path, inf_path, config_path, output):
    kernel = kernel_path.read_bytes()
    inf = inf_path.read_bytes()
    config = config_path.read_bytes()
    if hashlib.sha256(kernel).hexdigest() != EXPECTED_KERNEL:
        raise ValueError('Unexpected donor kernel; no offsets may be reused.')
    if hashlib.sha256(inf).hexdigest() != EXPECTED_INF:
        raise ValueError('Unexpected donor INF.')
    if config != EXPECTED_CONFIG:
        raise ValueError('Unexpected donor configuration.')
    text = inf.decode('utf-16') if inf[:2] in (b'\xff\xfe', b'\xfe\xff') else inf.decode('utf-8-sig')
    release = re.search(r'^HKR,,ReleaseVersion,,"([^"]+)"', text, re.M)
    if not release:
        raise ValueError('Donor ReleaseVersion is missing.')
    release_bytes = release.group(1).encode('ascii')
    emu = DonorEmulator(kernel)
    original_checksum = emu.digest(config[12:] + release_bytes)[::-1]
    if original_checksum != config[4:12]:
        raise ValueError('Actual donor checksum did not reproduce; stop.')
    candidate = bytearray(config)
    candidate[14] = 0xae
    candidate[4:12] = emu.digest(bytes(candidate[12:]) + release_bytes)[::-1]
    candidate = bytes(candidate)
    bad_checksum = bytearray(candidate)
    bad_checksum[4] ^= 1
    cases = (
        ('Original AF accepted', config, release_bytes, 0x163f, 0xaf, 0),
        ('Original AE rejected', config, release_bytes, 0x163f, 0xae, 0xc0000001),
        ('Configuration-only AE accepted', candidate, release_bytes, 0x163f, 0xae, 0),
        ('Configuration-only AF rejected', candidate, release_bytes, 0x163f, 0xaf, 0xc0000001),
        ('Different device rejected', candidate, release_bytes, 0x1640, 0xae, 0xc0000001),
        ('Corrupt checksum rejected', bytes(bad_checksum), release_bytes, 0x163f, 0xae, 0xc0000001),
        ('Different ReleaseVersion rejected', candidate, release_bytes+b'X', 0x163f, 0xae, 0xc0000001),
    )
    results = []
    for label, data, version, device, revision, expected in cases:
        actual = emu.check(data, version, device, revision)
        if actual != expected:
            raise ValueError(f'{label}: got {actual:#x}, expected {expected:#x}')
        results.append({'case': label, 'result': hex(actual), 'status': 'pass'})
    output.mkdir(parents=True, exist_ok=True)
    (output / 'amdgcf.dat').write_bytes(candidate)
    report = {
        'status': 'OfflineCandidateVerified',
        'kernel_sha256': hashlib.sha256(kernel).hexdigest(),
        'kernel_modified': False,
        'release_version': release.group(1),
        'original_configuration_hex': config.hex(),
        'candidate_configuration_hex': candidate.hex(),
        'candidate_sha256': hashlib.sha256(candidate).hexdigest(),
        'checks': results,
        'live_driver_changed': False,
        'normal_boot_verified': False,
        'installation_catalog_still_valid_for_modified_configuration': False,
        'limitation': 'A configuration candidate is not a signed replacement package. Normal Windows loading and hardware operation require a separate controlled trial.',
    }
    (output / 'candidate-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kernel', type=Path)
    parser.add_argument('inf', type=Path)
    parser.add_argument('configuration', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.kernel, args.inf, args.configuration, args.output), indent=2))
