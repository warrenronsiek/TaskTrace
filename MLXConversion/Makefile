VENV_DIR := $(shell if [ -d .venv ]; then echo .venv; elif [ -d venv ]; then echo venv; else echo .venv; fi)
PYTHON := $(VENV_DIR)/bin/python
PIP := $(PYTHON) -m pip

.PHONY: venv install convert-embedding convert-reranker smoke-embedding smoke-reranker vendor-text vendor-visual

venv:
	python3 -m venv venv

install:
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt

convert-embedding:
	./scripts/convert_embedding.sh

convert-reranker:
	./scripts/convert_reranker.sh

smoke-embedding:
	$(PYTHON) ./scripts/smoke_test_embedding.py

smoke-reranker:
	$(PYTHON) ./scripts/smoke_test_reranker.py

vendor-text:
	./scripts/vendor_text_model.sh

vendor-visual:
	./scripts/vendor_visual_model.sh
