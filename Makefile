.RECIPEPREFIX := >
.PHONY: help install-dev lint format test corpus build check clean

IMAGE ?= sourcetrace:local
KIT ?= mc3-starter-kit

help:
> @echo "make install-dev  install ruff, Pillow, numpy, pypdf (tests also run with plain unittest)"
> @echo "make lint         ruff check + format check"
> @echo "make test         run the unit tests (no GPU needed)"
> @echo "make corpus       graded-like corpus in samples/corpus: KIT=path/to/mc3-starter-kit"
> @echo "make build        docker build -t $(IMAGE) ."
> @echo "make check        pre-submission checks against a built image (docker + AMD GPU)"

install-dev:
> python3 -m pip install ruff Pillow numpy pypdf

lint:
> ruff check .
> ruff format --check .

format:
> ruff check --fix .
> ruff format .

test:
> python3 -m unittest discover -s tests -v

corpus:
> python3 scripts/prepare_corpus.py --src $(KIT)/mc3-corpus --dest samples/corpus

build:
> docker build -t $(IMAGE) .

check:
> ./scripts/check_submission.sh $(IMAGE) $(KIT)

clean:
> rm -rf output index .pytest_cache .ruff_cache
> find . -name __pycache__ -type d -prune -exec rm -rf {} +
