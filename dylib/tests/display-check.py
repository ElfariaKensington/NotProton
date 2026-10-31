#!/usr/bin/env python3
"""Probe actual interposition, native fullscreen, and physical display isolation."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
class DisplayIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='np-display-')
        cls.root = Path(cls.temp.name)
        cls.bundle = cls.root / 'Resolution Test.app'
        cls.macos = cls.bundle / 'Contents/MacOS'
        cls.macos.mkdir(parents=True)
        cls.loader = cls.macos / 'display-fixture'
        flags = ['clang', '-mmacosx-version-min=15.0', '-fobjc-arc', '-O2', '-Wall', '-Wextra',
                 '-framework', 'AppKit', '-framework', 'CoreGraphics', '-framework', 'QuartzCore', '-framework', 'Metal']
        subprocess.run(flags + ['-dynamiclib', '-o', str(cls.root / 'winemac.so'), str(ROOT / 'dylib/tests/display-driver-fixture.m')], check=True)
        subprocess.run(flags + ['-o', str(cls.loader), str(ROOT / 'dylib/tests/display-window-fixture.m')], check=True)
        with (cls.bundle / 'Contents/Info.plist').open('wb') as f:
            plistlib.dump(dict(CFBundleExecutable='display-fixture', CFBundleName='Resolution Test',
                CFBundlePackageType='APPL', CFBundleIdentifier='com.notproton.display-test',
                LSApplicationCategoryType='public.app-category.games', NSHighResolutionCapable=True), f)
        cls.env = dict(os.environ, NP_DISPLAY_TEST_DRIVER=str(cls.root / 'winemac.so'),
                       DYLD_INSERT_LIBRARIES=os.environ.get('NP_CURSOR_TEST_HELPER', str(ROOT / 'out/game-cursor.dylib')) + ':' + os.environ.get('NP_DISPLAY_TEST_HELPER', str(ROOT / 'out/game-display.dylib')))

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def probe(self, resolution='', window=False, session=False, exit_space=False, game_windowed=False, stay_windowed=False):
        env = dict(self.env, NOTPROTON_DISPLAY_RESOLUTION=resolution)
        if exit_space: env['NP_DISPLAY_TEST_EXIT']='1'
        if game_windowed: env['NP_DISPLAY_TEST_GAME_WINDOWED']='1'
        if stay_windowed: env['NP_DISPLAY_TEST_STAY_WINDOWED']='1'
        if session:
            env['DYLD_INSERT_LIBRARIES'] = str(ROOT / 'out/game-client.dylib') + ':' + env['DYLD_INSERT_LIBRARIES']
            env['NOTPROTON_GAME_CHANNEL'] = 'com.notproton.display-test.session'
        run = subprocess.run([str(self.loader)] + (['--window', 'Fixture.exe'] if window else []),
                             env=env, capture_output=True, text=True, timeout=18)
        self.assertEqual(run.returncode, 0, run.stderr + run.stdout)
        return json.loads(run.stdout.strip().splitlines()[-1])

    def test_default_is_passthrough(self):
        state = self.probe()
        self.assertEqual(state['virtual']['width'], state['physicalWidth'])
        self.assertEqual(state['virtual']['height'], state['physicalHeight'])
        self.assertTrue(state['physicalUnchanged'])

    def test_mode_bounds_pixels_and_appkit_are_isolated(self):
        state = self.probe('1920x1080')
        for key in ('width', 'modeWidth', 'pixelWidth', 'screenWidth'):
            self.assertEqual(state['virtual'][key], 1920, (key, state))
        for key in ('height', 'modeHeight', 'pixelHeight', 'screenHeight'):
            self.assertEqual(state['virtual'][key], 1080, (key, state))
        self.assertEqual(state['virtual']['modes'], 1)
        self.assertEqual(state['virtual']['scale'], 1)
        self.assertTrue(state['physicalUnchanged'])

    def test_invalid_configuration_is_passthrough(self):
        state = self.probe('1920x1080;bad')
        self.assertEqual(state['virtual']['width'], state['physicalWidth'])

    def test_native_fullscreen_space_preserves_real_display(self):
        state = self.probe('1920x1080', window=True)
        self.assertTrue(state['fullscreen'] and state['fullscreenInput'], state)
        self.assertTrue(state['presentationProtected'], state)
        self.assertTrue(state['dialogUnchanged'] and state['dialogClickable'], state)
        self.assertTrue(state['backgroundBlack'] and state['canvasBlack'], state)
        self.assertTrue(state['separatorHidden'] and state['titleHidden'], state)
        self.assertTrue(state['physicalUnchanged'], state)
        self.assertEqual(state['category'], 'public.app-category.games')
        self.assertGreaterEqual(state['canvasWidth'], 1920)
        self.assertGreaterEqual(state['canvasHeight'], 1080)

    def test_fullscreen_with_single_icon_client(self):
        state = self.probe('1920x1080', window=True, session=True)
        self.assertTrue(state['fullscreen'] and state['fullscreenInput'], state)
        self.assertTrue(state['presentationProtected'], state)
        self.assertTrue(state['dialogUnchanged'] and state['dialogClickable'], state)
        self.assertTrue(state['backgroundBlack'] and state['canvasBlack'], state)
        self.assertTrue(state['separatorHidden'] and state['titleHidden'], state)
        self.assertTrue(state['physicalUnchanged'], state)
        self.assertEqual(state['policy'], 1, 'The Wine client stays accessory while using a native Space')

    def test_input_at_2560_by_1600(self):
        state = self.probe('2560x1600', window=True)
        self.assertTrue(state['fullscreen'] and state['fullscreenInput'], state)
        self.assertTrue(state['presentationProtected'], state)
        self.assertTrue(state['dialogClickable'], state)

    def test_rendered_window_does_not_force_fullscreen(self):
        state = self.probe('1920x1080', window=True, stay_windowed=True)
        self.assertFalse(state['fullscreen'], state)
        self.assertTrue(state['gameWindowed'], state)
        self.assertFalse(state['presentationProtected'], state)

    def test_game_can_switch_to_windowed_mode(self):
        state = self.probe('1920x1080', window=True, game_windowed=True)
        self.assertTrue(state['gameWindowed'], state)
        self.assertFalse(state['presentationProtected'], state)
        self.assertFalse(state['fullscreen'], state)

    def test_exit_restores_window_chrome(self):
        state = self.probe('1920x1080', window=True, exit_space=True)
        self.assertFalse(state['fullscreen'], state)
        self.assertTrue(state['styleRestored'], state)
        self.assertTrue(state['dialogUnchanged'] and state['dialogClickable'], state)

if __name__ == '__main__':
    unittest.main()
