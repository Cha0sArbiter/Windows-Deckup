"""Run a tiny offscreen hardware GPU clear/copy/readback check on Windows.

Uses D3D_DRIVER_TYPE_HARDWARE only, without a software fallback. This is a
basic functional check, not a game benchmark or a comprehensive driver test.
COM method positions follow Microsoft's published d3d11.h interface ABI.
No administrator rights or display/power configuration changes are required.
"""

import argparse
import ctypes as ct
import json
import sys
import uuid
from datetime import datetime
from pathlib import Path


U32 = ct.c_uint32
HRESULT = ct.c_int32
PTR = ct.c_void_p


class SampleDescription(ct.Structure):
    _fields_ = [("count", U32), ("quality", U32)]


class TextureDescription(ct.Structure):
    _fields_ = [
        ("width", U32), ("height", U32), ("mip_levels", U32),
        ("array_size", U32), ("format", U32),
        ("sample", SampleDescription), ("usage", U32),
        ("bind_flags", U32), ("cpu_access_flags", U32),
        ("misc_flags", U32),
    ]


class MappedResource(ct.Structure):
    _fields_ = [("data", PTR), ("row_pitch", U32), ("depth_pitch", U32)]


class Guid(ct.Structure):
    _fields_ = [("data1", U32), ("data2", ct.c_uint16),
                ("data3", ct.c_uint16), ("data4", ct.c_ubyte * 8)]


class AdapterDescription(ct.Structure):
    _fields_ = [
        ("description", ct.c_wchar * 128), ("vendor_id", U32),
        ("device_id", U32), ("subsystem_id", U32), ("revision", U32),
        ("dedicated_video_memory", ct.c_size_t),
        ("dedicated_system_memory", ct.c_size_t),
        ("shared_system_memory", ct.c_size_t),
        ("luid_low", U32), ("luid_high", ct.c_int32),
    ]


def check_hr(result, operation):
    if result < 0:
        raise RuntimeError(f"{operation}: HRESULT 0x{result & 0xFFFFFFFF:08X}")


def com_method(instance, index, result_type, *argument_types):
    table = ct.cast(instance, ct.POINTER(ct.POINTER(PTR))).contents
    return ct.WINFUNCTYPE(result_type, PTR, *argument_types)(table[index])


def run_probe():
    if sys.platform != "win32":
        raise RuntimeError("This check requires Windows.")
    if ct.sizeof(TextureDescription) != 44:
        raise RuntimeError("Unexpected Direct3D structure layout.")
    if ct.sizeof(PTR) != 8 or ct.sizeof(AdapterDescription) != 304:
        raise RuntimeError("Unexpected 64-bit DXGI adapter structure layout.")

    d3d = ct.WinDLL("d3d11.dll")
    create_device = d3d.D3D11CreateDevice
    create_device.restype = HRESULT
    create_device.argtypes = [
        PTR, U32, PTR, U32, ct.POINTER(U32), U32, U32,
        ct.POINTER(PTR), ct.POINTER(U32), ct.POINTER(PTR),
    ]
    levels = (U32 * 2)(0xB100, 0xB000)  # 11_1 and 11_0
    device, context, feature_level = PTR(), PTR(), U32()
    owned = []
    try:
        result = create_device(
            None, 1, None, 0, levels, len(levels), 7,
            ct.byref(device), ct.byref(feature_level), ct.byref(context),
        )
        for pointer in (device, context):
            if pointer.value:
                owned.append(pointer)
        check_hr(result, "D3D11CreateDevice(HARDWARE)")

        # Identify the actual adapter used by this device, rather than infer
        # hardware identity from a separate Plug and Play snapshot.
        iid = Guid.from_buffer_copy(uuid.UUID(
            "54ec77fa-1377-44e6-8c32-88fd5f44c84c").bytes_le)
        dxgi_device = PTR()
        query_interface = com_method(device, 0, HRESULT,
                                     ct.POINTER(Guid), ct.POINTER(PTR))
        check_hr(query_interface(device, ct.byref(iid), ct.byref(dxgi_device)),
                 "QueryInterface(IDXGIDevice)")
        owned.append(dxgi_device)
        adapter = PTR()
        get_adapter = com_method(dxgi_device, 7, HRESULT, ct.POINTER(PTR))
        check_hr(get_adapter(dxgi_device, ct.byref(adapter)), "IDXGIDevice.GetAdapter")
        owned.append(adapter)
        description = AdapterDescription()
        get_description = com_method(adapter, 8, HRESULT,
                                     ct.POINTER(AdapterDescription))
        check_hr(get_description(adapter, ct.byref(description)), "IDXGIAdapter.GetDesc")
        adapter_identity = {
            "description": description.description,
            "vendor_id": f"0x{description.vendor_id:04X}",
            "device_id": f"0x{description.device_id:04X}",
            "subsystem_id": f"0x{description.subsystem_id:08X}",
            "revision": f"0x{description.revision:02X}",
            "luid": f"{description.luid_high & 0xFFFFFFFF:08X}:{description.luid_low:08X}",
        }

        width = height = 32
        texture_description = TextureDescription(
            width, height, 1, 1, 28, SampleDescription(1, 0), 0, 0x20, 0, 0,
        )
        create_texture = com_method(
            device, 5, HRESULT, ct.POINTER(TextureDescription), PTR,
            ct.POINTER(PTR),
        )
        render_texture = PTR()
        check_hr(create_texture(device, ct.byref(texture_description), None,
                                ct.byref(render_texture)), "CreateTexture2D(render)")
        owned.append(render_texture)

        staging_description = TextureDescription(
            width, height, 1, 1, 28, SampleDescription(1, 0), 3, 0, 0x20000, 0,
        )
        staging_texture = PTR()
        check_hr(create_texture(device, ct.byref(staging_description), None,
                                ct.byref(staging_texture)), "CreateTexture2D(staging)")
        owned.append(staging_texture)

        render_view = PTR()
        create_view = com_method(device, 9, HRESULT, PTR, PTR, ct.POINTER(PTR))
        check_hr(create_view(device, render_texture, None, ct.byref(render_view)),
                 "CreateRenderTargetView")
        owned.append(render_view)

        clear = com_method(context, 50, None, PTR, ct.POINTER(ct.c_float))
        copy = com_method(context, 47, None, PTR, PTR)
        map_resource = com_method(context, 14, HRESULT, PTR, U32, U32, U32,
                                  ct.POINTER(MappedResource))
        unmap = com_method(context, 15, None, PTR, U32)
        cases = []
        for name, channels in (
            ("red", (1, 0, 0, 1)),
            ("green", (0, 1, 0, 1)),
            ("blue", (0, 0, 1, 1)),
        ):
            color = (ct.c_float * 4)(*channels)
            clear(context, render_view, color)
            copy(context, staging_texture, render_texture)
            mapped = MappedResource()
            check_hr(map_resource(context, staging_texture, 0, 1, 0,
                                  ct.byref(mapped)), "Map(readback)")
            try:
                if not mapped.data or mapped.row_pitch < width * 4:
                    raise RuntimeError("Invalid mapped texture data.")
                expected_row = bytes(channel * 255 for channel in channels) * width
                for row in range(height):
                    pixels = ct.string_at(mapped.data + row * mapped.row_pitch,
                                          width * 4)
                    if pixels != expected_row:
                        raise RuntimeError(f"GPU readback mismatch: {name}, row {row}")
            finally:
                unmap(context, staging_texture, 0)
            cases.append({"color": name, "pixels_verified": width * height,
                          "passed": True})

        check_hr(com_method(device, 39, HRESULT)(device), "GetDeviceRemovedReason")
        return {
            "passed": True,
            "driver_type": "HARDWARE",
            "software_fallback": False,
            "adapter": adapter_identity,
            "feature_level": {0xB100: "11_1", 0xB000: "11_0"}[feature_level.value],
            "texture_size": [width, height],
            "cases": cases,
            "limitation": "Covers basic GPU clear/copy/readback only; this probe does not assess game stability, video, or sleep/wake.",
        }
    finally:
        for pointer in reversed(owned):
            com_method(pointer, 2, U32)(pointer)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = run_probe()
    except Exception as error:
        report = {"passed": False, "error": str(error)}
    report["captured_at"] = datetime.now().astimezone().isoformat()
    encoded = json.dumps(report, indent=2)
    if args.output:
        args.output.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
