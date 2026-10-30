#!/usr/bin/env python3
"""Exercise launcher fast paths without Wine, Steam, or a real prefix."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(sys.argv.pop(1) if len(sys.argv) > 1 else Path(__file__).parents[1] / 'feats/compat_run.sh').read_text()


def embedded(marker):
    return re.search(r"<<'" + marker + r"'\n(.*?)\n" + marker, SOURCE, re.S)[1]


class LaunchFastPaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_code(self, marker, *args):
        return subprocess.run([sys.executable, '-I', '-c', embedded(marker), *map(str, args)], capture_output=True, text=True)

    def install_fixture(self, completed=True, action='run process'):
        script = self.root / 'script.vdf'
        script.write_text('"evaluatorscript" { "0" { "appid" "228980" "mode" "1" '
            '"compat_installscript" { "' + action + '" { "dxsetup" { '
            '"hasrunkey" "HKEY_LOCAL_MACHINE\\\\Software\\\\Valve\\\\Steam\\\\Apps\\\\CommonRedist\\\\DirectX\\\\Jun2010" '
            '"process 1" "%INSTALLDIR%\\\\_CommonRedist\\\\DirectX\\\\Jun2010\\\\DXSETUP.exe" '
            '"command 1" "/silent" "nocleanup" "1" } } } } }')
        (self.root / 'system.reg').write_text('[Software\\\\Wow6432Node\\\\Valve\\\\Steam\\\\Apps\\\\CommonRedist\\\\DirectX\\\\Jun2010]\n'
            '"dxsetup"=dword:0000000' + ('1' if completed else '0') + '\n')
        return script

    def test_completed_install_check(self):
        self.assertEqual(self.run_code('NP_COMPLETED_REDIST', self.install_fixture(), self.root).returncode, 0)

    def vcredist_2013_fixture(self, x64_complete=True):
        script = self.install_fixture()
        text = script.read_text().replace('DirectX\\\\Jun2010', 'vcredist\\\\2013')
        text = text.replace('dxsetup', 'x86 12.0.30501').replace('DXSETUP.exe', 'vcredist_x86.exe')
        # Two architectures must both be complete before the helper is skipped.
        text = text.replace('"nocleanup" "1"', '"nocleanup" "1" } "x64 12.0.30501" { '
            '"hasrunkey" "HKEY_LOCAL_MACHINE\\\\Software\\\\Valve\\\\Steam\\\\Apps\\\\CommonRedist\\\\vcredist\\\\2013" '
            '"process 1" "%INSTALLDIR%\\\\_CommonRedist\\\\vcredist\\\\2013\\\\vcredist_x64.exe" '
            '"nocleanup" "1" "requirement_os" { "Is64BitWindows" "1" }')
        script.write_text(text)
        (self.root / 'system.reg').write_text('[Software\\\\Wow6432Node\\\\Valve\\\\Steam\\\\Apps\\\\CommonRedist\\\\vcredist\\\\2013]\n'
            '"x86 12.0.30501"=dword:00000001\n'
            '"x64 12.0.30501"=dword:0000000' + ('1' if x64_complete else '0') + '\n')
        return script

    def test_completed_vcredist_2013_both_architectures(self):
        script = self.vcredist_2013_fixture()
        self.assertEqual(self.run_code('NP_COMPLETED_REDIST', script, self.root).returncode, 0)

    def test_incomplete_vcredist_2013_requires_evaluator(self):
        script = self.vcredist_2013_fixture(x64_complete=False)
        self.assertNotEqual(self.run_code('NP_COMPLETED_REDIST', script, self.root).returncode, 0)

    def test_incomplete_install_requires_evaluator(self):
        self.assertNotEqual(self.run_code('NP_COMPLETED_REDIST', self.install_fixture(False), self.root).returncode, 0)

    def test_unknown_action_requires_evaluator(self):
        self.assertNotEqual(self.run_code('NP_COMPLETED_REDIST', self.install_fixture(action='registry'), self.root).returncode, 0)

    def test_malformed_script_requires_evaluator(self):
        script = self.install_fixture()
        script.write_text('broken')
        self.assertNotEqual(self.run_code('NP_COMPLETED_REDIST', script, self.root).returncode, 0)

    def test_cache_dependency_changes(self):
        cache = self.root / 'cache.json'
        dependency = self.root / 'bridge.dll'
        dependency.write_text('original')
        args = (cache, 'environment', 'WINELOADER=/runner/wine', dependency)
        self.assertEqual(self.run_code('NP_METADATA_CACHE', 'write', *args).returncode, 0)
        self.assertEqual(self.run_code('NP_METADATA_CACHE', 'read', *args).returncode, 0)
        dependency.write_text('changed')
        self.assertNotEqual(self.run_code('NP_METADATA_CACHE', 'read', *args).returncode, 0)
        dependency.unlink()
        self.assertNotEqual(self.run_code('NP_METADATA_CACHE', 'read', *args).returncode, 0)

    def test_native_helpers_invalidate_bundle_cache(self):
        host, client = self.root / 'game-host', self.root / 'game-client.dylib'
        display = self.root / 'game-display.dylib'
        display.write_text('display v1')
        host.write_text('host v1')
        client.write_text('client v1')
        functions = '\n'.join(re.search(r'^' + name + r'\(\) \{\n.*?^\}', SOURCE, re.M | re.S)[0]
                              for name in ('np_cache', 'np_bundle_stamp'))
        parameters = re.search(r'^np_bundle_parameters=.*$', SOURCE, re.M)[0]
        env = dict(os.environ, np_game_host=str(host), np_game_client=str(client),
                   np_single_icon='1', np_display_helper=str(display), np_bundle_cache=str(self.root / 'bundle-cache.json'),
                   loader_root=str(self.root), loader_app=str(self.root / 'Game.app'),
                   wine_unix=str(self.root / 'runner'), client_root=str(self.root),
                   game_name='Example', app_id='480', WINELOADER='/runner/wine')
        def stamp(mode):
            script = functions + '\n' + parameters + '\nnp_bundle_stamp "$1" "WINELOADER=/runner/wine"'
            return subprocess.run(['sh', '-ec', script, 'sh', mode], env=env, capture_output=True).returncode
        self.assertEqual(stamp('write'), 0)
        self.assertEqual(stamp('read'), 0)
        client.write_text('client v2')
        self.assertNotEqual(stamp('read'), 0)
        self.assertEqual(stamp('write'), 0)
        host.write_text('host v2')
        self.assertNotEqual(stamp('read'), 0)
        self.assertEqual(stamp('write'), 0)
        display.write_text('display v2')
        self.assertNotEqual(stamp('read'), 0)
        self.assertEqual(stamp('write'), 0)
        env['np_single_icon'] = '0'
        self.assertNotEqual(stamp('read'), 0)

    def test_bundle_detects_symlink_change(self):
        bundle = self.root / 'Game.app'
        bundle.mkdir()
        link = bundle / 'library.dylib'
        link.symlink_to('/one')
        before = self.run_code('NP_BUNDLE_CHECK', bundle)
        link.unlink()
        link.symlink_to('/two')
        after = self.run_code('NP_BUNDLE_CHECK', bundle)
        self.assertEqual(before.returncode, 0)
        self.assertEqual(after.returncode, 0)
        self.assertNotEqual(before.stdout, after.stdout)


if __name__ == '__main__':
    unittest.main()
