#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./build.sh --preview
swiftc -module-cache-path .build/module-cache Support/publish_bundle.swift -o .build/preview-publish
python3 - <<'PY'
from pathlib import Path
import os, signal, subprocess, tempfile, time, shutil
root = Path.cwd()
app = Path('/Applications/Utilipilled.app')
backup = Path(tempfile.mkdtemp(prefix='preview-backup-', dir=root / '.build')) / 'previous-app'
subprocess.run(['ditto', str(app), str(backup)], check=True)
stage = Path(tempfile.mkdtemp(prefix='.Utilipilled-preview-', dir='/Applications'))
try:
    staged = stage / 'Utilipilled.app'
    subprocess.run(['ditto', str(root / 'dist/Utilipilled.app'), str(staged)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(staged)], check=True)
    executable = str(app / 'Contents/MacOS/Utilipilled')
    processes = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True)
    pids = [int(parts[0]) for line in processes.splitlines()
            if len(parts := line.strip().split(None, 1)) == 2
            and (parts[1] == executable or parts[1] == executable + ' --debug')]
    for pid in pids: os.kill(pid, signal.SIGTERM)
    for _ in range(100):
        live = []
        for pid in pids:
            try: os.kill(pid, 0); live.append(pid)
            except ProcessLookupError: pass
        if not live: break
        time.sleep(.1)
    else: raise RuntimeError('The app did not quit normally; update left unapplied')
    subprocess.run([str(root / '.build/preview-publish'), str(staged), str(app)], check=True)
    print(f'Installed local preview. Previous app: {backup}')
finally:
    shutil.rmtree(stage)
    subprocess.run(['open', str(app)], check=False)
PY
