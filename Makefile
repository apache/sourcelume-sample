# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SHELL := /bin/bash

# Local configuration (override on the command line as needed)
PLUGIN_DIR     ?= ../sourcelume-tooling/plugins/sourcelume-python-plugin
SOURCELUME_SPEC ?= /private/tmp/wt-model
REGISTRY_DIR   ?= ../sourcelume-registry/sourcelume-registry-runtime-quarkus
REGISTRY       ?= http://localhost:8082
REGISTRY_LOG   ?= /tmp/e2e-registry.log

.PHONY: setup train validate-records registry-up registry-down registry-validate \
        demo demo-atlas query clean

setup:
	uv sync --group validate

train:
	uv run python src/train.py

# Spec-side validation (JSON Schema + SHACL), reusing the spec's own validator.
# Needs SOURCELUME_SPEC at the model-usage-record (PR #10) state or later.
validate-records:
	SOURCELUME_SPEC=$(SOURCELUME_SPEC) uv run python scripts/validate-records.py

registry-up:
	@( cd $(REGISTRY_DIR) && \
	   SOURCELUME_ATLAS_URL=http://localhost:21000 \
	   SOURCELUME_ATLAS_USER=admin \
	   SOURCELUME_ATLAS_PASSWORD='atlasR0cks!' \
	   JENV_VERSION=21 nohup java -jar target/quarkus-app/quarkus-run.jar </dev/null >$(REGISTRY_LOG) 2>&1 & disown )
	@for i in $$(seq 1 60); do \
		curl -sf $(REGISTRY)/q/health/live >/dev/null 2>&1 && echo "registry up ($(REGISTRY))" && exit 0; \
		sleep 2; \
	done; echo "registry did not come up (log: $(REGISTRY_LOG))"; exit 1

registry-down:
	@pkill -f quarkus-run.jar 2>/dev/null || true; echo "registry down"

# Validate both records against the running registry.
# The registry knows TrainingProvenanceRecord since sourcelume-registry#15,
# but the model record still fails here: the Python plugin models only
# ProvenanceRecord and rejects it client-side (tooling follow-up).
registry-validate:
	@echo "--- dataset record (ProvenanceRecord) ---"
	uv run --project $(PLUGIN_DIR) sourcelume validate data -u $(REGISTRY)
	@echo "--- model record (TrainingProvenanceRecord) ---"
	@uv run --project $(PLUGIN_DIR) sourcelume validate model -u $(REGISTRY) \
		|| echo ">>> expected failure: the Python plugin does not model TrainingProvenanceRecord yet (tooling follow-up)"

# Publish both records. Requires the Atlas stack (sourcelume-registry
# dev-support) — see make demo-atlas.
publish:
	@echo "--- publishing dataset record ---"
	uv run --project $(PLUGIN_DIR) sourcelume publish data -u $(REGISTRY)
	@echo "--- publishing model record ---"
	@uv run --project $(PLUGIN_DIR) sourcelume publish model -u $(REGISTRY) \
		|| echo ">>> expected failure: the Python plugin does not model TrainingProvenanceRecord yet (tooling follow-up)"

query:
	@echo "--- GET /records/{id} (dataset record; id = URL-encoded record IRI) ---"
	@curl -sf "$(REGISTRY)/records/$$(python3 -c 'import urllib.parse; print(urllib.parse.quote("https://sourcelume.apache.org/records/sample/gutenberg-alice-1865", safe=""))' 2>/dev/null || echo 'https%3A%2F%2Fsourcelume.apache.org%2Frecords%2Fsample%2Fgutenberg-alice-1865')"; echo
	@echo
	@echo "--- GET /records/{id} (model record; the registry resolves each trainingData"
	@echo "    reference to the dataset record's CURRENT status at read time) ---"
	@curl -sf "$(REGISTRY)/records/$$(python3 -c 'import urllib.parse; print(urllib.parse.quote("https://sourcelume.apache.org/records/sample/tiny-lm-v1", safe=""))' 2>/dev/null || echo 'https%3A%2F%2Fsourcelume.apache.org%2Frecords%2Fsample%2Ftiny-lm-v1')" \
		|| { echo ">>> no model record under that id yet: the Python plugin cannot publish"; \
		echo "    TrainingProvenanceRecord client-side (see the README table). Publish it directly:"; \
		echo "    curl -X POST -H 'Content-Type: application/json' --data-binary @model/provenance-record.json $(REGISTRY)/records"; }

# Full demo, stage 1: everything that works without Atlas.
demo: setup train validate-records registry-up registry-validate
	@echo
	@echo "Stage 1 complete. For the full publish loop run the Atlas stack"
	@echo "(sourcelume-registry/dev-support) and then: make demo-atlas"

# Full demo, stage 2: with Atlas, publishes everything it can.
demo-atlas: setup train validate-records registry-up registry-validate publish query
	@echo
	@echo "Stage 2 complete. Browse the Atlas UI at http://localhost:21000"
	@echo "(admin / atlasR0cks!), search type sourcelume_dataset."
