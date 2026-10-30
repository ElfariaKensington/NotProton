#!/usr/bin/env python3
"""Optional actual Wine regression; requires an installed NotProton-patched CrossOver runner."""
import argparse
import ctypes
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--crossover-root', required=True, type=Path)
parser.add_argument('--native-dialog-input', action='store_true', help='Exercise real Wine input with stale splash capture')
parser.add_argument('--resolution', default='1920x1080')
args = parser.parse_args()
if not re.fullmatch(r'[0-9]+x[0-9]+', args.resolution): parser.error('Invalid resolution')
cx = args.crossover_root.resolve()
loader = cx / 'lib/wine/x86_64-unix/wine'
server = cx / 'bin/wineserver-x86'
if not loader.is_file() or not server.is_file():
    parser.error('The CrossOver root must contain the x86_64 Wine loader and wineserver-x86.')

cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
cg.CGMainDisplayID.restype = ctypes.c_uint32
cg.CGDisplayCopyDisplayMode.argtypes = [ctypes.c_uint32]
cg.CGDisplayCopyDisplayMode.restype = ctypes.c_void_p
cg.CGDisplayModeRelease.argtypes = [ctypes.c_void_p]
def physical_mode():
    mode = cg.CGDisplayCopyDisplayMode(cg.CGMainDisplayID())
    try:
        values = []
        for name in ('CGDisplayModeGetWidth', 'CGDisplayModeGetHeight', 'CGDisplayModeGetPixelWidth', 'CGDisplayModeGetPixelHeight'):
            function = getattr(cg, name)
            function.argtypes = [ctypes.c_void_p]
            function.restype = ctypes.c_size_t
            values.append(function(mode))
        return tuple(values)
    finally:
        cg.CGDisplayModeRelease(mode)

before = physical_mode()
with tempfile.TemporaryDirectory(prefix='np-display-wine-') as temporary:
    root = Path(temporary)
    bundle = root / 'Resolution Game.app'
    macos = bundle / 'Contents/MacOS'
    macos.mkdir(parents=True)
    for file in loader.parent.iterdir():
        if file.name not in ('wine', 'wine.app'):
            (macos / file.name).symlink_to(file)
    subprocess.run(['cp', '-c', str(loader), str(macos / 'wine')], check=True)
    subprocess.run(['cp', str(ROOT / 'out/game-display.dylib'), str(macos / 'game-display.dylib')], check=True)
    if args.native_dialog_input:
        cursor = ROOT / 'out/game-cursor.dylib'
        if cursor.is_file(): (macos / 'game-cursor.dylib').write_bytes(cursor.read_bytes())
        subprocess.run(['clang','-fobjc-arc','-dynamiclib','-mmacosx-version-min=15.0',
            '-arch','arm64','-arch','x86_64','-framework','AppKit',
            str(ROOT / 'dylib/tests/display-dialog-probe.m'),'-o',str(macos / 'probe.dylib')], check=True)
    with (bundle / 'Contents/Info.plist').open('wb') as f:
        plistlib.dump(dict(CFBundleName='Resolution Game', CFBundleExecutable='launcher',
            CFBundleIdentifier='com.notproton.display-wine-test', CFBundlePackageType='APPL',
            LSApplicationCategoryType='public.app-category.games', NSHighResolutionCapable=True), f)
    executable = root / 'DisplayFixture.exe'
    subprocess.run(['x86_64-w64-mingw32-gcc', '-O2', '-o', str(executable),
                    str(ROOT / 'dylib/tests/display-wine-fixture.c'), '-luser32', '-lgdi32', '-lopengl32'], check=True)
    env = dict(os.environ, CX_ROOT=str(cx), CX_HOME=str(root / 'cx-home'),
        WINEPREFIX=str(root / 'pfx'), WINEDEBUG='-all', WINEMSYNC='0', WINESERVER=str(server),
        WINELOADER=str(macos / 'wine'), loader_macos=str(macos), loader_root=str(root))
    for name in ('DYLD_INSERT_LIBRARIES', 'STEAM_DYLD_INSERT_LIBRARIES', 'NOTPROTON_FEATURE_DYLIBS'):
        env.pop(name, None)
    if args.native_dialog_input:
        env.update(NOTPROTON_FEATURE_DYLIBS=str(macos / 'probe.dylib'),
            NP_INPUT_LOG=str(root / 'notproton-wine.log'), NP_TEST_NATIVE_DIALOG_INPUT='1')
    source = (ROOT / 'dylib/feats/compat_run.sh').read_text()
    recipe = re.search(r'cat > "\$loader_macos/launcher" <<LAUNCHER\n.*?\nLAUNCHER', source, re.S)[0]
    subprocess.run(['sh', '-ec', recipe], env=env, check=True)
    (macos / 'launcher').chmod(0o755)
    def run(resolution, window=False):
        subprocess.run([str(server), '-k'], env=env, capture_output=True)
        try:
            result = subprocess.run([str(macos / 'launcher'), str(executable)] + ([] if window else ['--probe']),
                env=dict(env, NOTPROTON_DISPLAY_RESOLUTION=resolution), timeout=75)
            text = (root / 'notproton-wine.log').read_text()
            assert result.returncode == 0, text[-4000:]
            match = re.search(r'desktop=(\d+)x(\d+)(?: client=(\d+)x(\d+))?', text)
            assert match, text[-4000:]
            assert physical_mode() == before, 'The physical macOS display mode changed'
            return match.groups(), text
        finally:
            subprocess.run([str(server), '-k'], env=env, capture_output=True)
    baseline, _ = run('')
    print('Wine baseline desktop:', 'x'.join(baseline[:2]), flush=True)
    enforced, log = run(args.resolution, window=True)
    assert enforced == tuple(args.resolution.split('x') * 2), (enforced, log[-3000:])
    assert 'entered native fullscreen at ' + args.resolution in log, log[-4000:]
    dialog=re.search(r'dialog=(\d+)x(\d+)',log)
    assert dialog and int(dialog[1])<900 and int(dialog[2])<500, 'startup dialog was enlarged: '+log[-4000:]
    if args.native_dialog_input:
        assert 'input=FAILED' not in log and 'inputResult=7' in log and 'nativeDialogInput=captureRestored' in log, log
        print('Real Wine dialog: native mouse click selects No despite stale splash capture; capture restored.', flush=True)
    print('Wine graphics window: '+args.resolution+' fullscreen; startup warning stays windowed; physical display unchanged.', flush=True)
    restored, _ = run('')
    assert restored[:2] == baseline[:2], (baseline, restored)
    print('Disabling enforcement restores the default Wine desktop.', flush=True)
