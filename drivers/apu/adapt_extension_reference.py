"""Resolve CopyINF to the renamed extension in a newly prepared bundle."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def adapt(data):
    result, count = re.subn(
        rb'(?im)^(CopyINF[ \t]*=[ \t]*)amduw23e\.inf([ \t]*\r?)$',
        rb'\1decklcd-config-extension.inf\2', data,
    )
    if count != 1:
        raise ValueError('Expected one exact donor extension CopyINF reference.')
    return result


def update(directory):
    report_path = directory / 'package-report.json'
    report = json.loads(report_path.read_text(encoding='utf-8'))
    path = directory / 'WT6A_INF/decklcd-config.inf'
    entry = next(item for item in report['files_before_catalog_regeneration'] if item['path'] == 'decklcd-config.inf')
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != entry['sha256']:
        raise ValueError('Prepared INF differs from the verified configuration build.')
    result = adapt(raw)
    path.write_bytes(result)
    entry['sha256'] = hashlib.sha256(result).hexdigest()
    report['extension_copy_inf_adapted'] = True
    report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    update(parser.parse_args().directory)
