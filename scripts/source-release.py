#!/usr/bin/env python3
"""Create a clean source archive, with vendored patches and dependency sources."""
from pathlib import Path
import tarfile
from importlib.util import module_from_spec, spec_from_file_location

ROOT = Path(__file__).resolve().parent.parent
spec = spec_from_file_location('notices', ROOT / 'scripts/third-party-notices.py')
notices = module_from_spec(spec)
spec.loader.exec_module(notices)
notices.main()
destination = ROOT / 'docs/releases/LabelPrint-0.1.0-source.tar.gz'
destination.parent.mkdir(exist_ok=True)
exclude = {'.git', '.DS_Store', '__pycache__', '.build', '.cache', '.idea', '.swiftpm', 'dist'}


def clean(info):
    if any(part in exclude or part.startswith('cmake-build-') for part in Path(info.name).parts):
        return None
    if any('/docs/' + name in info.name for name in ('design', 'releases', 'references')):
        return None
    if '/backend/target' in info.name or '/vendor/ptouch-rs/target' in info.name:
        return None
    return info


with tarfile.open(destination, 'w:gz') as archive:
    for name in ('Sources', 'Tests', 'backend', 'scripts', 'vendor/ptouch-rs',
                 'ThirdPartyNotices', 'docs', 'Package.swift', 'CMakeLists.txt',
                 'README.md', 'LICENSE', 'NOTICE', '.gitignore', 'assets/app-ui.png'):
        if (ROOT / name).exists():
            archive.add(ROOT / name, arcname='LabelPrint/' + name, filter=clean)
    for package in notices.dependencies():
        if package['source'] is not None:
            source = Path(package['manifest_path']).parent
            archive.add(source, arcname='LabelPrint/vendor/dependency-sources/' + source.name, filter=clean)
print('Created ' + str(destination))
