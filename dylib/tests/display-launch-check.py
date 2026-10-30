#!/usr/bin/env python3
"""Exercise the launcher's actual prefix-file validation and helper guard."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'dylib/feats/compat_run.sh').read_text()
start = source.index('np_display_resolution=""')
end = source.index('if [ -n "$STEAM_COMPAT_DATA_PATH" ]; then\n  export WINEPREFIX=', start)
code = 'show_alert() { echo "alert:$1"; };\n' + source[start:end] + '\nprintf "resolution=%s\\n" "$np_display_resolution"\nprintf "arg=%s\\n" "$@"\n'
with tempfile.TemporaryDirectory(prefix='np-display-launch-') as temporary:
    root = Path(temporary)
    data = root / 'prefix'; data.mkdir()
    support = root / 'support'; (support / 'bridge').mkdir(parents=True)
    helper = support / 'bridge/game-display.dylib'; helper.touch()
    env = dict(os.environ, STEAM_COMPAT_DATA_PATH=str(data), np_support=str(support), verb='waitforexitandrun')
    def run(text=None, verb='waitforexitandrun'):
        path = data / 'notproton-display'
        if text is None: path.unlink(missing_ok=True)
        else: path.write_text(text)
        return subprocess.run(['sh', '-ec', code, 'test', 'Game.exe', 'literal argument'],
                              env=dict(env, verb=verb), capture_output=True, text=True)
    disabled = run()
    assert disabled.returncode == 0 and 'resolution=\n' in disabled.stdout
    enabled = run('1920x1080\n')
    assert enabled.returncode == 0 and 'resolution=1920x1080\n' in enabled.stdout
    assert enabled.stdout.endswith('arg=Game.exe\narg=literal argument\n'), enabled.stdout
    for invalid in ('', '123', '1920x0', '1x1080', '999999999999x1080', '1920x1080;bad'):
        result = run(invalid)
        assert result.returncode == 1 and 'Invalid fullscreen resolution' in result.stdout, (invalid, result)
    helper.unlink()
    missing = run('1920x1080')
    assert missing.returncode == 1 and 'helper is missing' in missing.stdout
    for verb in ('run', 'runinprefix'):
        result = run('1920x1080', verb=verb)
        assert result.returncode == 0 and 'resolution=\n' in result.stdout
print('==> display launch: disabled/default, valid/invalid, missing-helper, helper-process and argv checks pass')
