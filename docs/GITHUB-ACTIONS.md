# GitHub Actions Execution Guide

A detailed, step-by-step reference for running, inspecting, and extending the
GitHub Actions pipeline defined in this repository.

This guide covers **what** the pipeline does, **how** to execute it (both on
GitHub and locally), and **how** to interpret its results. It is meant to be
read top-to-bottom the first time and used as a reference afterwards.

> **Looking for the Jenkins equivalent?** This repo ships an equivalent
> Jenkins declarative pipeline (`Jenkinsfile`) and a local Jenkins LTS stack
> under `jenkins/`. See [`docs/JENKINS.md`](./JENKINS.md) for the full
> walkthrough and a side-by-side comparison table.

---

## Table of Contents

1. [Pipeline at a Glance](#1-pipeline-at-a-glance)
2. [Workflow File Anatomy](#2-workflow-file-anatomy)
3. [Triggers — When the Pipeline Runs](#3-triggers--when-the-pipeline-runs)
4. [Jobs — What the Pipeline Does](#4-jobs--what-the-pipeline-does)
5. [Executing the Pipeline on GitHub](#5-executing-the-pipeline-on-github)
6. [Executing the Same Steps Locally](#6-executing-the-same-steps-locally)
7. [Viewing Results and Artifacts](#7-viewing-results-and-artifacts)
8. [Status Badges and Branch Protection](#8-status-badges-and-branch-protection)
9. [Troubleshooting Failed Runs](#9-troubleshooting-failed-runs)
10. [Extending the Pipeline](#10-extending-the-pipeline)
11. [Quick Reference](#11-quick-reference)

---

## 1. Pipeline at a Glance

The pipeline lives in a single file: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

It executes two jobs on every push and pull request to `main`:

```
           ┌──────────┐        ┌───────────────────────────┐
  event ──▶│  lint    │──ok──▶ │  test (matrix)            │
           │  Node 20 │        │   ├── Node 18.x           │
           └──────────┘        │   └── Node 20.x ──▶ upload│
                               │                  coverage │
                               └───────────────────────────┘
```

| Stage          | Runner          | Node version   | Purpose                                       |
| -------------- | --------------- | -------------- | --------------------------------------------- |
| `lint`         | `ubuntu-latest` | 20.x           | ESLint 9 flat-config check (fails the build)  |
| `test` (job)   | `ubuntu-latest` | 18.x **and** 20.x | Jest + Supertest with a 90 %/80 % coverage gate |
| `test` (20.x)  | —               | —              | Uploads the `coverage/` directory as an artifact |

Key properties:

- **Lint is a gate.** `test` has `needs: lint`, so a red lint short-circuits the matrix and saves runner time.
- **Matrix with `fail-fast: false`.** Node 18 and Node 20 run in parallel and neither cancels the other on failure — useful to see which version actually broke.
- **Concurrency control.** A new push to the same ref cancels any in-flight run for that ref via the `concurrency` block.
- **Least privilege.** The workflow declares `permissions: contents: read` — no write tokens are issued.

---

## 2. Workflow File Anatomy

The full file is ~70 lines. Each block is called out below.

```yaml
name: CI
```
The workflow's display name in the **Actions** tab.

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
```
Three triggers:
- **`push` to `main`** — every direct commit (and every merged PR once it lands on `main`).
- **`pull_request` targeting `main`** — every PR that wants to merge into `main`, including updates to the PR branch.
- **`workflow_dispatch`** — a manual "Run workflow" button on the Actions tab.

```yaml
concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```
All runs for the same workflow *and* the same ref (e.g. `refs/heads/main` or `refs/pull/42/merge`) share a group. A new run cancels the previous one. This prevents a queue of stale runs when you push several commits in quick succession.

```yaml
permissions:
  contents: read
```
The default `GITHUB_TOKEN` only gets read access to the repo contents — no writes, no packages, no pull-request writes. Add scopes explicitly if you extend the pipeline (e.g. `pull-requests: write` for PR comments).

```yaml
jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20.x
          cache: npm
      - run: npm ci
      - run: npm run lint
```
The `lint` job:
1. **`actions/checkout@v4`** — clones the repo at the triggering commit.
2. **`actions/setup-node@v4`** — installs Node 20.x and enables the built-in npm cache. The cache key is derived from `package-lock.json`, so cache hits are automatic and safe.
3. **`npm ci`** — deterministic install from `package-lock.json` (fails if the lockfile is out of sync with `package.json`).
4. **`npm run lint`** — runs ESLint (`eslint .`) against the repo using `eslint.config.js`.

```yaml
  test:
    name: Test (Node ${{ matrix.node-version }})
    runs-on: ubuntu-latest
    needs: lint
    strategy:
      fail-fast: false
      matrix:
        node-version: [18.x, 20.x]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: npm
      - run: npm ci
      - run: npm run test:coverage -- --ci
      - if: matrix.node-version == '20.x'
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
          retention-days: 14
```
The `test` job:
- **`needs: lint`** — does not start until `lint` is green.
- **Matrix** — two parallel legs, one per Node version. `fail-fast: false` lets both legs finish so you can see where the failure is.
- **`npm run test:coverage -- --ci`** — runs `jest --coverage --ci`. The `--ci` flag tells Jest to fail on new snapshots and disables the interactive watcher.
- **Coverage gate** — enforced by Jest itself via `coverageThreshold` in `package.json`: **90 %** statements/lines/functions and **80 %** branches. Dropping below those numbers fails the job.
- **Artifact upload** — only the Node-20 leg uploads `coverage/` (to avoid duplicates). Retention is 14 days.

---

## 3. Triggers — When the Pipeline Runs

| Trigger             | Fired by                                                  | Typical use                                        |
| ------------------- | --------------------------------------------------------- | -------------------------------------------------- |
| `push` (branches: main) | `git push` to `main`, or merging a PR into `main`     | Post-merge verification, status badge updates      |
| `pull_request` (branches: main) | Opening a PR against `main`, pushing new commits to a PR branch, reopening a PR | Pre-merge gate for PRs                             |
| `workflow_dispatch` | Clicking **Run workflow** in the Actions UI, or `gh workflow run` | Re-running CI without a new commit, ad-hoc checks |

> **Note:** Pushes to other branches do **not** trigger CI. If you want CI on every branch, add `branches: ['**']` under `push`, or drop the `branches` filter entirely.

---

## 4. Jobs — What the Pipeline Does

### 4.1 `lint`

- **Goal:** Fail fast on style and obvious correctness issues before burning runner minutes on tests.
- **Config:** `eslint.config.js` (ESLint 9 flat config).
- **Command:** `npm run lint` → `eslint .`
- **How to reproduce locally:**
  ```bash
  npm ci
  npm run lint
  # or autofix trivial issues:
  npm run lint:fix
  ```

### 4.2 `test` (matrix over Node 18 and Node 20)

- **Goal:** Verify the code works on both the oldest supported Node (`engines.node >= 18`) and the current LTS (20).
- **Framework:** Jest + Supertest (`tests/app.test.js`, `tests/error-handler.test.js`).
- **Command:** `npm run test:coverage -- --ci` → `jest --coverage --ci`.
- **Coverage thresholds (from `package.json`):**
  ```json
  "coverageThreshold": {
    "global": {
      "branches": 80,
      "functions": 90,
      "lines": 90,
      "statements": 90
    }
  }
  ```
  Jest exits non-zero if any threshold is missed, which fails the job.
- **How to reproduce locally:**
  ```bash
  npm ci
  npm run test:coverage
  ```

### 4.3 Artifact: `coverage-report`

- **Produced by:** The Node-20 leg of the `test` job.
- **Contents:** The full `coverage/` directory — `lcov.info`, HTML report under `coverage/lcov-report/`, and the text summary.
- **Retention:** 14 days.
- **Where to get it:** See [§7](#7-viewing-results-and-artifacts).

---

## 5. Executing the Pipeline on GitHub

There are four ways to trigger a run. Pick whichever matches your workflow.

### 5.1 Push to `main`

Any commit that lands on `main` — direct or via merged PR — starts a run.

```bash
git checkout main
git pull
# make changes …
git add <files>
git commit -m "feat: describe change"
git push origin main
```

Watch the run:

```bash
gh run watch                 # follow the latest run live
gh run list --branch main    # list recent runs
gh run view --log            # open the latest run's logs
```

Or open `https://github.com/<owner>/<repo>/actions` in a browser.

### 5.2 Open or update a Pull Request

```bash
git checkout -b feat/my-change
# make changes …
git push -u origin feat/my-change
gh pr create --fill          # opens a PR; CI starts automatically
```

Every subsequent push to `feat/my-change` re-runs the pipeline and updates the PR checks. The previous run is cancelled by the `concurrency` block.

### 5.3 Manual run (`workflow_dispatch`)

**From the UI:**
1. Go to **Actions → CI** in the repository.
2. Click **Run workflow** (top-right).
3. Select the branch (defaults to `main`) and click **Run workflow**.

**From the CLI (GitHub CLI):**
```bash
gh workflow run ci.yml                    # run on default branch
gh workflow run ci.yml --ref main         # run on a specific branch
gh run watch                              # follow it live
```

### 5.4 Re-run a failed or previous run

**UI:** open the run, click **Re-run all jobs** or **Re-run failed jobs**.

**CLI:**
```bash
gh run list --limit 5                     # find the run id
gh run rerun <run-id>                     # re-run all jobs
gh run rerun <run-id> --failed            # re-run only failed jobs
```

---

## 6. Executing the Same Steps Locally

The repository ships with `scripts/ci-local.sh`, which runs **the exact same commands** GitHub Actions does, in the same order. Run it before pushing to catch failures without burning CI minutes.

### 6.1 Prerequisites

Use the bootstrap script to verify your toolchain and install dependencies:

```bash
./scripts/setup.sh
```

It checks:
- `node` satisfies `engines.node >= 18` (see `package.json`)
- `npm` is present
- `git` is present

and runs `npm ci` by default. Pass `--skip-install` to only validate the toolchain, or `--install-mode install` if you don't have a lockfile yet.

### 6.2 Run the local CI pipeline

```bash
./scripts/ci-local.sh
```

Under the hood it executes:
1. `npm ci`
2. `npm run lint`
3. `npm run test:coverage`

Each step prints a coloured banner and the script exits non-zero on the first failure. Use `--skip-install` to skip step 1 when your `node_modules/` is already current:

```bash
./scripts/ci-local.sh --skip-install
```

### 6.3 Run the individual steps by hand

```bash
npm ci                       # deterministic install (like CI)
npm run lint                 # ESLint
npm run lint:fix             # ESLint + autofix
npm test                     # Jest without coverage
npm run test:coverage        # Jest with coverage + thresholds
npm run test:watch           # Jest in watch mode (NOT what CI runs)
```

### 6.4 Smoke-test a running instance

`ci-local.sh` only reproduces the CI jobs. To verify the service actually works end-to-end, start the server in one terminal and run the smoke test in another:

```bash
# terminal 1
npm start                    # listens on http://localhost:3000

# terminal 2
./scripts/check-health.sh    # host + /health probe
./scripts/smoke-test.sh      # hits every endpoint and asserts
```

Both scripts accept `--url` and `--timeout` flags if you want to point them at a deployed instance instead of `localhost:3000`.

### 6.5 Reset the workspace

If a local run leaves stale state behind:

```bash
./scripts/clean.sh           # remove node_modules, coverage, jest cache
./scripts/clean.sh --dry-run # preview what would be removed
./scripts/clean.sh --deep    # also remove package-lock.json (dangerous)
```

---

## 7. Viewing Results and Artifacts

### 7.1 Pass/fail status

- **UI:** `Actions` tab → click the run → each job shows its logs, timing, and annotations.
- **CLI:**
  ```bash
  gh run list                 # latest runs, newest first
  gh run view <run-id>        # job summary
  gh run view <run-id> --log  # full logs
  gh run view <run-id> --log-failed  # logs for failing steps only
  ```

### 7.2 Download the coverage artifact

The Node-20 leg of the `test` job uploads `coverage/` as the `coverage-report` artifact.

**UI:**
1. Open the run in the Actions tab.
2. Scroll to **Artifacts** at the bottom of the run summary.
3. Click `coverage-report` to download a zip.
4. Extract and open `lcov-report/index.html` in a browser to see line-by-line coverage.

**CLI:**
```bash
gh run download <run-id> -n coverage-report -D coverage/
open coverage/lcov-report/index.html    # macOS
xdg-open coverage/lcov-report/index.html # Linux
```

### 7.3 Reading the Jest coverage summary in the logs

Even without the artifact, the job log shows a text summary:

```
File        | % Stmts | % Branch | % Funcs | % Lines |
------------|---------|----------|---------|---------|
All files   |   100   |   100    |   100   |   100   |
 app.js     |   100   |   100    |   100   |   100   |
 routes.js  |   100   |   100    |   100   |   100   |
 middleware |   100   |   100    |   100   |   100   |
```

Any row below the thresholds in `package.json` marks the job red.

---

## 8. Status Badges and Branch Protection

### 8.1 Add a status badge to README

```markdown
![CI](https://github.com/<owner>/<repo>/actions/workflows/ci.yml/badge.svg)
```

Optional flavours:
```markdown
![CI (main)](https://github.com/<owner>/<repo>/actions/workflows/ci.yml/badge.svg?branch=main)
![CI (event=push)](https://github.com/<owner>/<repo>/actions/workflows/ci.yml/badge.svg?event=push)
```

### 8.2 Make CI a required check for merging

1. Repo → **Settings → Branches → Branch protection rules**.
2. Add a rule for `main`.
3. Enable **Require status checks to pass before merging**.
4. Select `Lint`, `Test (Node 18.x)`, and `Test (Node 20.x)` as required checks.
5. Enable **Require branches to be up to date before merging** if you want strict linear history.

After that, PRs cannot be merged until all three checks are green.

---

## 9. Troubleshooting Failed Runs

### 9.1 `npm ci` fails with "lockfile is not in sync"

Cause: `package.json` was changed without regenerating `package-lock.json`.

Fix:
```bash
npm install                  # regenerates the lockfile
git add package-lock.json
git commit -m "chore: update lockfile"
```

### 9.2 Lint fails

Run it locally and fix what ESLint reports:
```bash
npm run lint                 # see the errors
npm run lint:fix             # autofix trivial issues
```

If a legitimate rule needs relaxing, edit `eslint.config.js`; avoid per-line `eslint-disable` comments unless the exception is genuinely local.

### 9.3 Tests pass locally but fail in CI

Common causes:
- **Node version mismatch.** CI tests on 18 **and** 20; reproduce locally with whichever version is red:
  ```bash
  nvm install 18 && nvm use 18
  npm ci && npm test
  ```
- **Missing `--ci` flag locally.** CI runs `jest --ci`, which fails on obsolete snapshots. Reproduce with:
  ```bash
  npm run test:coverage -- --ci
  ```
- **Non-deterministic test.** Time, TZ, random ports. Fix the test, not the pipeline.

### 9.4 Coverage gate fails

The log line looks like:
```
Jest: "global" coverage threshold for lines (90%) not met: 87.5%
```

Options (in order of preference):
1. **Add the missing test.** Find the uncovered lines in `coverage/lcov-report/index.html` and cover them.
2. **Exclude genuinely untestable code** via `collectCoverageFrom` in `package.json`.
3. **Lower the threshold** only as a last resort, and only with a written justification in the PR.

### 9.5 A matrix leg times out or flakes

Re-run only the failed jobs instead of the whole pipeline:
```bash
gh run rerun <run-id> --failed
```

If flakes are frequent, the right fix is in the test, not in retry logic.

### 9.6 Run stuck "queued"

Usually means:
- Another run for the same ref is still in progress and concurrency cancelled yours (expected).
- You've hit the free-tier runner minutes quota.
- GitHub Actions has an incident — check `https://www.githubstatus.com/`.

---

## 10. Extending the Pipeline

The current workflow is intentionally minimal. Common next steps, with pointers:

### 10.1 Add a build or package step

Add a third job that depends on `test` and, for example, builds a Docker image:

```yaml
  build:
    name: Build image
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          tags: github-actions-jenkins-nodejs:${{ github.sha }}
```

### 10.2 Publish coverage to Codecov

```yaml
      - name: Upload coverage to Codecov
        if: matrix.node-version == '20.x'
        uses: codecov/codecov-action@v4
        with:
          files: coverage/lcov.info
          fail_ci_if_error: true
        env:
          CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

### 10.3 Cache beyond npm

`actions/setup-node@v4` already caches the npm download cache keyed on `package-lock.json`. If you add slow derived artifacts (e.g. a TypeScript build), cache them explicitly with `actions/cache@v4`.

### 10.4 Deploy on tagged releases

Add a separate workflow file (e.g. `release.yml`) triggered by `push: tags: ['v*']` — keep CI and CD concerns in separate files so a broken deploy job does not hold up normal CI.

### 10.5 Schedule a nightly run

```yaml
on:
  schedule:
    - cron: '0 3 * * *'   # 03:00 UTC daily
```

Useful for catching dependency drift even on weeks with no commits.

---

## 11. Quick Reference

| Task                                 | Command                                              |
| ------------------------------------ | ---------------------------------------------------- |
| Bootstrap the environment            | `./scripts/setup.sh`                                 |
| Run the exact CI steps locally       | `./scripts/ci-local.sh`                              |
| Run CI steps, skip `npm ci`          | `./scripts/ci-local.sh --skip-install`               |
| Lint only                            | `npm run lint`                                       |
| Lint + autofix                       | `npm run lint:fix`                                   |
| Unit tests only                      | `npm test`                                           |
| Unit tests + coverage + thresholds   | `npm run test:coverage`                              |
| Start the server                     | `npm start`                                          |
| Health probe                         | `./scripts/check-health.sh`                          |
| Smoke test every endpoint            | `./scripts/smoke-test.sh`                            |
| Clean working tree                   | `./scripts/clean.sh`                                 |
| Trigger CI manually                  | `gh workflow run ci.yml`                             |
| Watch latest run                     | `gh run watch`                                       |
| List recent runs                     | `gh run list`                                        |
| View a run's logs                    | `gh run view <id> --log`                             |
| View only failed step logs           | `gh run view <id> --log-failed`                      |
| Re-run only failed jobs              | `gh run rerun <id> --failed`                         |
| Download coverage artifact           | `gh run download <id> -n coverage-report -D coverage/` |

---

**Source of truth:** The workflow file at [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) is authoritative. If this guide and the workflow ever disagree, the workflow wins — please open a PR to update this document.
