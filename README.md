# github-actions-jenkins-nodejs

[![CI](https://github.com/robanb/github-actions-jenkins-nodejs/actions/workflows/ci.yml/badge.svg)](https://github.com/robanb/github-actions-jenkins-nodejs/actions/workflows/ci.yml)
[![Node.js](https://img.shields.io/badge/node-%3E%3D18-339933?logo=node.js&logoColor=white)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

A hands-on **Node.js + Express** lab built for the *DevOps Engineer
Certification Course* that demonstrates end-to-end **CI/CD pipelines with
both GitHub Actions and Jenkins** against the same codebase: linting,
automated testing on a Node.js version matrix, coverage reporting, and build
artifacts.

The application itself is intentionally small so the focus stays on the
**pipelines**, not on business logic.

---

## Table of Contents

- [Overview](#overview)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Available Scripts](#available-scripts)
- [DevOps Scripts](#devops-scripts)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [Testing & Coverage](#testing--coverage)
- [Linting](#linting)
- [CI/CD Pipeline](#cicd-pipeline)
- [Pushing to GitHub](#pushing-to-github)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

`github-actions-jenkins-nodejs` exposes a tiny HTTP API with three endpoints
and a set of cross-cutting concerns (JSON middleware, centralized error
handling, graceful shutdown). Every change pushed to the repository is
validated by **two parallel pipelines** — a GitHub Actions workflow and a
Jenkins declarative pipeline — that both run ESLint and execute the Jest
test suite across multiple Node.js versions.

**Learning goals**

1. Structure a Node.js project using modular routes and middleware.
2. Author a **GitHub Actions** workflow with multiple jobs, caching, and a
   build matrix.
3. Author an equivalent **Jenkins declarative pipeline** and run it against
   a local Jenkins LTS instance.
4. Compare the two tools side-by-side on the same codebase.
5. Use coverage thresholds to enforce quality gates.
6. Publish and consume pipeline artifacts.

## Tech Stack

| Layer         | Tool                    |
| ------------- | ----------------------- |
| Runtime       | Node.js `>= 18`         |
| Web framework | Express 4               |
| Test runner   | Jest 29                 |
| HTTP testing  | Supertest 7             |
| Linter        | ESLint 9 (flat config)  |
| CI (hosted)   | GitHub Actions          |
| CI (self-hosted) | Jenkins (declarative pipeline) |

## Project Structure

```text
github-actions-jenkins-nodejs/
├── .github/
│   └── workflows/
│       └── ci.yml                  # GitHub Actions pipeline
├── Jenkinsfile                     # Jenkins declarative pipeline (coming)
├── jenkins/                        # Local Jenkins LTS via Docker (coming)
│   └── docker-compose.yml
├── src/
│   ├── app.js                      # Express app factory
│   ├── server.js                   # Runtime entry point
│   ├── routes.js                   # HTTP route definitions
│   └── middleware/
│       ├── error-handler.js        # Centralized error responses
│       └── not-found.js            # 404 handler
├── tests/
│   ├── app.test.js                 # HTTP integration tests
│   └── error-handler.test.js       # Middleware unit tests
├── scripts/
│   ├── setup.sh                    # Bootstrap the dev environment
│   ├── check-health.sh             # Host specs + /health probe
│   ├── smoke-test.sh               # End-to-end endpoint checks
│   ├── ci-local.sh                 # Run the full CI pipeline locally
│   └── clean.sh                    # Remove generated artifacts
├── .editorconfig
├── .gitignore
├── .nvmrc
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── README.md
├── eslint.config.js
└── package.json
```

## Prerequisites

- **Node.js** 18 or newer (20 LTS recommended — pinned in `.nvmrc`)
- **npm** 9+ (ships with Node.js 18/20)
- A **GitHub account** to host the repository and run the Actions workflow

## Getting Started

```bash
# Clone
git clone https://github.com/robanb/github-actions-jenkins-nodejs.git
cd github-actions-jenkins-nodejs

# Install dependencies
npm ci

# Start the service (http://localhost:3000)
npm start

# Run the test suite
npm test
```

To use the Node.js version pinned in `.nvmrc`:

```bash
nvm use
```

## Available Scripts

| Script                 | Description                                     |
| ---------------------- | ----------------------------------------------- |
| `npm start`            | Launches the Express server on `$PORT` or 3000. |
| `npm test`             | Runs the Jest test suite once.                  |
| `npm run test:watch`   | Runs Jest in watch mode for local development.  |
| `npm run test:coverage`| Runs tests and generates a coverage report.     |
| `npm run lint`         | Lints all source and test files with ESLint.   |
| `npm run lint:fix`     | Applies ESLint autofixes where possible.        |

## DevOps Scripts

A set of Bash helpers lives in `scripts/`. They are intentionally
self-contained, POSIX-friendly, and safe to run from any working directory
(each script resolves its own project root).

| Script                      | Purpose                                                                |
| --------------------------- | ---------------------------------------------------------------------- |
| `scripts/setup.sh`          | Verifies the toolchain and installs dependencies with `npm ci`.       |
| `scripts/check-health.sh`   | Prints host specs (OS, CPU, memory, disk), validates Node/npm versions, and probes the running `/health` endpoint. |
| `scripts/smoke-test.sh`     | Hits every public endpoint and asserts status code + response body.   |
| `scripts/ci-local.sh`       | Runs the same steps as GitHub Actions: install, lint, test + coverage.|
| `scripts/clean.sh`          | Removes `node_modules`, coverage, caches, and (with `--deep`) the lockfile. Supports `--dry-run`. |

**Common flags**

- `-h`, `--help` — every script prints usage and exits.
- `--no-color` (`check-health.sh`) — disable ANSI colors for log capture.
- `--url <base>` (`check-health.sh`, `smoke-test.sh`) — target a non-default URL, e.g. a staging host.
- `--timeout <seconds>` — HTTP timeout for the probe scripts.

**Typical workflow**

```bash
./scripts/setup.sh                 # first-time bootstrap
npm start &                        # start the service in the background
./scripts/check-health.sh          # host + /health inspection
./scripts/smoke-test.sh            # full endpoint sweep
./scripts/ci-local.sh              # pre-push validation
./scripts/clean.sh                 # wipe artifacts before archiving
```

All scripts exit with `0` on success and non-zero on failure, so they drop
straight into other pipelines (CI jobs, Makefiles, Ansible playbooks).

## API Reference

| Method | Path       | Description                           | Example                          |
| ------ | ---------- | ------------------------------------- | -------------------------------- |
| GET    | `/`        | Welcome payload with service version. | `curl http://localhost:3000/`    |
| GET    | `/health`  | Liveness probe with uptime.           | `curl http://localhost:3000/health` |
| GET    | `/sum`     | Adds two numeric query parameters.    | `curl "http://localhost:3000/sum?a=2&b=3"` |

**Successful response — `GET /sum?a=2&b=3`**

```json
{ "a": 2, "b": 3, "result": 5 }
```

**Error response — invalid input**

```json
{
  "error": {
    "status": 400,
    "message": "Query parameters \"a\" and \"b\" must be valid numbers."
  }
}
```

Unknown routes return a `404` with the same error envelope.

## Architecture

The service is deliberately small so the CI/CD pipeline stays the main focus,
but it still follows the separation-of-concerns patterns you would apply to a
production Express application.

### High-Level Diagram

```text
            ┌────────────┐
  HTTP ───▶ │  server.js │  (runtime entry point)
            └─────┬──────┘
                  │  imports
                  ▼
            ┌────────────┐
            │   app.js   │  (Express app factory)
            └─────┬──────┘
                  │  wires
      ┌───────────┼────────────────┐
      ▼           ▼                ▼
┌──────────┐ ┌──────────┐    ┌─────────────────────┐
│ json     │ │ routes.js│    │ middleware/         │
│ parser   │ │  (GET /, │    │  ├─ not-found.js    │
│          │ │  health, │    │  └─ error-handler.js│
│          │ │  sum)    │    │                     │
└──────────┘ └──────────┘    └─────────────────────┘
```

### Modules

**`src/server.js`** — runtime entry point used by `npm start`. Reads `PORT`
from the environment (defaults to `3000`), starts the HTTP listener, and
registers `SIGTERM` / `SIGINT` handlers for graceful shutdown — important
when the service runs inside a container orchestrator.

**`src/app.js`** — defines a `createApp()` factory that instantiates and
configures the Express application:

1. Disables the `x-powered-by` header for a small security improvement.
2. Registers `express.json()` to parse JSON request bodies.
3. Mounts the router from `routes.js`.
4. Mounts the 404 handler **after** the routes so it catches unmatched paths.
5. Mounts the error handler **last** so every `next(err)` call flows through
   it.

Exporting a factory (rather than a singleton) makes the app trivially
testable — tests can import a fresh instance without ever binding a port.

**`src/routes.js`** — declares the three HTTP routes using an Express
`Router`:

| Route         | Responsibility                                            |
| ------------- | --------------------------------------------------------- |
| `GET /`       | Returns a welcome payload that echoes the package version. |
| `GET /health` | Lightweight liveness check used by probes.                |
| `GET /sum`    | Parses numeric query params and returns their sum, or errors via `next(err)`. |

Validation errors are forwarded to the shared error handler instead of being
serialized inline, keeping error formatting consistent across the API.

**`src/middleware/not-found.js`** — a terminal middleware that converts
unmatched requests into a `404` error and forwards it to the error handler.

**`src/middleware/error-handler.js`** — the single place where errors become
HTTP responses. It picks up `err.status` (falling back to `500`), returns a
consistent `{ error: { status, message } }` envelope, and logs `5xx` errors
with request context while keeping `4xx` errors quiet.

### Request Lifecycle

1. HTTP request hits the Express listener.
2. `express.json()` parses the body if `Content-Type: application/json`.
3. The router dispatches the request to the matching handler, which either
   responds with JSON or calls `next(err)` with an error bearing an HTTP
   `status`.
4. If no route matches, `not-found.js` fires and emits a 404 error.
5. `error-handler.js` receives any forwarded error and serializes it.

### Design Principles Applied

- **Single-responsibility modules** — each file does one thing (wire app,
  declare routes, handle errors, start server).
- **Fail fast, then format centrally** — handlers forward errors with
  `next(err)` instead of duplicating response formatting.
- **Environment-driven configuration** — `PORT` comes from the environment,
  not from hard-coded constants.
- **Graceful shutdown** — essential for containerized deployments that send
  `SIGTERM` before killing a process.

## Testing & Coverage

Tests are written with **Jest** and **Supertest** and cover successful
responses, validation errors, and the 404 fallback. The error handler also
has direct unit tests. Coverage thresholds are declared in `package.json`
and will fail CI if they drop below:

| Metric     | Threshold |
| ---------- | --------- |
| Statements | 90%       |
| Lines      | 90%       |
| Functions  | 90%       |
| Branches   | 80%       |

```bash
npm run test:coverage
```

A human-readable summary is printed to the console, and an `lcov` report is
written to `coverage/` for downstream tools (Codecov, SonarQube, etc.).

`server.js` is excluded from coverage in `package.json` because its only
responsibility is wiring the runtime — tests import `app.js` directly and
Supertest binds it to an ephemeral port per request.

## Linting

ESLint 9 is configured using the modern [flat config](https://eslint.org/docs/latest/use/configure/configuration-files)
in `eslint.config.js`, extending `@eslint/js` recommended rules and adding a
few opinionated constraints (`eqeqeq`, `prefer-const`, unused-vars).

```bash
npm run lint       # check
npm run lint:fix   # auto-fix
```

## CI/CD Pipeline

The pipeline lives in [`.github/workflows/ci.yml`](./.github/workflows/ci.yml)
and runs on every `push` and `pull_request` targeting `main`, plus manual
`workflow_dispatch` triggers.

```text
┌────────────┐     ┌──────────────────────────┐
│  lint job  │ ──▶ │  test job (matrix 18/20) │ ──▶ upload coverage artifact
└────────────┘     └──────────────────────────┘
```

### Pipeline Goals

1. **Validate** every push and pull request on `main`.
2. **Fail fast** on obvious issues (lint) before running the more expensive
   test suite.
3. **Prove compatibility** with the Node.js versions the project supports.
4. **Produce artifacts** (coverage) that humans and other tools can inspect.
5. **Be idempotent and cache-friendly** so repeated runs stay fast and cheap.

### Triggers

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
```

- `push` — validates the default branch after every merge.
- `pull_request` — gates contributions before they are merged.
- `workflow_dispatch` — lets maintainers run the pipeline manually from the
  **Actions** tab (useful for demos and re-runs).

### Concurrency Control

```yaml
concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

When a new commit lands on the same branch, the previous in-flight run is
cancelled. This prevents wasted minutes on pipelines whose results will be
superseded anyway.

### Permissions

```yaml
permissions:
  contents: read
```

Follows the principle of least privilege. CI only needs to read the
repository; it does not publish packages, push commits, or create releases.

### Jobs

**1. `lint`** — runs ESLint on a single Node.js version. Lint is fast and
catches the most common programmer errors, so it belongs in its own job that
gates the test matrix.

**2. `test`** — runs Jest with coverage on a Node.js version matrix:

```yaml
  test:
    needs: lint
    strategy:
      fail-fast: false
      matrix:
        node-version: [18.x, 20.x]
```

Key points:

- **`needs: lint`** — the matrix only runs when lint succeeds.
- **`fail-fast: false`** — if Node 18 fails, Node 20 still runs. This gives
  you a complete picture of compatibility instead of stopping at the first
  failure.
- **Matrix dimensions** — add more versions by appending to the array.

The Node 20 job uploads the `coverage/` directory as a workflow artifact
(guarded by an `if:` expression so only one job uploads, avoiding naming
clashes). The artifact is retained for 14 days.

### Caching

`actions/setup-node@v4` understands `cache: npm` and automatically caches
`~/.npm` keyed on the hash of `package-lock.json`. Subsequent runs reuse the
cached tarballs, cutting install time from ~30 s to a couple of seconds on
warm caches.

### `npm ci` vs `npm install`

`npm ci` installs dependencies strictly from `package-lock.json`, fails if
the lockfile is out of sync with `package.json`, and wipes any existing
`node_modules`. This is exactly what you want on CI: reproducible,
deterministic installs.

### Extending the Pipeline

The workflow is a good starting point. Natural next steps for the course:

| Extension                            | How                                                              |
| ------------------------------------ | ---------------------------------------------------------------- |
| Publish coverage to Codecov          | Add `codecov/codecov-action@v4` after the test step.             |
| Build a Docker image                 | Add a new job using `docker/build-push-action`.                  |
| Push the image to GHCR               | Use `docker/login-action` with `secrets.GITHUB_TOKEN`.           |
| Deploy to a cloud target             | Gate a `deploy` job on `needs: test` and `if: github.ref == 'refs/heads/main'`. |
| Dependency / security scan           | Add `actions/dependency-review-action` on pull requests.         |
| Cut GitHub releases on tags          | Create a separate workflow triggered on `push.tags`.             |

### Running the Pipeline Locally

You can reproduce the same steps on your machine before pushing:

```bash
npm ci
npm run lint
npm run test:coverage
```

This mirrors what CI does and is the fastest way to avoid red pipelines.

### Troubleshooting

| Symptom                                          | Likely cause / fix                                           |
| ------------------------------------------------ | ------------------------------------------------------------ |
| `npm ci` fails with "lockfile out of date"       | Run `npm install` locally and commit `package-lock.json`.    |
| Tests pass locally but fail on CI                | Node version mismatch — use `nvm use` to match `.nvmrc`.     |
| Coverage threshold errors after adding new code  | Add tests or lower the threshold in `package.json` intentionally. |
| Workflow does not run on a PR                    | The PR target branch is not `main`, or the workflow file is not on the default branch yet. |

## Pushing to GitHub

1. Create a new empty repository on GitHub (e.g. `github-actions-jenkins-nodejs`).
2. From this folder:
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/robanb/github-actions-jenkins-nodejs.git
   git push -u origin main
   ```
3. Open the **Actions** tab on GitHub — you should see the CI workflow
   running.
4. Create a branch, change something (e.g. break a test), open a PR, and
   watch the CI report the failure.

## Contributing

Contributions are welcome. Please read [`CONTRIBUTING.md`](./CONTRIBUTING.md)
for development setup, branching strategy, and the PR checklist.

## License

Released under the [MIT License](./LICENSE).
