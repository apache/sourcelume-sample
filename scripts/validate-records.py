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

"""Validates the demo's records against the Sourcelume spec (JSON Schema +
SHACL), reusing the spec's own validator.

SOURCELUME_SPEC must point at a sourcelume-spec checkout that includes the
TrainingProvenanceRecord type — i.e. the model-usage-record branch (PR #10)
until it is merged into main. Defaults to the local worktree of that branch.
"""

import json
import os
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
SPEC = Path(os.environ.get("SOURCELUME_SPEC", "/private/tmp/wt-model")).resolve()
if not (SPEC / "tools" / "validate.py").is_file():
    print(f"SOURCELUME_SPEC is not a spec checkout: {SPEC}", file=sys.stderr)
    sys.exit(2)

sys.path.insert(0, str(SPEC / "tools"))
import validate as spec_validate  # noqa: E402

RECORDS = [
    BASE / "data" / "provenance-record.json",
    BASE / "model" / "provenance-record.json",
]


def main() -> int:
    # The SHACL shapes for all record types share one file in the spec.
    shapes_path = spec_validate.SCHEMA_DIR / "sourcelume.shacl.ttl"
    ok = True
    for record in RECORDS:
        if not record.is_file():
            print(f"SKIP {record.name}: not generated yet (run `make train` first)")
            continue
        record_type = json.loads(record.read_text()).get("type", "ProvenanceRecord")
        validator = spec_validate.load_validator(record_type)
        ok = spec_validate.validate_example(record, validator, shapes_path) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
