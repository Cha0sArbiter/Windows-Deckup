import hashlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "src"))
from build_package import add_hardware_id, child_path, patch_kernel


class PatchSafetyTests(unittest.TestCase):
    def setUp(self):
        self.data = bytes.fromhex("90 3b d6 75 0b 0f b6 4b 02 41 3b ce 74 15 3b d6 90")
        self.manifest = {
            "kernel_sha256": hashlib.sha256(self.data).hexdigest(),
            "patch": {"offset": 12, "expected": "74", "replacement": "eb",
                      "context_offset": 1, "context": self.data[1:16].hex()},
        }

    def test_changes_only_the_revision_branch(self):
        patched = patch_kernel(self.data, self.manifest)
        self.assertEqual(len(patched), len(self.data))
        self.assertEqual([i for i, pair in enumerate(zip(self.data, patched)) if pair[0] != pair[1]], [12])
        self.assertEqual(patched[12:14], b"\xeb\x15")

    def test_rejects_unknown_build(self):
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            patch_kernel(self.data + b"\x00", self.manifest)

    def test_rejects_unexpected_instruction_even_with_matching_hash(self):
        modified = self.data[:12] + b"\x75" + self.data[13:]
        self.manifest["kernel_sha256"] = hashlib.sha256(modified).hexdigest()
        with self.assertRaisesRegex(ValueError, "context"):
            patch_kernel(modified, self.manifest)

    def test_rejects_out_of_range_and_size_changes(self):
        self.manifest["patch"]["offset"] = 100
        with self.assertRaisesRegex(ValueError, "outside"):
            patch_kernel(self.data, self.manifest)
        self.manifest["patch"]["offset"] = 12
        self.manifest["patch"]["replacement"] = "eb1590"
        with self.assertRaisesRegex(ValueError, "size"):
            patch_kernel(self.data, self.manifest)

    def test_rejects_manifest_path_escape(self):
        with self.assertRaisesRegex(ValueError, "escapes"):
            child_path(Path(__file__).parent, "../../escaped.sys")

    def test_adds_model_only_to_specified_section(self):
        inf = b"[Models]\r\noriginal=model, HW\r\n[Other]\r\nkeep=yes\r\n[Strings]\r\nold=Original\r\n"
        spec = {"sha256": hashlib.sha256(inf).hexdigest(), "model_section": "Models", "path": "example.inf"}
        result = add_hardware_id(inf, spec, "PCI\\VEN_1002&DEV_163F&REV_AE")
        self.assertIn(b"[Other]\r\nkeep=yes\r\n", result)
        self.assertEqual(result.count(b"ati2mtag_VanGogh"), 1)
        self.assertIn(b'AMD163F.DeckLCD = "AMD Radeon(TM) Graphics"', result)


if __name__ == "__main__":
    unittest.main()
