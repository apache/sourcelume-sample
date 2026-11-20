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
REGISTRY_DIR   ?= ../sourcelume-registry/sourcelume-registry-distribution-atlas
REGISTRY_PG_DIR ?= ../sourcelume-registry/sourcelume-registry-distribution-postgres
REGISTRY_PG_DB ?= ../sourcelume-registry/dev-support/docker-compose.postgres.yml
REGISTRY       ?= http://localhost:8082
REGISTRY_LOG   ?= /tmp/e2e-registry.log

.PHONY: setup train validate-records registry-up registry-up-postgres registry-down \
        registry-validate demo demo-postgres demo-atlas query clean

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

# Start the default PostgreSQL distribution: the dev-support PostgreSQL
# container plus the sourcelume-registry-distribution-postgres jar.
registry-up-postgres:
	@docker compose -f $(REGISTRY_PG_DB) up -d --wait
	@( cd $(REGISTRY_PG_DIR) && \
	   SOURCELUME_POSTGRES_JDBC_URL=jdbc:postgresql://localhost:55432/sourcelume_registry \
	   SOURCELUME_POSTGRES_USERNAME=sourcelume \
	   SOURCELUME_POSTGRES_PASSWORD=sourcelume \
	   JENV_VERSION=21 nohup java -jar target/quarkus-app/quarkus-run.jar </dev/null >$(REGISTRY_LOG) 2>&1 & disown )
	@for i in $$(seq 1 60); do \
		curl -sf $(REGISTRY)/q/health/live >/dev/null 2>&1 && echo "registry up ($(REGISTRY))" && exit 0; \
		sleep 2; \
	done; echo "registry did not come up (log: $(REGISTRY_LOG))"; exit 1

registry-down:
	@pkill -f quarkus-run.jar 2>/dev/null || true
	@docker compose -f $(REGISTRY_PG_DB) down >/dev/null 2>&1 || true
	@echo "registry down"

# Validate both records against the running registry.
registry-validate:
	@echo "--- dataset record (ProvenanceRecord) ---"
	uv run --project $(PLUGIN_DIR) sourcelume validate data -u $(REGISTRY)
	@echo "--- model record (TrainingProvenanceRecord) ---"
	uv run --project $(PLUGIN_DIR) sourcelume validate model -u $(REGISTRY)

# Publish both records. Requires a storage backend: the dev-support
# PostgreSQL instance (make demo-postgres) or the Atlas stack
# (make demo-atlas).
publish:
	@echo "--- publishing dataset record ---"
	uv run --project $(PLUGIN_DIR) sourcelume publish data -u $(REGISTRY)
	@echo "--- publishing model record ---"
	uv run --project $(PLUGIN_DIR) sourcelume publish model -u $(REGISTRY)

query:
	@echo "--- GET /records/{id} (dataset record; id = URL-encoded record IRI) ---"
	@curl -sf "$(REGISTRY)/records/$$(python3 -c 'import urllib.parse; print(urllib.parse.quote("https://sourcelume.apache.org/records/sample/gutenberg-alice-1865", safe=""))' 2>/dev/null || echo 'https%3A%2F%2Fsourcelume.apache.org%2Frecords%2Fsample%2Fgutenberg-alice-1865')"; echo
	@echo
	@echo "--- GET /records/{id} (model record; the registry resolves each trainingData"
	@echo "    reference to the dataset record's CURRENT status at read time) ---"
	@curl -sf "$(REGISTRY)/records/$$(python3 -c 'import urllib.parse; print(urllib.parse.quote("https://sourcelume.apache.org/records/sample/tiny-lm-v1", safe=""))' 2>/dev/null || echo 'https%3A%2F%2Fsourcelume.apache.org%2Frecords%2Fsample%2Ftiny-lm-v1')" \
		|| echo ">>> no model record under that id yet: run make publish first"

# Full demo, stage 1: everything that works without a storage backend.
demo: setup train validate-records registry-up registry-validate
	@echo
	@echo "Stage 1 complete. For the full publish loop run make demo-postgres"
	@echo "(default PostgreSQL distribution, Docker only) or make demo-atlas"
	@echo "(Atlas stack via sourcelume-registry/dev-support)."

# Full demo on the default backend: the PostgreSQL distribution — Docker only,
# no Atlas stack.
demo-postgres: setup train validate-records registry-up-postgres registry-validate publish query
	@echo
	@echo "Demo complete on the PostgreSQL distribution. Browse the records with"
	@echo "make query, then make registry-down."

# Full demo, stage 2: with Atlas, publishes everything it can.
demo-atlas: setup train validate-records registry-up registry-validate publish query
	@echo
	@echo "Stage 2 complete. Browse the Atlas UI at http://localhost:21000"
	@echo "(admin / atlasR0cks!), search type sourcelume_dataset."
