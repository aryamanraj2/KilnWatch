"""E1 merge of per-index evidence manifests: synthetic folders only, no network or imagery reads."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('prepare_all_evidence', Path(__file__).resolve().parents[1]/'scripts'/'prepare_all_evidence.py')
prepare_all = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare_all)


def part(root, index, observation, input_sha='a'*64, before=True):
    folder = root/str(index); folder.mkdir()
    sides = {}
    for side in ('before', 'after'):
        if side == 'before' and not before:
            sides[side] = None; continue
        name = f'{side}{index}.png'
        (folder/name).write_bytes(b'png '+name.encode())
        sides[side] = {'local_path': name, 'sha256': side+str(index)}
    (folder/'manifest.json').write_text(json.dumps({'schema_version': 1, 'input_sha256': input_sha,
        'publication_state': 'local_unpublished', 'entries': [{'observation_id': observation, 'model_sha256': 'm', **sides}]}))
    return index, folder


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.out = self.root/'out'

    def tearDown(self):
        self.tmp.cleanup()

    def test_merges_relative_paths_and_carries_input_hash(self):
        # Index 1 stands for a kiln the preparer skipped: it never reaches merge.
        manifest = prepare_all.merge([part(self.root, 0, 'o0'), part(self.root, 2, 'o2', before=False)], self.out)
        self.assertEqual(manifest['input_sha256'], 'a'*64)
        self.assertEqual(manifest['publication_state'], 'local_unpublished')
        self.assertEqual([e['observation_id'] for e in manifest['entries']], ['o0', 'o2'])
        self.assertIsNone(manifest['entries'][1]['before'])
        for entry in manifest['entries']:
            for meta in filter(None, (entry['before'], entry['after'])):
                self.assertEqual(Path(meta['local_path']).name, meta['local_path'])
                self.assertTrue((self.out/meta['local_path']).is_file())

    def test_rejects_duplicate_observation(self):
        with self.assertRaisesRegex(ValueError, 'duplicate observation'):
            prepare_all.merge([part(self.root, 0, 'o0'), part(self.root, 1, 'o0')], self.out)

    def test_rejects_mixed_detection_exports(self):
        with self.assertRaisesRegex(ValueError, 'different detection export'):
            prepare_all.merge([part(self.root, 0, 'o0'), part(self.root, 1, 'o1', input_sha='b'*64)], self.out)

    def test_skipped_kiln_is_listed_with_reason(self):
        class Args: detections = scenes = Path('x'); before_scene = None; district = 'Hapur'
        refused = type('R', (), {'returncode': 1, 'stderr': 'Traceback\nValueError: patch nodata 0.020 exceeds 1%\n'})()
        prepare_all.subprocess.run, original = (lambda *a, **k: refused), prepare_all.subprocess.run
        try:
            with self.assertRaisesRegex(RuntimeError, 'patch nodata 0.020 exceeds 1%'):
                prepare_all.cut(3, Args, self.root)
        finally:
            prepare_all.subprocess.run = original


if __name__ == '__main__':
    unittest.main()
