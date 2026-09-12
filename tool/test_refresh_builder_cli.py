"""CLI path checks use temporary sentinels, never generate or fake media."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('build_288_refresh_preview.py')


class RefreshBuilderCliTest(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                              capture_output=True, text=True, encoding='utf-8')

    def test_help_without_optional_render_dependencies(self):
        result = self.run_cli('--help')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--source-video-2', result.stdout)
        self.assertIn('--output-dir', result.stdout)

    def test_missing_input_fails_before_output_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_cli('--source-video', root/'missing-1.mp4',
                                  '--source-video-2', root/'missing-2.mp4',
                                  '--output-dir', root/'output', '--check-inputs')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Missing input', result.stderr)
            self.assertFalse((root/'output').exists())

    def test_input_check_hashes_all_inputs_without_rendering_or_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = ['shoujo_bird_human_performance_00_25.png',
                     'shoujo_bird_closure_08_reworked.png',
                     'shoujo_bird_wing_unfold_00_04.png', 'one.mp4', 'two.mp4']
            for name in names:
                (root/name).write_bytes(b'path-validation-only')
            result = self.run_cli('--asset-root', root, '--source-video', root/'one.mp4',
                                  '--source-video-2', root/'two.mp4',
                                  '--output-dir', root/'output', '--check-inputs')
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(len(report['inputs']), 5)
            self.assertEqual(report['media_decode_verified'], False)
            self.assertTrue(all(len(item['sha256']) == 64 for item in report['inputs']))
            self.assertFalse((root/'output').exists())


if __name__ == '__main__':
    unittest.main()
