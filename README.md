<!--
  Licensed to the Apache Software Foundation (ASF) under one
  or more contributor license agreements.  See the NOTICE file
  distributed with this work for additional information regarding
  copyright ownership.  The ASF licenses this file to You under the
  Apache License, Version 2.0 (the "License"); you may not use this
  file except in compliance with the License.  You may obtain a copy
  of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
-->

# Apache Sourcelume Sample

**Tiny model, full provenance.** This repo trains a char-level language model
(so small it trains in seconds on a laptop CPU) and walks the complete
Sourcelume loop: dataset record → training → `TrainingProvenanceRecord` →
registry → query.

The point of the demo: the training record is **born from the training run**
with real token counts from `model/training-run.json` — not authored by hand.
A provenance record that says "model X was trained on dataset Y" is only
interesting if you can watch it happen.

## The five steps

```
git clone https://github.com/apache/sourcelume-sample && cd sourcelume-sample
make demo
```

1. **Dataset record** — `data/provenance-record.json` describes the bundled
   public-domain corpus (Alice's Adventures in Wonderland, 1865, Project
   Gutenberg ebook #11). The demo publishes this record itself: it bootstraps
   its own preconditions instead of assuming records it did not create.
2. **Train** — `src/train.py` trains a tiny char-level MLP (numpy only, no
   torch, no GPU) on the corpus and writes `model/training-run.json` with the
   honest numbers of the run.
3. **Record** — the trainer fills `model/provenance-record.json`: a
   `TrainingProvenanceRecord` referencing the dataset record by canonical
   record IRI, with tokens (characters per epoch) and `share: 1.0` from the
   actual run.
4. **Validate** — both records are validated twice: against the spec (JSON
   Schema + SHACL) and against the registry's `/records/validate` endpoint.
5. **Publish + query** — with the Atlas stack up, records are published via
   the Python plugin; `GET /records/{id}` and the Atlas UI show the result.

## Prerequisites

- Python 3.11+ and [uv](https://docs.astral.sh/uv/)
- For the registry steps: a local Sourcelume Registry
  (see `sourcelume-registry/dev-support`, port 8082)
- For publishing: the Atlas stack (`make demo-atlas`)

## What works today, and what deliberately does not

| Step | State |
|---|---|
| Dataset record: spec + registry validation | ✅ works today |
| Dataset record: publish to Atlas | ✅ works with the Atlas stack up |
| Training record: spec validation | ✅ works — validate against a `sourcelume-spec` checkout at `main` (the `TrainingProvenanceRecord` type was merged with PR #10); set `SOURCELUME_SPEC` accordingly |
| Training record: plugin validate/publish | ❌ **expected to fail** — the Python plugin itself only models `ProvenanceRecord` (its Pydantic model rejects the record client-side). The plugin needs the same type-dispatch the spec validator has (tooling follow-up; see `make registry-validate`). |
| Training record: registry validate/publish | ❌ **expected to fail** until the registry learns the `TrainingProvenanceRecord` type (registry follow-up to PR #10, currently in review as sourcelume-registry#15). Direct `curl -X POST .../records/validate` shows the registry's own rejection (HTTP 422, `must be the constant value 'ProvenanceRecord'`) — the demo's exhibit for that follow-up. |

This demo **builds on PR #10 as given**: the training record type, the
type-dispatching validator and the record examples come from that branch.

## Honesty notes

- The demo record is **unsigned** (Sourcelume Attest is still a discussion).
- It is a **producer's own claim** — no certification, no adjudication, no
  "approved" flag anywhere.
- `disclosure: complete` is only honest because the demo *knows* its data.
  Realistic partial/undisclosed cases are covered by the spec examples.
- One token = one character (char-level model); `tokens` are per epoch,
  following the Mímir Table-10 convention.
