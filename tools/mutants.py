#!/usr/bin/env python3
"""Mutation runs: does a test fail when the code it is about is broken?

    python3 tools/mutants.py <test ids> <list.py> [log]

<list.py> defines MUTANTS = [(file, old, new, label), ...]: one textual
change each, in a file of the project (`old` must occur exactly once). Each
change is applied by itself, the named tests are run
(tests/run_tests.gd -- --only=<test ids>), and the file is put back byte for
byte. A mutant is killed when a test fails or no longer compiles. A mutant
that lives shows where the tests do not reach: strengthen the test, or note
why the change makes no difference.

MUT_ROOT names a copy of the project to work in (default: this project), so
that the working tree stays free during a long run:

    mkdir /tmp/copy && git archive HEAD | tar x -C /tmp/copy
    (cd /tmp/copy && godot --headless --path . --import)
    MUT_ROOT=/tmp/copy python3 tools/mutants.py T-BOSS-02 tools/mutants/storm.py run.log
"""
import filecmp
import os
import runpy
import shutil
import subprocess
import sys
import tempfile

if len(sys.argv) < 3:
    sys.exit(__doc__)
root = os.environ.get('MUT_ROOT', os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
tests = sys.argv[1]
mutants = runpy.run_path(sys.argv[2])['MUTANTS']
log = open(sys.argv[3], 'w') if len(sys.argv) > 3 else sys.stdout
backup = os.path.join(tempfile.gettempdir(), 'mutants.%d.backup' % os.getpid())
godot = os.environ.get('GODOT', 'godot')
alive = []
for index, (path, old, new, label) in enumerate(mutants):
    full = os.path.join(root, path)
    text = open(full).read()
    if text.count(old) != 1:
        print(f'#{index + 1} {label}: NOT APPLIED ({text.count(old)} matches)', file=log, flush=True)
        alive.append(label + ' (not applied)')
        continue
    shutil.copyfile(full, backup)
    open(full, 'w').write(text.replace(old, new, 1))
    try:
        out = subprocess.run([godot, '--headless', '--path', root, '--script', 'res://tests/run_tests.gd', '--', '--only=' + tests, '--verbose'],
                             capture_output=True, text=True, timeout=1800).stdout
    finally:
        shutil.copyfile(backup, full)
    assert filecmp.cmp(backup, full, shallow=False)
    lines = [line for line in out.splitlines() if line.startswith('[') or line.strip().startswith('- ') or 'Parse Error' in line or 'SCRIPT ERROR' in line]
    killed = any(line.startswith('[FAIL]') or line.startswith('[TODO]') for line in lines)
    first = next((line.strip() for line in lines if line.strip().startswith('- ') or 'Error' in line or 'ERROR' in line), '')
    print(f'#{index + 1} {label}: {"KILLED" if killed else "ALIVE"}  {first[:160]}', file=log, flush=True)
    if not killed:
        alive.append(label)
if os.path.exists(backup):
    os.remove(backup)
print(f'DONE: {len(mutants) - len(alive)} of {len(mutants)} killed; alive: {alive}', file=log, flush=True)
