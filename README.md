# SourceTrace

**Citation-exact retrieval-augmented question answering over mixed documents, built for AMD ROCm.**

Point it at a folder of PDFs, Word files, spreadsheets, CSVs, logs, source code and pictures,
ask a question, and get back the value, the exact files it came from, and nothing else. When the
folder does not contain the answer, it says nothing instead of guessing. It is built for the AMD
AI League *Match 3 (RAG)* grader, where a correct answer with the wrong citation set scores zero.

```
 corpus ──► defensive walk ──► per-type parsers ──► chunks ──► BM25 (+ dense) index   (once, --index)
                │                (pdf docx xlsx csv txt log py + pictures read by Qwen3-VL)
                └─ unreadable / encrypted / unknown / empty dir: recorded, skipped, never fatal

 question ─► retrieve ─► look at pictures with the question ─► {answer, evidence, lookup} ─┐
                ▲                                                                         │
                └──────── multi-hop: retrieve again with the identifier found ◄───────────┘
             answer must occur verbatim in the cited text ─► independent yes/no check
             ─► citation pruning (re-ask without each file; unchanged = not necessary)
             ─► /app/output/<query-id>_output.json   {"answer", "citations", "confidence"}
```

## Why it is built this way

| Challenge rule | What SourceTrace does |
|---|---|
| Each question is a **new process**, 30 s | A **resident server** (container `CMD`) holds the model and the index; `app.py` is a ~0.2 s client on a Unix socket. If a runner overrides `CMD`, the first call starts the server itself. |
| Indexing is charged to the 10 min startup, not to a question | `--index` parses everything once, reads pictures with the vision model, embeds, and persists the index to `/app/index`. |
| Citations are an **exact set**: necessity, not relevance | The model proposes evidence; code then **prunes**: each cited file is removed and the question re-asked, and a file whose removal leaves the answer unchanged is dropped. Chain sources (the log that gave the ticket number) are protected. |
| Superseded revisions are traps | `WITHDRAWN`/`SUPERSEDED BY` in the file name or the top of a document flags it: demoted in ranking, marked in the prompt, never preferred for grounding. |
| Multi-hop: "log shows an incident, which release fixed it?" | The model may answer `lookup: "ORR-1847"`; retrieval runs again with that identifier (exact-identifier boost) and both files are cited. |
| Unanswerable (even if the value sits in an encrypted file) | Encrypted PDFs are never opened. Three gates must pass or the answer is `""` with `[]`: the model must find a value, it must occur **verbatim** in a cited passage, and an independent verification call must confirm it. |
| Answers are the **value only**, complete (`Q3 FY27`, `REV-C2`) | Prompt rules plus `postprocess.py` (units/currency dropped, prose refusals mapped to `""`). Normalisation is the grader's own (`textutil.normalize`). |
| Two questions need a **vision model** (pin in a diagram, revision on a label) | Pictures are transcribed at index time (text plus `A -> B` relations), and at query time the vision model looks at the top pictures again **with the question**. Pictures embedded in PDFs and Word files are read too. |
| One unreadable file must not cost the corpus | Per-file isolation with a time limit per file; text files first, pictures last so a slow model only spends leftover time; tests simulate `--cap-drop DAC_OVERRIDE`. |
| No network at grading, 60 GiB image | Weights baked in (`/models`), `HF_HUB_OFFLINE=1`. Base 29 GiB + Qwen3-VL-8B ~17 GiB + extras ~2 GiB. |
| pip can silently replace ROCm torch with a CUDA build | The Dockerfile pins torch/torchvision/triton from the base via a constraints file and **fails the build** if `torch.__version__` stops containing `+rocm`. |
| One timeout zeroes the run | Every model call is deadline-bounded, a watchdog writes a refusal and exits before 30 s, and an (empty but valid) file exists from the first moment. `app.py` always exits 0. |

## Layout

```
app/
  app.py                  harness entry point
  requirements.txt
  sourcetrace/
    parsers/              pdf, docx, xlsx (standard-library OOXML), csv, text/code, images
    walker.py             defensive, ordered, time-boxed corpus walk
    store.py bm25.py embed.py   chunk index, BM25, optional dense retrieval, persistence
    answering.py          retrieve -> hop -> ground -> verify -> prune
    prompts.py postprocess.py   prompts; answer cleaning and JSON repair
    service.py server.py client.py cli.py output.py   resident server, thin client, atomic output
    backends/             qwen (transformers), mock (tests, no GPU)
scripts/
  smoke_test_model.py     RUN THIS FIRST on the AMD notebook
  evaluate.py             score answer + exact citations like the grader
  prepare_corpus.py       graded-like corpus: empty dir + chmod 000 file
  check_submission.sh     pre-submission gates against the built image
  download_model.py       used by the Dockerfile
tests/                    unit + end-to-end tests, no GPU needed (sample corpus included)
Dockerfile  .dockerignore  .gitignore  docker-compose.yml  Makefile  pyproject.toml
docs/SUBMISSION.md        ready-to-paste text for the lablab.ai form
```

## Workflow (in this order)

1. **Smoke-test on the AMD notebook** (3 GPU-hours/day; turn the session off afterwards):
   ```bash
   pip install --no-deps -U transformers tokenizers safetensors   # never a plain `-U` with deps
   pip install -r app/requirements.txt
   python scripts/smoke_test_model.py --embed BAAI/bge-small-en-v1.5
   ```
   It answers: ROCm torch? GPU visible? does Qwen3-VL load and follow the JSON format? does it
   read text from a picture? does it refuse when it should? peak VRAM?
2. **Run the real pipeline on the sample corpus** (still on the notebook, no Docker):
   ```bash
   python scripts/prepare_corpus.py --src mc3-starter-kit/mc3-corpus --dest /tmp/corpus
   python app/app.py --serve &                       # loads the model once
   python app/app.py --index /tmp/corpus
   python scripts/evaluate.py --local --corpus /tmp/corpus --questions mc3-starter-kit/sample-questions.json
   ```
   For debugging, set `SOURCETRACE_TRACE_DIR=/tmp/traces` to get one JSON per
   question showing what was retrieved, each hop, what pruning dropped and why a refusal happened.
3. **Build the image on a machine with Docker** (an AMD Developer Cloud GPU droplet has Docker and
   ROCm pre-installed; the notebook is a Jupyter pod and probably has no Docker daemon).
4. **Run the gates**: `./scripts/check_submission.sh sourcetrace:local mc3-starter-kit`
5. **Push to a public registry** and submit the image reference on lablab.ai (`docs/SUBMISSION.md`).

## Docker

```bash
docker build -t sourcetrace:local .
# reproducible weights:
docker build --build-arg MODEL_REVISION=<commit-sha> -t sourcetrace:local .

# run exactly like the grader: no network, no DAC_OVERRIDE
docker run -d --name st --network none --cap-drop DAC_OVERRIDE \
  --device=/dev/kfd --device=/dev/dri --group-add video --ipc=host \
  --security-opt seccomp=unconfined sourcetrace:local
docker cp /tmp/corpus/. st:/app/corpus
docker exec st python3 /app/app.py --index /app/corpus
docker exec st python3 /app/app.py --corpus /app/corpus --query-id query_01 \
  --query "What is the maximum junction temperature of the TQ-40?"
docker exec st cat /app/output/query_01_output.json
```

Publish (and never commit the reference to a public repo; `.gitignore` excludes `IMAGE_REF*`):

```bash
docker tag sourcetrace:local ghcr.io/<you>/<name>:v1 && docker push ghcr.io/<you>/<name>:v1
# make the package PUBLIC, then verify it pulls without credentials:
docker logout ghcr.io && docker pull ghcr.io/<you>/<name>:v1
```

## Configuration

All optional; environment variables.

| Variable | Default | Meaning |
|---|---|---|
| `SOURCETRACE_MODEL_PATH` | `/models/model` if present, else `Qwen/Qwen3-VL-8B-Instruct` | weights directory or HF id |
| `SOURCETRACE_EMBED_PATH` | `/models/embed` if present, else off | dense retrieval model; empty = BM25 only |
| `SOURCETRACE_MODE` | `auto` (image sets `server`) | `auto`, `server`, `standalone` |
| `SOURCETRACE_CLIENT_DEADLINE_S` | `27` | hard per-question deadline (limit is 30) |
| `SOURCETRACE_INDEX_BUDGET_S` | `420` | time the index pass may spend (limit 600 incl. model load) |
| `SOURCETRACE_TOP_CHUNKS` / `_MAX_CHUNKS_PER_FILE` | `10` / `3` | retrieval breadth |
| `SOURCETRACE_MAX_HOPS` | `2` | identifier look-ups per question |
| `SOURCETRACE_VISION_LOOKUP` | `1` | re-read top pictures with the question |
| `SOURCETRACE_VERIFY_ANSWER` / `_PRUNE_CITATIONS` | `1` / `1` | the verification and pruning stages |
| `SOURCETRACE_VRAM_CAP_GIB` | `44` | per-process GPU memory cap |
| `SOURCETRACE_TRACE_DIR` | unset | per-question debug trace |
| `SOURCETRACE_BACKEND` | `qwen` | `mock` exercises the whole contract without a GPU |

Another model: `--build-arg MODEL_ID=...` at build time. Anything loadable with
`AutoModelForImageTextToText` and a chat template works; at about 30 GiB of free image space the
practical ceiling is ~16B parameters in bf16.

## Development

```bash
make install-dev
make test      # unit + end-to-end tests: parsers, walker (incl. simulated DAC_OVERRIDE), index,
               # multi-hop, grounding, pruning, vision, server/client, CLI, all ten sample questions
make lint
```

The tests use a scripted model, so everything except the real LLM is covered on a laptop. In
particular `test_every_sample_question_scores` runs the ten sample questions end to end and checks
the answer **and** the exact citation set, with a model that deliberately over-cites.

## Known risks (verify these first)

Developed and tested **without an AMD GPU, ROCm, Docker or Python 3.14**, so reality may differ here:

1. **Real model behaviour.** The pipeline is tested with a scripted model. Whether Qwen3-VL-8B follows
   the JSON format, refuses correctly and reads the diagram is what `smoke_test_model.py` and
   `evaluate.py --local` measure. If the model is weak at JSON, tune `prompts.py`; the parser already
   repairs fences, trailing commas and truncated objects.
2. **torchvision.** The Match 3 brief shows `torchvision 0.28.0+rocm10.0.0` in the base image, so the
   Qwen3-VL processor should work. If it complains anyway, use `--build-arg TORCHVISION_SPEC=...`.
3. **Python 3.14 wheels.** If `pip install -r app/requirements.txt` finds no wheel for a package,
   relax its pin. `pypdf` and the OOXML readers are pure Python on purpose.
4. **Citations that need judgement.** If two files state the same value, the grader's expected file
   is one of them; pruning keeps the one the model ranked first. The hidden corpus is "larger and
   harder": use `SOURCETRACE_TRACE_DIR` to see why a question failed.
5. **Scanned PDFs.** Text-less PDF pages are not rasterised (that needs a PDF renderer that may not
   have a Python 3.14 wheel); only pictures *embedded* in a PDF are read.
6. **Startup race.** If the harness runs `--index` before the model finishes loading, the client waits
   (the socket is bound first) and the wait is charged to the 10 minute startup, as in the brief.
7. **Official self-checks can pass without a GPU.** Always score on a real GPU.

## License

MIT. See `LICENSE`. The files under `tests/fixtures/` are AMD's sample corpus from the Match 3
starter kit, included only so the end-to-end tests are reproducible.
