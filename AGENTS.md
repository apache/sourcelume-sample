<!-- SPDX-License-Identifier: Apache-2.0
     https://www.apache.org/licenses/LICENSE-2.0 -->

# AGENTS.md

Guidance for AI coding agents (and the humans running them) working in
this repository. This is the place to record conventions any harness —
Claude Code, Cursor, Copilot, Junie, Codex, a local `pi` setup, whatever
comes next — is expected to follow here. When in doubt, follow the
Apache Sourcelume project conventions over any default the harness
suggests.

## Project overview

This repository, `apache/sourcelume-sample`, is the **Apache Sourcelume**
end-to-end sample: a tiny char-level model trained on a bundled
public-domain corpus (Project Gutenberg's *Alice's Adventures in
Wonderland*, 1865) with the full provenance chain emitted as Sourcelume
records. It demonstrates the two-layer story: a dataset record
(`ProvenanceRecord`) authored for the corpus, and a model record
(`TrainingProvenanceRecord`) born from an actual training run.

The sample is deliberately honest about what works today and what does
not: see the "What works today" table in `README.md` before making
claims on behalf of the demo. The model is unsigned and the records
carry producer claims only — no certification semantics.

This repo is pure Python (`uv`); there is no Maven build here.

## Build and test commands

- `uv sync --group validate` — install runtime and validation
  dependencies (numpy, jsonschema, pyshacl, pyld).
- `uv run python src/train.py` — train the tiny model; on success it
  writes `model/provenance-record.json` (born from this run, not
  hand-authored).
- `SOURCELUME_SPEC=/path/to/sourcelume-spec uv run python
  scripts/validate-records.py` — validate both records against the
  spec's JSON Schema and SHACL shapes. This is the real gate.
- `make demo` — the five-step local story (train, records, validation).
  `make demo-atlas` adds the optional registry/Atlas round-trip.

Run the trainer and record validation before opening or updating a PR.
A green `validate-records.py` is the local bar.

## Vocabulary

All records in this repo follow the Sourcelume metadata specification
(`apache/sourcelume-spec`). Reuse existing standard terms wherever an
equivalent exists (`dct:`, `schema:`, `spdx:`) rather than inventing
Sourcelume-native terms; the `sourcelume:` namespace stays minimal.

## Commit messages and AI attribution

This is the part every harness must get right. Apache Sourcelume follows
the ASF generative-tooling guidance and the draft convention documented at
<https://rai.apache.org/commit-messages.html>. The established, in-repo
practice (see existing commits by `jgoodyear`) is a three-line trailer
block at the end of the commit message body:

```
Apache-ai: Yes
Generated-by: <tool> (<model>)
Reviewed-by: <human>
```

For example:

```
Apache-ai: Yes
Generated-by: Claude Code (Sonnet 5)
Reviewed-by: anierbeck
```

Rules:

- **`Generated-by:`** — required when an AI tool produced the code, even
  if a human reviewed and edited it. Name the actual tool and model
  (e.g. `Claude Code (Sonnet 5)`, `PyCharm AI Assistant (Claude 4.5 Sonnet)`,
  `Webstorm Junie (Gemini 3 Flash)`), not a generic label.
- **`Assisted-by:`** — use this instead of `Generated-by:` only when the
  human wrote the code and the AI helped in small ways. They are not
  the same action: *Generated* = AI produced, human reviewed; *Assisted* =
  human produced, AI helped. Pick the one that matches what actually
  happened.
- **`Apache-ai: Yes`** — include alongside `Generated-by:` / `Assisted-by:`
  when AI played a significant role, for policy transparency.
- **`Reviewed-by:`** — the human who reviewed the change.
- **`Co-authored-by:`** is for humans only, never for an AI tool.
- The commit message is the committer's representation. Even when AI
  generated the code, the committer is responsible for what's committed.

## Pull requests

- This repository is dual-hosted: authoritative history is on
  `gitbox.apache.org`, mirrored to/from GitHub. Contribute via a GitHub
  pull request against `main` (fork, branch, PR). `main` is treated as
  protected; do not push directly to it.
- Non-trivial or cross-cutting changes are normally discussed on the
  dev list first (`dev@sourcelume.apache.org`,
  [archives](https://lists.apache.org/list.html?dev@sourcelume.apache.org)),
  not just via PR. When a discussion has happened on-list, reference it in
  the PR description.
- Apache License 2.0 applies; preserve `LICENSE` and `NOTICE`. There is
  no Maven/RAT run here — add the ASF header to new code files
  (`.py`, `Makefile`, workflow YAML) by convention; data files
  (`data/`) and records are exempt.
- Run the trainer and `scripts/validate-records.py` before pushing.
