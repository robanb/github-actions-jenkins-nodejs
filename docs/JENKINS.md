# Jenkins Execution Guide

A detailed, step-by-step reference for running, inspecting, and extending the
Jenkins declarative pipeline defined in this repository.

This guide walks through **setting up a local Jenkins LTS in Docker**,
**wiring the pipeline job**, **running a build end-to-end**, and
**comparing the result to the GitHub Actions workflow** that lives next
to it. It is meant to be read top-to-bottom the first time and used as a
reference afterwards.

> **Looking for the GitHub Actions equivalent?** See
> [`docs/GITHUB-ACTIONS.md`](./GITHUB-ACTIONS.md). The two guides are
> structured identically so you can diff them mentally.

---

## Table of Contents

1. [Pipeline at a Glance](#1-pipeline-at-a-glance)
2. [Jenkinsfile Anatomy](#2-jenkinsfile-anatomy)
3. [The `jenkins/` Stack](#3-the-jenkins-stack)
4. [Bringing Up Local Jenkins](#4-bringing-up-local-jenkins)
5. [First Login and Sanity Checks](#5-first-login-and-sanity-checks)
6. [Creating the Pipeline Job](#6-creating-the-pipeline-job)
7. [Running the Pipeline](#7-running-the-pipeline)
8. [Viewing Results and Artifacts](#8-viewing-results-and-artifacts)
9. [Reproducing the Same Steps Locally](#9-reproducing-the-same-steps-locally)
10. [Troubleshooting](#10-troubleshooting)
11. [Extending the Pipeline](#11-extending-the-pipeline)
12. [GitHub Actions vs. Jenkins — Side-by-Side](#12-github-actions-vs-jenkins--side-by-side)
13. [Quick Reference](#13-quick-reference)

---

## 1. Pipeline at a Glance

The pipeline lives in a single file at the repo root: [`Jenkinsfile`](../Jenkinsfile).

It executes four stages in sequence on every build:

```
  Checkout  ──▶  Lint  ──▶  Test (Node 18)  ──▶  Test (Node 20)
                                                        │
                                                        ▼
                                              Archive coverage/
                                              Publish JUnit report
```

| Stage             | Node version | Purpose                                         |
| ----------------- | ------------ | ----------------------------------------------- |
| `Checkout`        | —            | Clone the repo at the triggering commit         |
| `Lint`            | 20           | `npm ci` + ESLint (fast-fail gate)              |
| `Test (Node 18)`  | 18           | Jest + Supertest with the 90 %/80 % coverage gate and a JUnit report |
| `Test (Node 20)`  | 20           | Same as Node 18, plus `archiveArtifacts` on `coverage/` |

Key properties:

- **Lint gates Test.** A red lint short-circuits the rest of the build.
- **Tests run sequentially on two Node versions.** Node 18 first, then Node 20. Parallel execution is possible but needs workspace isolation; the sequential form is simpler and fast enough for a teaching lab.
- **Jest writes a JUnit XML report** (via `jest-junit`) into `reports/junit/junit.xml`. Jenkins reads it with the `junit` step and renders the native **Test Result** UI with pass/fail counts, per-test durations, and history graphs.
- **Coverage is archived only from the Node 20 leg** to avoid duplication, matching the GitHub Actions workflow.
- **Concurrent builds are disabled** (`disableConcurrentBuilds`) — pushing several commits queues them.
- **SCM polling** every five minutes is the trigger. If you expose Jenkins to the internet and wire a GitHub webhook, you can swap `pollSCM` for `githubPush()`.

---

## 2. Jenkinsfile Anatomy

The full file is ~80 lines. Each block is called out below.

### `pipeline` and `agent`

```groovy
pipeline {
  agent any
  ...
}
```

`pipeline { ... }` declares a **declarative pipeline** (as opposed to scripted Groovy). `agent any` tells Jenkins to run every stage on any available executor — in a local single-controller setup that's always the built-in node.

### `options`

```groovy
options {
  timestamps()
  ansiColor('xterm')
  timeout(time: 15, unit: 'MINUTES')
  buildDiscarder(logRotator(numToKeepStr: '20'))
  disableConcurrentBuilds()
}
```

| Option                  | Why                                                       |
| ----------------------- | --------------------------------------------------------- |
| `timestamps()`          | Prefixes every console line with `HH:mm:ss`. Requires the **Timestamper** plugin. |
| `ansiColor('xterm')`    | Renders coloured npm/ESLint output in the Console Output. Requires the **AnsiColor** plugin. |
| `timeout(...)`          | Kills the build after 15 minutes — safety net against runaway tests. |
| `buildDiscarder(...)`   | Keeps the last 20 builds on disk and drops older ones. Protects `/var/jenkins_home` from filling up. |
| `disableConcurrentBuilds()` | Queues new builds instead of running two copies of the job in parallel. Avoids `npm ci` contention. |

### `triggers`

```groovy
triggers {
  pollSCM('H/5 * * * *')
}
```

The `H/5 * * * *` cron expression polls the remote once every ~5 minutes (the `H` spreads the poll across the hour so multiple jobs don't all poll at the same second). If Jenkins finds a new commit on `main`, it starts a build.

Alternatives you might use in production:

- `githubPush()` — a true push-driven trigger, requires a GitHub webhook pointing at `http://<your-jenkins>/github-webhook/`.
- `cron('H 3 * * *')` — run once a day at ~03:00 regardless of commits (useful for dependency-drift detection).

### `environment`

```groovy
environment {
  CI = 'true'
}
```

Sets a process-wide environment variable for every `sh` step in the build. `CI=true` is the conventional signal to Jest (and most other Node tooling) that it is running in a non-interactive context.

### Stages

#### `Checkout`

```groovy
stage('Checkout') {
  steps { checkout scm }
}
```

`checkout scm` reads the SCM configuration attached to the job (see [§6](#6-creating-the-pipeline-job)) and does a `git clone` / `git fetch` + `git checkout` for the triggering commit.

#### `Lint`

```groovy
stage('Lint') {
  tools { nodejs 'Node 20' }
  steps {
    sh 'node --version'
    sh 'npm ci'
    sh 'npm run lint'
  }
}
```

`tools { nodejs 'Node 20' }` asks the **NodeJS** plugin to put the binaries from the *Node 20* tool installation (configured via JCasC, see [§3](#3-the-jenkins-stack)) on `PATH` for this stage only. On first use the plugin downloads and caches the binaries inside `/var/jenkins_home/tools/`.

#### `Test (Node 18)` and `Test (Node 20)`

```groovy
stage('Test (Node 18)') {
  tools { nodejs 'Node 18' }
  steps {
    sh 'node --version'
    sh 'npm ci'
    sh 'npm run test:coverage -- --ci'
  }
  post {
    always {
      junit 'reports/junit/junit.xml'
    }
  }
}
```

- `npm ci` is re-run per stage because each stage uses a different Node version (and `node_modules/` can contain native binaries compiled against the specific Node ABI).
- `npm run test:coverage -- --ci` runs `jest --coverage --ci`. The `--ci` flag tells Jest not to write new snapshots and to fail if any are missing.
- `post { always { junit ... } }` parses the JUnit XML *regardless* of whether the `sh` step passed or failed. Even failed test runs should feed the Test Result view so you can see which test broke.

The Node 20 stage has one extra `post` action:

```groovy
post {
  always {
    junit 'reports/junit/junit.xml'
  }
  success {
    archiveArtifacts artifacts: 'coverage/**', fingerprint: true
  }
}
```

`archiveArtifacts` copies the `coverage/` directory off the build workspace into Jenkins' artifact store, so it survives workspace cleanup and can be downloaded from the build page.

### Top-level `post`

```groovy
post {
  success { echo 'Pipeline succeeded.' }
  failure { echo 'Pipeline failed — check the Console Output and Test Result pages.' }
  always  { cleanWs(notFailBuild: true) }
}
```

`cleanWs()` wipes the workspace at the end of every build so the next build starts from a clean slate. `notFailBuild: true` means a cleanup glitch never fails the build.

---

## 3. The `jenkins/` Stack

The repository ships a one-command local Jenkins under `jenkins/`:

```
jenkins/
├── Dockerfile          # jenkins/jenkins:lts-jdk17 + curl + git + plugins
├── docker-compose.yml  # service definition, volume, env vars, ports
├── plugins.txt         # plugin manifest (unpinned = latest compatible)
├── casc.yaml           # Configuration-as-Code: admin + NodeJS tools
└── .env.example        # template for jenkins/.env (admin credentials)
```

### Dockerfile

```dockerfile
FROM jenkins/jenkins:lts-jdk17

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
USER jenkins

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --latest true
```

- **Base image:** `jenkins/jenkins:lts-jdk17` — the long-term-support release on JDK 17, which is what new Jenkins installations should use today.
- **System packages:** `curl` (for the health-check and for debugging), `git` (explicit even though the base image includes it), `ca-certificates` (HTTPS to GitHub and the npm registry).
- **Plugin install:** `jenkins-plugin-cli` is the modern replacement for `install-plugins.sh`. It reads the manifest and installs the latest compatible release of each plugin.

### plugins.txt

```
workflow-aggregator
pipeline-stage-view
git
github
nodejs
configuration-as-code
timestamper
ansicolor
ws-cleanup
junit
```

| Plugin                 | What it gives you                                   |
| ---------------------- | --------------------------------------------------- |
| `workflow-aggregator`  | The umbrella package that pulls in Pipeline core    |
| `pipeline-stage-view`  | The per-build stage timeline UI                     |
| `git`, `github`        | SCM polling, checkout, commit status publishing     |
| `nodejs`               | The `tools { nodejs '...' }` directive and the NodeJS tool installer |
| `configuration-as-code`| Reads `casc.yaml` at boot                           |
| `timestamper`          | `timestamps()` pipeline option                      |
| `ansicolor`            | `ansiColor('xterm')` pipeline option                |
| `ws-cleanup`           | `cleanWs()` post step                               |
| `junit`                | The `junit` step and the Test Result UI             |

### casc.yaml

Configuration-as-Code (**JCasC**) is what lets us ship a "ready-to-run" Jenkins without clicking through the first-run wizard. The file is deliberately small — it only handles things that would otherwise be click-ops:

```yaml
jenkins:
  systemMessage: "github-actions-jenkins-nodejs :: local Jenkins LTS"
  numExecutors: 2
  mode: NORMAL

  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "${JENKINS_ADMIN_ID:-admin}"
          password: "${JENKINS_ADMIN_PASSWORD:-admin}"

  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false

tool:
  nodejs:
    installations:
      - name: "Node 18"
        properties:
          - installSource:
              installers:
                - nodeJSInstaller:
                    id: "18.20.4"
      - name: "Node 20"
        properties:
          - installSource:
              installers:
                - nodeJSInstaller:
                    id: "20.18.0"
```

What it does, block by block:

- **`jenkins.systemMessage`** — the banner shown at the top of the Jenkins dashboard. Confirms the container is the one you think it is.
- **`jenkins.numExecutors: 2`** — two concurrent build slots on the controller. Enough for this lab's single job plus any manual experiments you run.
- **`securityRealm.local`** — Jenkins manages its own user database (as opposed to delegating to LDAP, SAML, GitHub OAuth, etc.). One user is seeded from the `JENKINS_ADMIN_ID` and `JENKINS_ADMIN_PASSWORD` environment variables, which `docker-compose.yml` sources from `jenkins/.env` (or uses `admin`/`admin` as a fallback).
- **`authorizationStrategy.loggedInUsersCanDoAnything`** — anyone logged in is an admin. Fine for a local lab; **replace with a matrix-auth strategy for anything internet-facing**.
- **`tool.nodejs.installations`** — defines the two tool installations that the `Jenkinsfile` references by name. The `id` value is a concrete version string that Jenkins downloads from the nodejs.org release manifest on first use.

What `casc.yaml` intentionally does **not** do:

- **It does not create the pipeline job.** You create it once through the UI in [§6](#6-creating-the-pipeline-job). That's on purpose — manually wiring a pipeline job is one of the key skills this lab is teaching.
- **It does not configure webhooks.** Local Jenkins has no public URL, so webhook delivery wouldn't work anyway.
- **It does not manage credentials.** You don't need any for a public repo. See [§11](#11-extending-the-pipeline) for how to add them later.

### docker-compose.yml

```yaml
services:
  jenkins:
    build: .
    image: gajn-jenkins:local
    container_name: gajn-jenkins
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "50000:50000"
    environment:
      JAVA_OPTS: "-Djenkins.install.runSetupWizard=false"
      CASC_JENKINS_CONFIG: /var/jenkins_conf/casc.yaml
      JENKINS_ADMIN_ID: ${JENKINS_ADMIN_ID:-admin}
      JENKINS_ADMIN_PASSWORD: ${JENKINS_ADMIN_PASSWORD:-admin}
    volumes:
      - jenkins_home:/var/jenkins_home
      - ./casc.yaml:/var/jenkins_conf/casc.yaml:ro
volumes:
  jenkins_home:
```

Highlights:

- **`build: .`** — build the Dockerfile in the same directory. The resulting image is tagged `gajn-jenkins:local` so you can spot it in `docker image ls`.
- **`JAVA_OPTS=-Djenkins.install.runSetupWizard=false`** — tells Jenkins to skip the "Unlock Jenkins" screen. The password that would normally be used for unlocking (the one you're told to copy from the container log) is not needed.
- **`CASC_JENKINS_CONFIG=/var/jenkins_conf/casc.yaml`** — points the JCasC plugin at the file mounted from the host. Changing the host file and running `docker compose restart jenkins` re-applies the config without a rebuild.
- **`jenkins_home` volume** — persists builds, caches, plugins, and downloaded Node binaries across container restarts. `docker compose down` keeps the volume; `docker compose down -v` wipes it.
- **Port `8080`** — the web UI. `http://localhost:8080` after `docker compose up`.
- **Port `50000`** — the inbound-agent port. Unused in this lab (we only have the controller) but exposed anyway because it's idiomatic.

---

## 4. Bringing Up Local Jenkins

### 4.1 Prerequisites

- **Docker Engine** 20.10+ and **Docker Compose v2** (`docker compose version` should work). On a Mac or Windows host, Docker Desktop ships both.
- **Free ports** 8080 and 50000. If something else is already listening, either stop that service or edit the `ports:` block in `docker-compose.yml` to remap (e.g. `"8081:8080"`).
- **~1 GB of free disk space** for the image + plugins.

### 4.2 One-shot build and start

From the repo root:

```bash
# Build the image (first time only) and start the container in the background
docker compose -f jenkins/docker-compose.yml up -d --build
```

What happens:

1. Docker pulls `jenkins/jenkins:lts-jdk17` (~450 MB).
2. The Dockerfile layer installs `curl`, `git`, `ca-certificates`.
3. `jenkins-plugin-cli` downloads every plugin in `plugins.txt` into `/usr/share/jenkins/ref/plugins/`. Takes ~1–2 minutes on a fast connection.
4. The container starts, copies the reference plugins into `/var/jenkins_home/plugins/` on first boot, loads `casc.yaml`, and seeds the `admin` user.
5. Jenkins becomes reachable at `http://localhost:8080`.

### 4.3 Watching the startup log

```bash
docker compose -f jenkins/docker-compose.yml logs -f jenkins
```

You'll see lines like:

```
Jenkins initial setup is required. An admin user has been created [...]
Configuration as Code: Loading configuration from /var/jenkins_conf/casc.yaml
Jenkins is fully up and running
```

Once you see `Jenkins is fully up and running`, press `Ctrl+C` to detach from the log stream (the container keeps running in the background).

### 4.4 Stopping and resetting

```bash
# Stop and remove the container (volume kept)
docker compose -f jenkins/docker-compose.yml down

# Stop and wipe everything including builds and plugin cache
docker compose -f jenkins/docker-compose.yml down -v

# Restart without rebuilding (picks up casc.yaml edits)
docker compose -f jenkins/docker-compose.yml restart jenkins

# Rebuild the image after editing Dockerfile or plugins.txt
docker compose -f jenkins/docker-compose.yml up -d --build
```

### 4.5 Overriding the admin credentials

Before your first `docker compose up`, copy the example env file and edit it:

```bash
cp jenkins/.env.example jenkins/.env
$EDITOR jenkins/.env
```

```ini
JENKINS_ADMIN_ID=admin
JENKINS_ADMIN_PASSWORD=something-secret-just-for-you
```

`jenkins/.env` is gitignored. `docker compose` reads it automatically because it sits next to `docker-compose.yml`.

---

## 5. First Login and Sanity Checks

1. Open `http://localhost:8080` in a browser.
2. Log in with the credentials from `jenkins/.env` (or `admin` / `admin` if you skipped §4.5).
3. You should land on the Jenkins dashboard. Confirm:
   - The banner message at the top reads `github-actions-jenkins-nodejs :: local Jenkins LTS`.
   - There are no pipeline jobs yet (expected — you'll create one in the next section).
4. Sanity-check the NodeJS tool installations:
   - **Manage Jenkins** → **Tools** → scroll to **NodeJS installations**.
   - You should see **Node 18** (version `18.20.4`) and **Node 20** (version `20.18.0`). If either is missing, the JCasC load failed; check `docker compose logs jenkins`.
5. Sanity-check the plugin set:
   - **Manage Jenkins** → **Plugins** → **Installed plugins**.
   - Confirm `Pipeline`, `NodeJS`, `Git`, `GitHub`, `JUnit`, `Timestamper`, `AnsiColor`, and `Configuration as Code` are all present and enabled.

---

## 6. Creating the Pipeline Job

This is the one-time manual step. It takes about 60 seconds.

1. From the dashboard, click **+ New Item** (top-left).
2. **Enter an item name:** `github-actions-jenkins-nodejs`.
3. Select **Pipeline** from the list.
4. Click **OK**.

You're now on the configuration page. Scroll and fill in:

### General

- **Description:** `Declarative Jenkins pipeline mirroring .github/workflows/ci.yml. See docs/JENKINS.md.`
- Tick **Discard old builds** and set **Max # of builds to keep:** `20`.
- Leave the rest unchecked.

### Build Triggers

Tick **Poll SCM** and enter `H/5 * * * *` in the schedule box. (This is optional — the `Jenkinsfile` itself also declares a `pollSCM` trigger, and Jenkins merges both. But having it on the job makes the behaviour visible in the UI.)

### Pipeline

This is the important section.

- **Definition:** `Pipeline script from SCM`
- **SCM:** `Git`
- **Repository URL:** `https://github.com/robanb/github-actions-jenkins-nodejs.git`
- **Credentials:** `- none -` (the repo is public)
- **Branches to build:** `*/main`
- **Script Path:** `Jenkinsfile` (the default — leave it)
- Tick **Lightweight checkout** so Jenkins fetches only the `Jenkinsfile` before deciding whether to run, instead of cloning the whole repo twice.

Click **Save**.

You are now on the job page. It shows "No builds yet".

---

## 7. Running the Pipeline

### 7.1 Manual run

On the job page, click **Build Now** (left sidebar). A new entry appears under **Build History** with a flashing progress bar.

Click the entry (or the `#1` link under **Build History**) to see the build details. Useful sub-pages:

| Sub-page        | What you'll see                                                |
| --------------- | -------------------------------------------------------------- |
| **Status**      | High-level summary: duration, triggered by, changes since last |
| **Console Output** | The full stdout/stderr of every `sh` step, with timestamps and ANSI colours |
| **Pipeline Steps** | A clickable list of every pipeline step that ran               |
| **Test Result** | The JUnit report: test counts, per-file and per-test duration, failures with stack traces |

The first build does extra work: downloading Node 18 and Node 20 binaries (each ~30 MB) and caching them under `/var/jenkins_home/tools/`. Expect ~3–4 minutes. Subsequent builds reuse the cache and complete in ~1 minute.

### 7.2 Automatic run via SCM polling

With `pollSCM('H/5 * * * *')`, Jenkins checks the remote every ~5 minutes. Push a commit to `main`:

```bash
git commit --allow-empty -m "ci: trigger"
git push origin main
```

Within 5 minutes a new build starts on its own. Watch **Build History** on the job page, or tail the logs:

```bash
docker compose -f jenkins/docker-compose.yml logs -f jenkins | grep -i polling
```

### 7.3 Triggering via the REST API (optional)

Jenkins exposes every job action over a REST API. To trigger a build from the command line:

```bash
# 1. Generate an API token in your user profile:
#    http://localhost:8080/me/configure → Add new Token → Copy
TOKEN=<paste-token>

# 2. Fire a build
curl -X POST \
  --user "admin:${TOKEN}" \
  http://localhost:8080/job/github-actions-jenkins-nodejs/build
```

The build is queued immediately, which is handy when you want a push-button integration from a shell script or a webhook handler.

---

## 8. Viewing Results and Artifacts

### 8.1 Stage view

On the job page, the **Stage View** table shows one row per build and one column per stage. Hover any cell to see its duration; click a cell to jump straight to that stage's log output. It's the fastest way to see at a glance which stage is slow or flaky.

### 8.2 Test Result

Each finished build has a **Test Result** link if JUnit parsing succeeded. The page shows:

- Top-level totals: `X tests, Y failures, Z skipped, duration`.
- A drilldown by test suite (file), then by describe/it block.
- Failures are highlighted and expand to show the Jest assertion message and the stack trace.
- A trend graph under **Status → Test Result Trend** shows pass/fail counts over the last 20 builds — useful for spotting flakes.

Because `jest-junit` writes the XML on every run (pass or fail) and the pipeline parses it in `post { always { ... } }`, the Test Result page is always populated even when the pipeline fails.

### 8.3 Coverage artifacts

The Node 20 stage's `archiveArtifacts artifacts: 'coverage/**'` makes the full `coverage/` directory downloadable from the build page.

**UI path:** job page → build number → **Artifacts** on the left → click `coverage.zip` (Jenkins zips multi-file artifacts on download).

**Browser view of the HTML report:**

1. Download the zip.
2. Extract it somewhere.
3. Open `coverage/lcov-report/index.html` in your browser.

If you want an inline coverage view inside Jenkins without downloading, install the **HTML Publisher** plugin and add a `publishHTML(...)` step to the Node 20 stage (see [§11](#11-extending-the-pipeline)).

### 8.4 Console output

Every pipeline step's stdout and stderr are captured into the **Console Output** page. With `timestamps()` enabled, every line is prefixed with `HH:mm:ss.SSS`, which is invaluable when diagnosing a slow step. Use `Ctrl+F` to jump to the first `ERROR` or `WARN` string.

---

## 9. Reproducing the Same Steps Locally

Before triggering a Jenkins build on a pushed commit, save yourself the round-trip by running the same steps on your workstation:

```bash
./scripts/ci-local.sh
```

which is equivalent to:

```bash
npm ci
npm run lint
npm run test:coverage -- --ci
```

See the **Reproducing the Same Steps Locally** section of [`docs/GITHUB-ACTIONS.md`](./GITHUB-ACTIONS.md#6-executing-the-same-steps-locally) for the full treatment — the exact same script is used to pre-flight both pipelines.

---

## 10. Troubleshooting

### 10.1 `docker compose up` exits immediately

Usually port 8080 is already in use. Check with:

```bash
lsof -i :8080   # or: ss -ltnp | grep 8080
```

Either stop the conflicting service or remap the port in `jenkins/docker-compose.yml`:

```yaml
ports:
  - "8081:8080"
```

then reach Jenkins at `http://localhost:8081`.

### 10.2 I can't log in / admin password rejected

The admin user is seeded **only on first boot**, from the env vars active at that moment. If you changed `jenkins/.env` *after* the first startup, the new password is ignored because the user already exists in `/var/jenkins_home/users/`.

Two fixes:

- **Reset the instance** (destroys all builds): `docker compose -f jenkins/docker-compose.yml down -v && docker compose -f jenkins/docker-compose.yml up -d`
- **Change the password from inside Jenkins**: log in with the old password, go to **People → admin → Configure**, set a new password.

### 10.3 `java.lang.NoClassDefFoundError` or "plugin X depends on Y" on startup

A plugin in `plugins.txt` pulled in a newer version than a sibling can handle. Rebuild with a fresh plugin resolution:

```bash
docker compose -f jenkins/docker-compose.yml down -v
docker compose -f jenkins/docker-compose.yml up -d --build --force-recreate
```

The `--latest true` flag on `jenkins-plugin-cli` pulls the newest compatible release of each plugin, which usually resolves transitive conflicts.

### 10.4 `tool 'Node 18' is not defined` during a build

Either the NodeJS plugin is missing or the JCasC load failed. Check both:

- **Manage Jenkins → Tools → NodeJS installations** should list Node 18 and Node 20.
- `docker compose logs jenkins | grep -i casc` should show `Configuration as Code: Loading configuration from /var/jenkins_conf/casc.yaml`.

If JCasC complained about a syntax error, the log will name the line. Fix the YAML, then `docker compose restart jenkins`.

### 10.5 Tests pass locally but fail in Jenkins

Common causes:

- **Node version mismatch.** Your local Node is neither 18 nor 20, but Jenkins runs both. Run the same version locally: `nvm use 18 && npm test`.
- **Missing JUnit reporter.** If `junit 'reports/junit/junit.xml'` logs `No test report files were found`, the `jest-junit` devDependency is missing from `package.json` or the reporter config under `jest.reporters` is wrong. Check with `npm run test:coverage` locally and confirm `reports/junit/junit.xml` exists afterwards.
- **Non-deterministic test.** Time, timezone, random ports. Fix the test, not the pipeline.

### 10.6 The coverage artifact is empty

`archiveArtifacts` only runs on `success`. If the Node 20 test stage failed, the artifact step is skipped on purpose. Check the Test Result page first, fix the failing test, and rerun.

### 10.7 Build hangs at "Waiting for next available executor"

The job is set to `disableConcurrentBuilds()` and the previous build is still running. Cancel or wait for it to finish. If there is no previous build, check **Manage Jenkins → System Information → numExecutors** — it should be ≥ 1.

---

## 11. Extending the Pipeline

The current pipeline is deliberately minimal. Common next steps, with pointers:

### 11.1 Parallel test matrix

Replace the two sequential `Test (Node X)` stages with a `parallel` block:

```groovy
stage('Test') {
  parallel {
    stage('Node 18') {
      agent { label 'built-in' }
      tools { nodejs 'Node 18' }
      steps {
        checkout scm
        sh 'npm ci'
        sh 'npm run test:coverage -- --ci'
      }
      post { always { junit 'reports/junit/junit.xml' } }
    }
    stage('Node 20') {
      agent { label 'built-in' }
      tools { nodejs 'Node 20' }
      steps {
        checkout scm
        sh 'npm ci'
        sh 'npm run test:coverage -- --ci'
      }
      post { always { junit 'reports/junit/junit.xml' } }
    }
  }
}
```

Note the inner `agent { label 'built-in' }` — it gives each parallel cell its own workspace directory, which is what avoids `node_modules` contention.

### 11.2 Inline coverage HTML report

Add the **HTML Publisher** plugin to `plugins.txt` and a `publishHTML` step to the Node 20 stage:

```groovy
post {
  success {
    publishHTML(target: [
      reportDir: 'coverage/lcov-report',
      reportFiles: 'index.html',
      reportName: 'Coverage Report',
      keepAll: true
    ])
  }
}
```

A **Coverage Report** link will appear on the build sidebar, rendering the HTML directly in Jenkins.

### 11.3 Build a Docker image

Add a post-test stage that builds an image from the app:

```groovy
stage('Build image') {
  steps {
    sh 'docker build -t github-actions-jenkins-nodejs:${BUILD_NUMBER} .'
  }
}
```

Needs a `Dockerfile` at the repo root (not shipped yet), and the Jenkins container needs access to the host Docker socket (`-v /var/run/docker.sock:/var/run/docker.sock` in `docker-compose.yml`).

### 11.4 Push to a registry with credentials

Add a credential under **Manage Jenkins → Credentials** (id: `dockerhub`), then reference it in the pipeline:

```groovy
stage('Push image') {
  steps {
    withCredentials([usernamePassword(
        credentialsId: 'dockerhub',
        usernameVariable: 'DH_USER',
        passwordVariable: 'DH_PASS')]) {
      sh 'echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin'
      sh 'docker push github-actions-jenkins-nodejs:${BUILD_NUMBER}'
    }
  }
}
```

`withCredentials` binds the secret to local shell variables that are masked in the Console Output.

### 11.5 GitHub webhook trigger

When Jenkins is reachable from GitHub (public URL, ngrok tunnel, reverse proxy…):

1. In GitHub: **Settings → Webhooks → Add webhook**
2. Payload URL: `http://<your-jenkins>/github-webhook/`
3. Content type: `application/json`
4. Events: **Just the push event**
5. In the Jenkinsfile, replace `pollSCM(...)` with `githubPush()`.

Builds now start within seconds of a push instead of within 5 minutes.

---

## 12. GitHub Actions vs. Jenkins — Side-by-Side

Both pipelines run against the same `main` branch and execute the same three commands (`npm ci`, `npm run lint`, `npm run test:coverage`). The table below maps the concepts each tool uses for the same job.

| Concept                     | GitHub Actions (`.github/workflows/ci.yml`) | Jenkins (`Jenkinsfile`)                        |
| --------------------------- | ------------------------------------------- | ---------------------------------------------- |
| **Pipeline definition file** | `.github/workflows/ci.yml` (YAML)           | `Jenkinsfile` at the repo root (Groovy DSL)    |
| **Where it runs**           | GitHub-hosted or self-hosted runners        | Your own Jenkins controller / agents           |
| **Trigger: push/PR**        | `on: push` / `on: pull_request`             | `pollSCM(...)` or `githubPush()` with a webhook |
| **Trigger: manual**         | `workflow_dispatch` + "Run workflow" button | **Build Now** or `curl` against the REST API   |
| **Trigger: scheduled**      | `on: schedule: cron:`                       | `triggers { cron('...') }`                     |
| **Concurrency control**     | `concurrency:` block, cancels old runs      | `disableConcurrentBuilds()` option             |
| **Job / stage**             | Top-level `jobs:` + `steps:`                | `stages { stage { steps } }`                   |
| **Matrix over Node versions** | `strategy.matrix` with `fail-fast: false`   | `parallel { }` or `matrix { }` directive       |
| **Tool / language setup**   | `actions/setup-node@v4` with `cache: npm`   | NodeJS plugin + `tools { nodejs 'Node 20' }`  |
| **Checkout**                | `actions/checkout@v4`                       | `checkout scm`                                 |
| **Secrets**                 | `secrets.MY_TOKEN` + `${{ }}` interpolation | **Credentials** + `withCredentials { }`        |
| **Environment variables**   | `env:` at workflow / job / step level       | `environment { }` block or `withEnv { }`       |
| **Caching**                 | `actions/cache@v4`, keyed on lockfile       | `stash`/`unstash` or the Job Cacher plugin     |
| **Artifacts**               | `actions/upload-artifact@v4`                | `archiveArtifacts` step                        |
| **Test report UI**          | Workflow logs + third-party actions         | Built-in **JUnit** plugin with trend graphs    |
| **Log output**              | Streamed on the run page                    | **Console Output**, timestamped via Timestamper |
| **Retry failed job**        | **Re-run failed jobs** button               | **Rebuild** / **Replay** on the build page    |
| **Status badge**            | `badge.svg` URL from GitHub                 | `/buildStatus/icon?job=<name>` endpoint        |
| **Cost model**              | Free minutes + paid overage                 | Free, but you run (and maintain) the server    |
| **First-run setup**         | Push the workflow file, it just runs        | Install Jenkins, install plugins, create job   |
| **Learning curve**          | Low — YAML + marketplace actions            | Medium — Groovy, plugin ecosystem, admin UI    |

**When to pick which (rule of thumb for this repo's audience):**

- **GitHub Actions** is the pragmatic default when your code already lives on GitHub: zero infrastructure, integrated PR checks, a huge marketplace of ready-made actions. For open-source projects it's effectively free.
- **Jenkins** still dominates inside enterprises with strict network policies, on-prem build agents, unusual toolchains, or a large pile of pre-existing pipeline DSL. Knowing how to *read*, *run*, and *extend* a Jenkinsfile is still table-stakes DevOps knowledge.
- **In this lab**, running both side-by-side is the point: you see the *same* three commands wearing two different pipeline jackets, and you build the muscle memory to translate between them.

---

## 13. Quick Reference

| Task                                      | Command                                                                    |
| ----------------------------------------- | -------------------------------------------------------------------------- |
| Build + start local Jenkins               | `docker compose -f jenkins/docker-compose.yml up -d --build`               |
| Stop Jenkins (keep volume)                | `docker compose -f jenkins/docker-compose.yml down`                        |
| Wipe Jenkins completely                   | `docker compose -f jenkins/docker-compose.yml down -v`                     |
| Reload JCasC without rebuilding           | `docker compose -f jenkins/docker-compose.yml restart jenkins`             |
| Tail the Jenkins log                      | `docker compose -f jenkins/docker-compose.yml logs -f jenkins`             |
| Open the UI                               | `http://localhost:8080`                                                    |
| Default admin credentials                 | `admin` / `admin` (override in `jenkins/.env`)                             |
| Trigger a build from the CLI              | `curl -X POST --user admin:$TOKEN http://localhost:8080/job/github-actions-jenkins-nodejs/build` |
| Run the same steps on your workstation   | `./scripts/ci-local.sh`                                                    |
| Where the pipeline lives                  | [`Jenkinsfile`](../Jenkinsfile) (at the repo root)                         |
| Where the GH Actions peer lives           | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)                  |
| Where the side-by-side comparison lives   | [§12 above](#12-github-actions-vs-jenkins--side-by-side)                   |

---

**Source of truth:** The `Jenkinsfile` at the repo root is authoritative. If this guide and the pipeline ever disagree, the pipeline wins — please open a PR to update this document.
