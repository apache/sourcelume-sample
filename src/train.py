#!/usr/bin/env python3
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Trains a tiny char-level language model on the bundled public-domain
corpus and emits the Sourcelume records for the run.

Outputs (all under model/):
  - training-run.json          the honest training summary (real numbers)
  - provenance-record.json     a TrainingProvenanceRecord filled from the run
  - tiny-lm-v1.npz             the model weights

The record's numbers come from THIS run — that is the demo's whole point:
the record is born from the training, not authored by hand.
"""

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

BASE = Path(__file__).resolve().parent.parent
DATA = BASE / "data"
MODEL = BASE / "model"
CORPUS = DATA / "corpus" / "alice-in-wonderland-1865.txt"

DATASET_ID = "https://sourcelume.apache.org/records/sample/gutenberg-alice-1865"
MODEL_ID = "https://sourcelume.apache.org/records/sample/tiny-lm-v1"


def train(text: str, chars: int, epochs: int, window: int, hidden: int,
          batch: int, lr: float, seed: int):
    slice_ = text[:chars]
    vocab = sorted(set(slice_))
    v = len(vocab)
    char_index = {c: i for i, c in enumerate(vocab)}
    encoded = np.array([char_index[c] for c in slice_], dtype=np.int64)

    rng = np.random.default_rng(seed)
    w1 = rng.normal(0, 0.1, (window * v, hidden))
    b1 = np.zeros(hidden)
    w2 = rng.normal(0, 0.1, (hidden, v))
    b2 = np.zeros(v)

    positions = np.arange(len(encoded) - window)
    history = []
    for epoch in range(epochs):
        rng.shuffle(positions)
        losses = []
        for start in range(0, len(positions) - batch + 1, batch):
            idx = positions[start:start + batch]
            x = np.zeros((batch, window * v))
            for k in range(window):
                x[np.arange(batch), k * v + encoded[idx + k]] = 1.0
            y = encoded[idx + window]

            h = np.tanh(x @ w1 + b1)
            z = h @ w2 + b2
            z -= z.max(axis=1, keepdims=True)
            p = np.exp(z)
            p /= p.sum(axis=1, keepdims=True)
            losses.append(-np.log(p[np.arange(batch), y]).mean())

            dz = p
            dz[np.arange(batch), y] -= 1.0
            dz /= batch
            dw2 = h.T @ dz
            db2 = dz.sum(axis=0)
            dh = (dz @ w2.T) * (1 - h * h)
            dw1 = x.T @ dh
            db1 = dh.sum(axis=0)
            w1 -= lr * dw1
            b1 -= lr * db1
            w2 -= lr * dw2
            b2 -= lr * db2
        history.append(float(np.mean(losses)))
        print(f"epoch {epoch + 1}/{epochs}: loss {history[-1]:.4f}")

    params = w1.size + b1.size + w2.size + b2.size
    return slice_, vocab, history, params, (w1, b1, w2, b2)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--chars", type=int, default=60_000)
    parser.add_argument("--window", type=int, default=8)
    parser.add_argument("--hidden", type=int, default=96)
    parser.add_argument("--batch", type=int, default=64)
    parser.add_argument("--lr", type=float, default=0.15)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    text = CORPUS.read_text(encoding="utf-8")
    if args.chars > len(text):
        print(f"corpus has only {len(text)} chars; using all of them")
        args.chars = len(text)

    slice_, vocab, history, params, weights = train(
        text, args.chars, args.epochs, args.window, args.hidden,
        args.batch, args.lr, args.seed)

    ran_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    MODEL.mkdir(exist_ok=True)

    # Tokens follow the Mímir convention: per epoch. One token = one character.
    tokens_per_epoch = len(slice_)
    run = {
        "dataset": DATASET_ID,
        "ranAt": ran_at,
        "epochs": args.epochs,
        "tokensPerEpoch": tokens_per_epoch,
        "window": args.window,
        "hidden": args.hidden,
        "vocabSize": len(vocab),
        "parameters": int(params),
        "lossHistory": history,
        "finalLoss": history[-1],
        "modelFile": "model/tiny-lm-v1.npz",
    }
    (MODEL / "training-run.json").write_text(json.dumps(run, indent=2) + "\n")
    np.savez_compressed(MODEL / "tiny-lm-v1.npz", *weights)

    record = {
        "@context": "https://sourcelume.apache.org/context/0.0.1/sourcelume.jsonld",
        "id": MODEL_ID,
        "type": "TrainingProvenanceRecord",
        "identifier": "tiny-lm",
        "name": "Tiny char-LM (Apache Sourcelume training demo)",
        "version": "v1",
        "creator": [
            {
                "type": "schema:Organization",
                "name": "Apache Sourcelume training demo",
                "role": "originator"
            }
        ],
        "created": ran_at,
        "disclosure": "complete",
        "trainingData": [
            {
                "dataset": DATASET_ID,
                "phase": "pretraining",
                "tokens": tokens_per_epoch,
                "share": 1.0
            }
        ],
        "note": (
            f"Generated by src/train.py in apache/sourcelume-sample from a real "
            f"run on {ran_at} — an illustrative demo model, not a published model. "
            f"Character-level tokens: one token = one character; tokens are per epoch, "
            f"and this run trained for {args.epochs} epochs over a "
            f"{tokens_per_epoch}-character slice of the referenced corpus "
            f"({len(vocab)}-character vocabulary, {params} parameters, "
            f"final loss {history[-1]:.4f}, see model/training-run.json). "
            f"The referenced dataset record is published by this demo itself "
            f"(data/provenance-record.json). Unsigned producer claim — see README."
        ),
    }
    (MODEL / "provenance-record.json").write_text(json.dumps(record, indent=2) + "\n")

    print()
    print(f"dataset record : {DATA / 'provenance-record.json'} (authored, static)")
    print(f"training run   : {MODEL / 'training-run.json'}")
    print(f"model record   : {MODEL / 'provenance-record.json'} (born from this run)")
    print(f"weights        : {MODEL / 'tiny-lm-v1.npz'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
