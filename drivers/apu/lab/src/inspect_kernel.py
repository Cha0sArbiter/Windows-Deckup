"""Read-only PE inspection for AMD driver compatibility research."""
import argparse
import bisect
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

sys.path.insert(0, str(Path(__file__).parent / "python-libs"))
import capstone
import pefile


def inspect(path):
    raw = Path(path).read_bytes()
    pe = pefile.PE(data=raw)
    base = pe.OPTIONAL_HEADER.ImageBase
    engine = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    engine.detail = True
    functions = sorted(
        (entry.struct.BeginAddress, entry.struct.EndAddress)
        for entry in pe.DIRECTORY_ENTRY_EXCEPTION
    )
    starts = [f[0] for f in functions]

    def containing(rva):
        i = bisect.bisect_right(starts, rva) - 1
        return functions[i] if i >= 0 and rva < functions[i][1] else None

    def disassemble(rva, length):
        offset = pe.get_offset_from_rva(rva)
        return [
            f"{ins.address-base:08x}: {ins.bytes.hex(' '):<38} {ins.mnemonic} {ins.op_str}"
            for ins in engine.disasm(raw[offset:offset + length], base + rva)
        ]

    needles = [b"AMDGCF verification", b"amdgcf.dat", "amdgcf.dat".encode("utf-16le")]
    targets = []
    for needle in needles:
        for match in re.finditer(re.escape(needle), raw):
            offset = match.start()
            targets.append({"needle": needle.decode("ascii", errors="replace"),
                            "offset": offset, "rva": pe.get_rva_from_offset(offset)})

    references = []
    target_rvas = {target["rva"] for target in targets}
    for section in pe.sections:
        if not section.Characteristics & 0x20000000:
            continue
        data = section.get_data()
        # RIP-relative LEA instructions used to reference diagnostic strings.
        for match in re.finditer(rb"[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]", data):
            pos = match.start()
            if pos + 7 > len(data):
                continue
            rva = section.VirtualAddress + pos
            destination = rva + 7 + struct.unpack_from("<i", data, pos + 3)[0]
            if destination in target_rvas:
                function = containing(rva)
                references.append({"instruction_rva": rva, "target_rva": destination,
                                   "function": function,
                                   "disassembly": disassemble(function[0], min(function[1]-function[0], 4096)) if function else disassemble(rva, 96)})

    legacy_offset = 0x56550
    legacy_rva = pe.get_rva_from_offset(legacy_offset)
    result = {
        "path": str(Path(path).resolve()), "sha256": hashlib.sha256(raw).hexdigest(),
        "size": len(raw), "image_base": base, "targets": targets,
        "legacy_patch_location": {"offset": legacy_offset, "rva": legacy_rva,
                                  "bytes": raw[legacy_offset:legacy_offset+32].hex(' '),
                                  "containing_function": containing(legacy_rva),
                                  "disassembly": disassemble(legacy_rva, 128)},
        "references": references,
    }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("kernel")
    parser.add_argument("output")
    args = parser.parse_args()
    result = inspect(args.kernel)
    Path(args.output).write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "references"}, indent=2))
    print(f"Found {len(result['references'])} string references; full analysis saved to {args.output}")
