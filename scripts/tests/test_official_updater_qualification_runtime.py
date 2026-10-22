import importlib.util
import os
import pathlib
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / 'scripts/official-updater-qualification-runtime.py'
spec = importlib.util.spec_from_file_location('official_qualification_runtime', TOOL)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class QualificationRuntimeTests(unittest.TestCase):
    def test_exact_distinct_immutable_tuple_is_required(self):
        valid = {'source_sha': 'a'*40, 'dmg_sha256': 'b'*64, 'manifest_sha256': 'c'*64,
                 'feed_sha256': 'd'*64, 'bootstrap_release_id': '416881043', 'candidate_release_id': '416881044'}
        self.assertEqual(runtime.validate_inputs(valid), valid)
        for field, replacement in [('source_sha', 'main'), ('dmg_sha256', 'latest'),
                                   ('manifest_sha256', 'a'*63), ('feed_sha256', 'A'*64),
                                   ('candidate_release_id', '../releases/latest'),
                                   ('candidate_release_id', valid['bootstrap_release_id'])]:
            with self.subTest(field=field, replacement=replacement), self.assertRaises(ValueError):
                runtime.validate_inputs(dict(valid, **{field: replacement}))

    def test_entry_point_refuses_a_maintainer_host_before_any_preparation(self):
        work = pathlib.Path.home() / 'estrobo-qualification'
        existed = work.exists()
        result = subprocess.run([sys.executable, '-B', str(TOOL), 'prepare'],
                                env=dict(os.environ, GITHUB_ACTIONS='false'), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('disposable GitHub-hosted macOS user', result.stderr)
        self.assertEqual(work.exists(), existed)


if __name__ == '__main__':
    unittest.main()
