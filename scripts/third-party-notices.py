#!/usr/bin/env python3
"""Collect exact license notices from the locked macOS Cargo dependency graph."""
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def dependencies():
    env = dict(os.environ, CARGO_HOME=str(ROOT / '.cache/cargo'))
    host = next(line.split(': ', 1)[1] for line in subprocess.check_output(
        ['rustc', '-vV'], text=True).splitlines() if line.startswith('host: '))
    data = subprocess.check_output([
        'cargo', 'metadata', '--manifest-path', str(ROOT / 'backend/Cargo.toml'),
        '--locked', '--offline', '--filter-platform', host, '--format-version', '1'
    ], env=env, text=True)
    return json.loads(data)['packages']


def main():
    destination = ROOT / 'ThirdPartyNotices'
    destination.mkdir(exist_ok=True)
    lines = ['# Third-party licenses', '',
             'Generated from the locked macOS dependency graph, including build dependencies.',
             'Original notices below retain their upstream copyright holders.', '',
             '| Package | Version | SPDX license |', '| --- | --- | --- |']
    for package in sorted(dependencies(), key=lambda p: p['name']):
        if package['name'] == 'label-backend':
            continue
        name = package['name'] + '-' + package['version']
        source = Path(package['manifest_path']).parent
        notices = sorted({p for pattern in ('LICENSE*', 'COPYING*', 'NOTICE*', 'UNLICENSE*')
                          for p in source.glob(pattern) if p.is_file()})
        if package['name'] == 'ptouch-core':
            notices = [ROOT / 'vendor/ptouch-rs' / p for p in ('LICENSE', 'NOTICE')]
        if not notices:
            raise RuntimeError('No license text found for ' + name)
        target = destination / name
        target.mkdir(exist_ok=True)
        for path in notices:
            shutil.copy2(path, target / path.name)
        if package['name'] == 'libusb1-sys':
            # Rust wrapper is MIT, but the statically linked C library is LGPL.
            native = list(source.glob('**/libusb*/COPYING'))
            if not native:
                native = list(source.glob('**/COPYING'))
            if not native:
                raise RuntimeError('Missing bundled libusb COPYING')
            shutil.copy2(native[0], target / 'libusb-COPYING')
        lines.append('| [{}]({}/) | {} | {} |'.format(
            package['name'], name, package['version'], package['license']))
    lines += ['', '## Native library and platform components', '',
              '- libusb: LGPL-2.1-or-later; its COPYING text is included with libusb1-sys.',
              '- AppKit, SwiftUI, CoreGraphics, CoreImage and Vision are Apple system frameworks.',
              '- Installed fonts and SF Symbols are resolved from macOS at runtime; their font files are not bundled.',
              '- Swift/Rust toolchain runtime components retain their respective toolchain licenses.', '']
    index = ROOT / 'docs/third-party-licenses.md'
    index.parent.mkdir(exist_ok=True)
    index.write_text('\n'.join(lines).replace('](', '](../ThirdPartyNotices/'))
    print('Collected notices in ' + str(destination))


if __name__ == '__main__':
    main()
