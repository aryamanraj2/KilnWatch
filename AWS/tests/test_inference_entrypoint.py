"""Prompt 38 detector entrypoint: fake S3 and a fake detector only, no network or model load."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('entrypoint', Path(__file__).resolve().parents[1]/'inference'/'entrypoint.py')
entrypoint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(entrypoint)

SCENE = 'S2B_T43RGM_20261005T053448_L2A'
ENV = {'DATA_BUCKET': 'bucket', 'MODEL_S3_PREFIX': 'models/', 'OUTPUT_S3_PREFIX': 'detections/'}
WEIGHTS = b'not really a checkpoint'


class FakeS3:
    def __init__(self, objects):
        self.objects, self.written = objects, {}

    def download_file(self, bucket, key, path):
        Path(path).write_bytes(self.objects[key])

    def upload_file(self, path, bucket, key, ExtraArgs=None):
        self.written[key] = Path(path).read_bytes()

    def put_object(self, Bucket, Key, Body, ContentType):
        self.written[Key] = Body


def fake_detect(cmd, check):
    out = Path(cmd[cmd.index('--out') + 1])
    out.write_text(json.dumps({'type': 'FeatureCollection',
        'features': [{'properties': {'type': 'FCBK'}}, {'properties': {'type': 'FCBK'}}, {'properties': {'type': 'CFCBK'}}],
        'kilnwatch': {'scenes': [{'id': SCENE}], 'model_version': 'baseline:x', 'params': {'conf': 0.25},
                      'created': '2026-10-11T00:00:00+00:00'}}))


def failing_detect(cmd, check):
    raise subprocess.CalledProcessError(1, cmd)


class EntrypointTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.pinned = Path(self.tmp.name)/'pinned.json'
        self.pinned.write_text(json.dumps({'sha256': hashlib.sha256(WEIGHTS).hexdigest()}))
        self.old_pinned, entrypoint.PINNED_MANIFEST = entrypoint.PINNED_MANIFEST, self.pinned

    def tearDown(self):
        entrypoint.PINNED_MANIFEST = self.old_pinned
        self.tmp.cleanup()

    def s3(self, weights=WEIGHTS, manifest_sha=None):
        sha = manifest_sha or hashlib.sha256(WEIGHTS).hexdigest()
        return FakeS3({'models/best.pt': weights, 'models/checkpoint-manifest.json': json.dumps({'sha256': sha}).encode()})

    def test_rejects_bad_arguments(self):
        for argv in ([], ['--scene', SCENE], ['--scene', 'S2B; rm -rf /', '--run-id', 'm0'],
                     ['--scene', SCENE, '--run-id', '../m0'], ['--scene', SCENE, '--run-id', 'M0'],
                     ['--scene', SCENE, '--run-id', 'm0', '--weights', 'x.pt']):
            with self.assertRaises(SystemExit) as e:
                entrypoint.parse(argv)
            self.assertNotEqual(e.exception.code, 0)

    def test_requires_relative_prefixes(self):
        with self.assertRaises(SystemExit):
            entrypoint.settings({**ENV, 'OUTPUT_S3_PREFIX': ''})
        with self.assertRaises(SystemExit):
            entrypoint.settings({**ENV, 'OUTPUT_S3_PREFIX': '/detections'})

    def test_key_layout(self):
        self.assertEqual(entrypoint.keys('models/', 'detections/', 'm0-after'), {
            'weights': 'models/best.pt', 'manifest': 'models/checkpoint-manifest.json',
            'geojson': 'detections/m0-after/kilns.geojson', 'run': 'detections/m0-after/run.json'})

    def test_refuses_mismatched_weights_or_manifest(self):
        for s3 in (self.s3(weights=b'tampered'), self.s3(manifest_sha='0'*64)):
            with self.assertRaises(SystemExit) as e:
                entrypoint.run(['--scene', SCENE, '--run-id', 'm0'], ENV, s3, fake_detect)
            self.assertIn('refusing', str(e.exception.code))
            self.assertEqual(s3.written, {})

    def test_writes_only_detections(self):
        s3 = self.s3()
        self.assertEqual(entrypoint.run(['--scene', SCENE, '--run-id', 'm0-after'], ENV, s3, fake_detect), 0)
        self.assertEqual(sorted(s3.written), ['detections/m0-after/kilns.geojson', 'detections/m0-after/run.json'])
        record = json.loads(s3.written['detections/m0-after/run.json'])
        self.assertEqual((record['candidates'], record['by_type']), (3, {'FCBK': 2, 'CFCBK': 1}))
        self.assertEqual(record['model_sha256'], hashlib.sha256(WEIGHTS).hexdigest())
        self.assertEqual(record['registry_input_sha256'],
                         hashlib.sha256(s3.written['detections/m0-after/kilns.geojson']).hexdigest())

    def test_detector_failure_exits_non_zero_without_writes(self):
        s3 = self.s3()
        original = entrypoint.run
        entrypoint.run = lambda argv: original(argv, ENV, s3, failing_detect)
        try:
            self.assertEqual(entrypoint.main(['--scene', SCENE, '--run-id', 'm0']), 1)
        finally:
            entrypoint.run = original
        self.assertEqual(s3.written, {})

    def test_detector_gets_local_run_settings(self):
        seen = []
        entrypoint.run(['--scene', SCENE, '--run-id', 'm0'], ENV, self.s3(), lambda cmd, check: (seen.append(cmd), fake_detect(cmd, check)))
        cmd = seen[0]
        for flag, value in (('--conf', '0.25'), ('--iou', '0.3'), ('--ios', '0.6'), ('--aoi', 'hapur_test'), ('--scene', SCENE)):
            self.assertEqual(cmd[cmd.index(flag) + 1], value)


if __name__ == '__main__':
    unittest.main()
