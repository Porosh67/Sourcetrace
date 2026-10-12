# lablab.ai submission text (Match 3: RAG)

Ready to paste. Limits checked at the bottom of this file by `python3 -c` (title 5-50
characters, description 600+ characters and 100+ words).

## Step 1 of 2: Basic Information

**Submission Title**

    SourceTrace: Citation-Exact RAG on AMD ROCm

**Long Description**

    SourceTrace answers questions over a folder of mixed company documents (PDF, Word, Excel, CSV, logs, source code and pictures) and names the exact files each answer came from. It runs as a container on AMD GPUs with ROCm, with Qwen3-VL as the single model for reading text, reading pictures and writing answers, plus BM25 and dense retrieval.

    The design follows the grading rule that a right answer with the wrong citations scores nothing. A resident server keeps the model and the index in memory while app.py stays a thin client, so every question is a new process yet answers in seconds. Indexing parses each file defensively, so an unreadable file, an encrypted PDF, an unknown type or an empty directory never costs the rest of the corpus. Pictures are read by the vision model at index time and again at query time with the question in hand. Withdrawn revisions are demoted, multi-hop questions follow identifiers such as a ticket number from a log to a bug database, and the answer must appear word for word in the cited text.

    Citations are made minimal on purpose: each cited file is removed and the question re-asked, and a file that changes nothing is dropped. When the corpus does not contain the answer, SourceTrace returns an empty answer and no citations instead of guessing. The project ships with a Dockerfile on the mandated ROCm base image, baked-in weights, 102 tests, an evaluation script and a pre-submission checker.

**Categories**: pick the closest available (for example Machine Learning / NLP / Enterprise AI).

**Technologies Used**: AMD ROCm, AMD Instinct / Developer Cloud, PyTorch, Hugging Face
Transformers, Qwen3-VL, Docker, Python (select the ones that exist in the list).

**Mini Challenge 3 Image**: a screenshot of a passing `check_submission.sh` run or of the
architecture diagram from the README. Leave it empty if the field does not accept an upload.
Never put junk text (such as `xcv`) in it.

**Mini Challenge 2 Image**: leave as it is for the other submission.

## Step 2 of 2

Expected: the public container image reference. Push the image to a registry, make it
public, test `docker pull` without logging in, then paste the reference. Do not publish it
anywhere else (not in a public README, a blog post or the description above).

## Before you press submit

- [ ] `./scripts/check_submission.sh <image> <path-to-mc3-starter-kit>` passes
- [ ] the real model scored the ten sample questions 10/10 on the AMD GPU
- [ ] image is public and pullable without credentials
- [ ] no secrets in the image
