"""Prepare a configuration-only package without installing or signing it."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

from build_config_candidate import build as verify_configuration
from build_package import add_hardware_id, child_path

INSTALL_NAMES = {
    'u0202038.inf': 'decklcd-config.inf',
    'u0202038.cat': 'decklcd-config.cat',
    'amduw23e.inf': 'decklcd-config-extension.inf',
    'amduw23e.cat': 'decklcd-config-extension.cat',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(source, output, manifest_path):
    source, output = source.resolve(), output.resolve()
    if output.exists() or output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError('Output must be a new directory outside the source tree.')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    inf_changes = [(spec, add_hardware_id(child_path(source, spec['path']).read_bytes(),
                                         spec, manifest['hardware_id']))
                   for spec in manifest['infs']]
    report = verify_configuration(child_path(source, manifest['kernel']),
                                  child_path(source, 'u0202038.inf'),
                                  child_path(source, 'B026204/amdgcf.dat'), output)
    package = output / 'WT6A_INF'
    shutil.copytree(source, package)
    shutil.copyfile(output / 'amdgcf.dat', package / 'B026204/amdgcf.dat')
    for spec, data in inf_changes:
        old_name = spec['path']
        old_catalog = old_name.removesuffix('.inf') + '.cat'
        new_catalog = INSTALL_NAMES[old_catalog]
        data, count = re.subn(rb'(?im)^(CatalogFile\s*=\s*)' + re.escape(old_catalog.encode()) + rb'(\r?$)',
                              lambda m: m[1] + new_catalog.encode() + m[2], data)
        if count != 1:
            raise ValueError('Unexpected INF catalog declaration.')
        child_path(package, INSTALL_NAMES[old_name]).write_bytes(data)
        child_path(package, old_name).unlink()
        child_path(package, old_catalog).rename(child_path(package, new_catalog))
    allowed_changes = {'B026204/amdgcf.dat', *(INSTALL_NAMES[spec['path']] for spec, _ in inf_changes)}
    changes, files, original_catalogs = [], [], []
    for original in sorted(source.rglob('*')):
        if not original.is_file():
            continue
        relative = original.relative_to(source)
        target = Path(INSTALL_NAMES.get(relative.as_posix(), relative.as_posix()))
        before, after = sha(original), sha(package / target)
        if before != after:
            changes.append(target.as_posix())
        files.append({'path': target.as_posix(), 'sha256': after})
        if original.suffix.lower() == '.cat':
            archived = output / 'original-catalogs' / relative
            archived.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original, archived)
            original_catalogs.append({'path': relative.as_posix(), 'sha256': before})
    if set(changes) != allowed_changes:
        raise ValueError(f'Unexpected changes in the prepared package: {changes}')
    report.update({
        'status': 'UnsignedConfigurationOnlyPackagePrepared',
        'package_directory': str(package),
        'driver_version': manifest['driver_version'],
        'hardware_id': manifest['hardware_id'],
        'main_inf': INSTALL_NAMES['u0202038.inf'],
        'extension_inf': INSTALL_NAMES['amduw23e.inf'],
        'renamed_package_files': INSTALL_NAMES,
        'changed_files': changes,
        'changed_executables': [],
        'source_files': len(files),
        'original_catalogs': original_catalogs,
        'files_before_catalog_regeneration': files,
        'installation_signing_required': True,
        'normal_mode_installation_verified': False,
    })
    (output / 'package-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ('files_before_catalog_regeneration', 'checks')}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    args = parser.parse_args()
    build(args.source, args.output, args.manifest)
