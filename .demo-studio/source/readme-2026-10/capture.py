#!/usr/bin/env python3
"""Build a capture-only copy. Never edits the product sources or saved settings."""
import pathlib
import shutil
import subprocess
import tempfile

source = pathlib.Path(__file__).resolve().parent
repo = source.parents[2]
production = repo / '.demo-studio/_production'
production.mkdir(parents=True, exist_ok=True)
stage = pathlib.Path(tempfile.mkdtemp(prefix='readme-', dir=production))
output = repo / '.demo-studio/capture/readme-2026-10' / stage.name
for name in ('Package.swift', 'Package.resolved'):
    shutil.copy2(repo / name, stage / name)
for name in ('Sources', 'Resources', 'scripts'):
    shutil.copytree(repo / name, stage / name)
shutil.copy2(source / 'ReadmeCapture.swift', stage / 'Sources/Tyto/Dev/ReadmeCapture.swift')
test = stage / 'Sources/Tyto/Dev/SelfTest.swift'
text = test.read_text()
anchor = '        if let path = value(after: "--selftest-glass") {'
assert text.count(anchor) == 1
text = text.replace(anchor, '''        if let path = value(after: "--capture-readme") {
            Task { exit(await readmeCapture(to: path)) }
            return true
        }
''' + anchor)
test.write_text(text)
print(f'Capture-only build: {stage}', flush=True)
subprocess.run(['scripts/build-app.sh'], cwd=stage, check=True)
subprocess.run([str(stage / 'build/Tyto.app/Contents/MacOS/Tyto'), '--capture-readme', str(output)], check=True)
