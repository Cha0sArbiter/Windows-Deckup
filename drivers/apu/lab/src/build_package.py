"""Build a version-pinned local AMD driver experiment; never install it."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


def digest(data):
    return hashlib.sha256(data).hexdigest()


def patch_kernel(data, manifest):
    if digest(data) != manifest["kernel_sha256"].lower():
        raise ValueError("Unrecognized kernel SHA-256; no patch applied")
    patch = manifest["patch"]
    offset = patch["offset"]
    expected = bytes.fromhex(patch["expected"])
    replacement = bytes.fromhex(patch["replacement"])
    context_offset = patch["context_offset"]
    context = bytes.fromhex(patch["context"])
    if len(expected) != len(replacement) or not expected:
        raise ValueError("Patch must preserve binary size")
    if offset < 0 or offset + len(expected) > len(data):
        raise ValueError("Patch offset is outside the kernel")
    if not (context_offset <= offset < context_offset + len(context)):
        raise ValueError("Patch is outside its verified instruction context")
    if data[context_offset:context_offset + len(context)] != context:
        raise ValueError("Instruction context differs; no patch applied")
    if data[offset:offset + len(expected)] != expected:
        raise ValueError("Original instruction differs; no patch applied")
    return data[:offset] + replacement + data[offset + len(expected):]


def add_hardware_id(data, spec, hardware_id):
    if digest(data) != spec["sha256"].lower():
        raise ValueError(f"Unrecognized INF SHA-256: {spec['path']}")
    text = data.decode("ascii")
    if hardware_id in text:
        raise ValueError("Deck hardware ID already exists; refusing a second adaptation")
    section = f"[{spec['model_section']}]"
    if text.count(section) != 1 or text.count("[Strings]") != 1:
        raise ValueError("Unexpected INF section structure")
    newline = "\r\n" if "\r\n" in text else "\n"
    model = f'"%AMD163F.DeckLCD%" = ati2mtag_VanGogh, {hardware_id}'
    text = text.replace(section + newline, section + newline + model + newline, 1)
    text = text.replace("[Strings]" + newline,
                        "[Strings]" + newline + 'AMD163F.DeckLCD = "AMD Radeon(TM) Graphics"' + newline, 1)
    if text.count(model) != 1:
        raise ValueError("Hardware-ID insertion failed")
    return text.encode("ascii")


def child_path(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("Manifest path escapes package directory")
    return path


def build(source, destination, manifest_path):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if destination.exists() or destination.is_relative_to(source) or source.is_relative_to(destination):
        raise ValueError("Output must be a new directory outside the source tree")
    manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    kernel_source = child_path(source, manifest["kernel"])
    original_kernel = kernel_source.read_bytes()
    new_kernel = patch_kernel(original_kernel, manifest)
    infs = [(spec, add_hardware_id(child_path(source, spec["path"]).read_bytes(), spec,
                                   manifest["hardware_id"])) for spec in manifest["infs"]]
    shutil.copytree(source, destination)
    child_path(destination, manifest["kernel"]).write_bytes(new_kernel)
    for spec, data in infs:
        child_path(destination, spec["path"]).write_bytes(data)
    changed = [index for index, (old, new) in enumerate(zip(original_kernel, new_kernel)) if old != new]
    report = {
        "driver_version": manifest["driver_version"], "hardware_id": manifest["hardware_id"],
        "original_kernel_sha256": digest(original_kernel), "patched_unsigned_kernel_sha256": digest(new_kernel),
        "changed_kernel_offsets": changed, "patch_purpose": manifest["patch"]["purpose"],
        "modified_infs": [spec["path"] for spec, data in infs],
        "source": str(source), "destination": str(destination),
        "signing_required": True, "installed": False,
    }
    (destination.parent / "build-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    build(args.source, args.output, args.manifest)
