#!/usr/bin/env python3
"""Native cursor policy/ownership and generated game-launcher regression."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='np-cursor-') as directory:
    root=Path(directory); fixture=root/'cursor-fixture'
    subprocess.run(['clang','-fobjc-arc','-O2','-Wall','-Wextra','-Wno-unused-function',
        '-mmacosx-version-min=15.0','-framework','AppKit','-framework','QuartzCore','-framework','Metal',
        str(ROOT/'dylib/tests/cursor-fixture.m'),'-o',str(fixture)],check=True)
    subprocess.run([str(fixture)],check=True)
    for image,expected in [('Game.exe','game'),('C:\\Games\\Example\\Game.exe','game'),
        ('steam.exe','other'),('C:\\windows\\system32\\notepad.exe','other'),
        ('crashpad_handler.exe','other'),('UnityCrashHandler64.exe','other'),
        ('C:\\legacycompat\\iscriptevaluator.exe','other'),('Finder','other')]:
        result=subprocess.check_output([str(fixture),'--classify',image],text=True).strip()
        assert result==expected,(image,result)
    source=(ROOT/'dylib/feats/compat_run.sh').read_text()
    launcher=re.search(r'cat > "\$loader_macos/launcher" <<LAUNCHER\n.*?\nLAUNCHER',source,re.S)[0]
    macos=root/'Game.app/Contents/MacOS';macos.mkdir(parents=True)
    loader=macos/'wine';loader.write_text('#!/bin/sh\nprintf "%s\\n" "$DYLD_INSERT_LIBRARIES"\nprintf "arg=%s\\n" "$@"\n');loader.chmod(0o755)
    env=dict(os.environ,loader_macos=str(macos),loader_root=str(root),WINELOADER=str(loader))
    subprocess.run(['sh','-ec',launcher],env=env,check=True);(macos/'launcher').chmod(0o755)
    # Inspect the generated shell's exports in-process: SIP strips DYLD variables
    # when invoking /bin/sh, so a second shell cannot stand in for an unsigned Wine loader.
    path=macos/'launcher'
    script=path.read_text().replace('#!/bin/sh','#!/bin/sh\nexport DYLD_INSERT_LIBRARIES="$NP_TEST_EXISTING"',1)
    script=script.replace('exec "'+str(loader)+'" "$@"', 'printf "%s\\n" "$DYLD_INSERT_LIBRARIES"; printf "arg=%s\\n" "$@"')
    path.write_text(script)
    for present in (False,True):
        helper=macos/'game-cursor.dylib'
        if present:helper.touch()
        subprocess.run([str(path),'Game.exe','literal argument'],env=dict(env,
            NP_TEST_EXISTING='/existing.dylib',NOTPROTON_FEATURE_DYLIBS='/feature.dylib'),check=True)
        log=(root/'notproton-wine.log').read_text()
        expected='/existing.dylib:/feature.dylib'+(':'+str(helper) if present else '')
        assert log==expected+'\narg=Game.exe\narg=literal argument\n',log
print('cursor: process exclusions, optional staging, existing injection and literal argv pass')
