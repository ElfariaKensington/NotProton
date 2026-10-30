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
args = parser.parse_args()
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
    with (bundle / 'Contents/Info.plist').open('wb') as f:
        plistlib.dump(dict(CFBundleName='Resolution Game', CFBundleExecutable='launcher',
            CFBundleIdentifier='com.notproton.display-wine-test', CFBundlePackageType='APPL',
            LSApplicationCategoryType='public.app-category.games', NSHighResolutionCapable=True), f)
    executable = root / 'DisplayFixture.exe'
    subprocess.run(['x86_64-w64-mingw32-gcc', '-O2', '-o', str(executable),
                    str(ROOT / 'dylib/tests/display-wine-fixture.c'), '-luser32', '-lgdi32'], check=True)
    env = dict(os.environ, CX_ROOT=str(cx), CX_HOME=str(root / 'cx-home'),
        WINEPREFIX=str(root / 'pfx'), WINEDEBUG='-all', WINEMSYNC='0', WINESERVER=str(server),
        WINELOADER=str(macos / 'wine'), loader_macos=str(macos), loader_root=str(root))
    for name in ('DYLD_INSERT_LIBRARIES', 'STEAM_DYLD_INSERT_LIBRARIES', 'NOTPROTON_FEATURE_DYLIBS'):
        env.pop(name, None)
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
    enforced, log = run('1920x1080', window=True)
    assert enforced == ('1920', '1080', '1920', '1080'), (enforced, log[-3000:])
    assert 'entered native fullscreen at 1920x1080' in log, log[-4000:]
    print('Wine fullscreen desktop and client: 1920x1080; physical display unchanged.', flush=True)
    restored, _ = run('')
    assert restored[:2] == baseline[:2], (baseline, restored)
    print('Disabling enforcement restores the default Wine desktop.', flush=True)
