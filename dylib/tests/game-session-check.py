#!/usr/bin/env python3
"""Check bundle staging and native session shutdown without Wine or Steam."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(sys.argv.pop(1) if len(sys.argv) > 1 else ROOT / 'dylib/feats/compat_run.sh').read_text()
RECIPE = re.search(r'(cat > "\$loader_macos/launcher" <<LAUNCHER\n.*?)\n\nbundle_listing\(\)', SOURCE, re.S)[1]


class GameSession(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='np-game-session-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle = self.root / 'Example Game.app'
        self.macos = self.bundle / 'Contents/MacOS'
        self.macos.mkdir(parents=True)
        self.env = os.environ.copy()
        for key in ('DYLD_INSERT_LIBRARIES', 'NOTPROTON_GAME_CHANNEL', 'NOTPROTON_FEATURE_DYLIBS',
                    'STEAM_DYLD_INSERT_LIBRARIES', 'NOTPROTON_GAME_CWD'):
            self.env.pop(key, None)
        self.env.update(loader_macos=str(self.macos), loader_root=str(self.root),
                        WINELOADER=str(self.macos / 'wine'), np_game_host=str(ROOT / 'out/game-host'),
                        np_game_client=str(ROOT / 'out/game-client.dylib'))

    def stage(self, enabled):
        self.env['np_single_icon'] = str(int(enabled))
        subprocess.run(['sh', '-ec', RECIPE], env=self.env, check=True)

    def test_fallback_uses_existing_shell_entry(self):
        self.stage(False)
        self.assertTrue((self.macos / 'launcher').read_text().startswith('#!/bin/sh'))
        self.assertFalse((self.macos / 'wine-launch.sh').exists())

    def test_host_carries_both_architectures(self):
        self.stage(True)
        for name in ('launcher', 'game-client.dylib'):
            arches = subprocess.check_output(['lipo', '-archs', self.macos / name], text=True).split()
            self.assertEqual(set(arches), {'arm64', 'x86_64'})
        self.assertTrue((self.macos / 'wine-launch.sh').is_file())

    def test_quit_stops_only_the_requested_prefix_and_preserves_arguments(self):
        self.check_session(quit_from_host=True)

    def test_game_exit_removes_the_host_and_stops_the_prefix(self):
        self.check_session(quit_from_host=False)

    def check_session(self, quit_from_host):
        import plistlib
        self.stage(True)
        with (self.bundle / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleExecutable': 'launcher', 'CFBundleName': 'Example Game',
                          'CFBundlePackageType': 'APPL', 'CFBundleIdentifier': 'com.notproton.test.game'}, stream)
        fixture = ROOT / 'out/game-session-fixture'
        (self.macos / 'wine').write_bytes(fixture.read_bytes())
        (self.macos / 'wine').chmod(0o755)
        server = self.root / 'wineserver'
        server.write_text('#!/bin/sh\nprintf "%s\\n" "$WINEPREFIX" "$1" > "$NP_GAME_TEST_STOP"\n'
                          'kill "$(/usr/bin/plutil -extract pid raw -o - "$NP_GAME_TEST_STATE")"\n')
        server.chmod(0o755)
        state = self.root / 'state.json'
        stopped = self.root / 'stopped'
        self.env.update(WINESERVER=str(server), WINEPREFIX=str(self.root / 'prefix'),
                        NP_GAME_TEST_STATE=str(state), NP_GAME_TEST_STOP=str(stopped))
        arguments = ['argument with spaces', '-switch', 'literal$argument']
        host = subprocess.Popen([self.macos / 'launcher', *arguments], env=self.env)
        client_pid = None
        try:
            deadline = time.monotonic() + 15
            while not state.exists():
                self.assertIsNone(host.poll(), 'host exited before launching the client')
                if time.monotonic() >= deadline:
                    self.fail('client did not publish its state')
                time.sleep(0.05)
            data = json.loads(state.read_text())
            client_pid = data['pid']
            self.assertEqual(data['policy'], 1)
            self.assertEqual(data['arguments'][1:], arguments)
            self.assertIn(str(self.macos / 'game-client.dylib'), data['libraries'])
            if quit_from_host:
                subprocess.run([fixture, '--quit', str(host.pid)], check=True)
            else:
                os.kill(client_pid, signal.SIGTERM)
            self.assertEqual(host.wait(timeout=15), 0)
            self.assertEqual(stopped.read_text().splitlines(), [self.env['WINEPREFIX'], '-k'])
        finally:
            if host.poll() is None:
                host.kill()
                host.wait()
            if client_pid:
                try:
                    os.kill(client_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


if __name__ == '__main__':
    unittest.main()
