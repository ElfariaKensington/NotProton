#!/usr/bin/env python3
"""Exercise the actual launcher's prefix-file reader and environment forwarding."""
from pathlib import Path
import os
import subprocess
import tempfile

source = Path('dylib/feats/compat_run.sh').read_text()
reader = source[source.index('np_game_env_text=""'):source.index('np_from_defaults() {')]
forward = source[source.index('# Forward custom names'):source.index('# Prepended first')]
with tempfile.TemporaryDirectory(prefix='notproton-env-') as root:
    path = Path(root)
    marker = path / 'must-not-exist'
    text = (f'# comment\r\n\r\n FOO =old\r\nFOO=two words=ok\nEMPTY=\n'
            f'LITERAL=$(touch {marker}); `touch {marker}` $HOME "quoted"\n'
            'UNICODE=Türkçe 日本語\nname=game-name\nlog=game-log\n'
            'WINEMSYNC=1\nWINEDEBUG=-all\nDXMT_CONFIG=a=b\n'
            'PATH=/bad\nWINEPREFIX=/bad\nNOTPROTON_GAME_CWD=/bad\nBAD-NAME=no\n'
            'LAST=no-newline')
    (path / 'notproton.env').write_text(text)
    script = reader + '\nset -- game.exe "argument with spaces"\n' + forward + '''
    printf '%s\\0' "$WINEMSYNC" "$WINEDEBUG" "$DXMT_CONFIG" "$log" "$@"
    '''
    env = dict(os.environ, STEAM_COMPAT_DATA_PATH=root, verb='waitforexitandrun', log='launcher-log')
    result = subprocess.check_output(['sh', '-ec', script], env=env).decode().split('\0')[:-1]
    assert result[:4] == ['1', '-all', 'a=b', 'launcher-log'], result
    args = result[4:]
    assert args[-2:] == ['game.exe', 'argument with spaces'], args
    pairs = args[:-2]
    assert pairs[::2] == ['--env'] * (len(pairs) // 2)
    forwarded = dict(item.split('=', 1) for item in pairs[1::2])
    assert forwarded == dict(FOO='two words=ok', EMPTY='',
        LITERAL=f'$(touch {marker}); `touch {marker}` $HOME "quoted"',
        UNICODE='Türkçe 日本語', name='game-name', log='game-log', LAST='no-newline'), forwarded
    assert not marker.exists(), 'Values must never run as shell commands'
    env['verb'] = 'runinprefix'
    out = subprocess.check_output(['sh', '-ec', reader + 'printf %s "$np_game_env_text"'], env=env)
    assert out == b'', 'Helper launches do not import per-game settings'
    (path / 'notproton.env').unlink()
    env['verb'] = 'waitforexitandrun'
    out = subprocess.check_output(['sh', '-ec', reader + 'printf %s "$np_game_env_text"'], env=env)
    assert out == b'', 'No file means no custom environment'
print('==> gameenv: literal values, duplicates, Unicode, empty values, argv and helper isolation pass')
