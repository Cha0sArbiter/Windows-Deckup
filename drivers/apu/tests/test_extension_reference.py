from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from adapt_extension_reference import adapt


class ExtensionReferenceTests(unittest.TestCase):
    def test_preserves_other_copy_targets_and_line_endings(self):
        original = b'[Install]\r\nCopyINF = .\\amdfendr\\amdfendr.inf\r\nCopyINF=amduw23e.inf\r\nNext=value\r\n'
        self.assertEqual(adapt(original), original.replace(b'CopyINF=amduw23e.inf', b'CopyINF=decklcd-config-extension.inf'))

    def test_refuses_missing_or_duplicate_reference(self):
        for data in (b'[Install]\r\n', b'CopyINF=amduw23e.inf\nCopyINF=amduw23e.inf\n'):
            with self.assertRaises(ValueError):
                adapt(data)


if __name__ == '__main__':
    unittest.main()
