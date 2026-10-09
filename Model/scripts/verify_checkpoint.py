"""Verify a trusted, user-supplied checkpoint without training or downloading weights."""
import argparse
import hashlib
import json
from pathlib import Path


def verify(path, args_path=None, scores_path=None, run_identity=None):
    import torch
    import ultralytics
    from ultralytics import YOLO
    path = Path(path)
    if not path.is_file():
        raise ValueError('checkpoint must already exist locally')
    model = YOLO(str(path))  # PyTorch checkpoints must come from a trusted owner.
    names = {str(k): v for k, v in model.names.items()}
    if model.task != 'obb' or names != {'0': 'CFCBK', '1': 'FCBK', '2': 'Zigzag'}:
        raise ValueError('expected kiln-trained OBB classes, not generic pretrained weights')
    args = model.ckpt.get('train_args', {})
    if args.get('mode') != 'train' or not args.get('data'):
        raise ValueError('missing training metadata')
    manifest = {
        'schema_version': 1, 'artifact': path.name,
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size,
        'task': model.task, 'classes': names,
        'model_version': f"{args.get('name', 'unknown')}:{hashlib.sha256(path.read_bytes()).hexdigest()[:12]}",
        'checkpoint_ultralytics': model.ckpt.get('version'),
        'checkpoint_saved_at': model.ckpt.get('date'),
        'loader_ultralytics': ultralytics.__version__, 'loader_torch': torch.__version__,
        'training': {k: args.get(k) for k in ('model', 'name', 'epochs', 'imgsz', 'batch', 'fraction')},
        'checkpoint_epoch': model.ckpt.get('epoch'),
        'limitations': ['Stripped epoch=-1 does not establish completed epoch count.',
                         'External args.yaml, scores.json and saved-run/version are on the ML team mate laptop; linkage unverified.',
                         'Type predictions remain unverified regardless of class score.'],
        'external_run_identity': None, 'external_scores_sha256': None,
    }
    manifest['external_run_identity'] = run_identity
    if args_path:
        import yaml
        supplied = yaml.safe_load(Path(args_path).read_text())
        for k in ('model','name','epochs','imgsz','batch','fraction'):
            if supplied[k] != manifest['training'][k]: raise ValueError('args configuration mismatch: '+k)
        manifest['supplied_args_sha256'] = hashlib.sha256(Path(args_path).read_bytes()).hexdigest()
        manifest['supplied_save_dir'] = supplied.get('save_dir')
        manifest['supplied_metadata_config_matches'] = True
        manifest['limitations'].append('args stores optimizer=auto and warmup_bias_lr=0.1; checkpoint stores resolved MuSGD and OBB-adjusted 0.0.')
    if scores_path:
        supplied = json.loads(Path(scores_path).read_text())
        for k in ('model','epochs','imgsz','batch','fraction'):
            if supplied[k] != manifest['training'][k]: raise ValueError('scores configuration mismatch: '+k)
        manifest['supplied_scores_sha256'] = hashlib.sha256(Path(scores_path).read_bytes()).hexdigest()
        baseline = Path(__file__).resolve().parents[1]/'results'/'baseline_scores.json'
        manifest['supplied_scores_match_checked_in_baseline'] = supplied == json.loads(baseline.read_text())
    if args_path and scores_path:
        manifest['limitations'] = [v for v in manifest['limitations'] if not v.startswith('External args')]
        manifest['limitations'].append('Saved Kaggle version/run identity missing; external scores have no weights checksum.' if not run_identity else 'External scores match configuration but have no weights checksum.')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('weights', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--args', type=Path)
    parser.add_argument('--scores', type=Path)
    parser.add_argument('--run-identity')
    args = parser.parse_args()
    manifest = verify(args.weights, args.args, args.scores, args.run_identity)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))
