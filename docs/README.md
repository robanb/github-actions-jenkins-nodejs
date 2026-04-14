# Documentation

This repository ships two equivalent CI/CD pipelines against the same
Node.js codebase. Pick the guide that matches the tool you're learning.

| Guide                                          | What it covers                                                    |
| ---------------------------------------------- | ----------------------------------------------------------------- |
| [**GITHUB-ACTIONS.md**](./GITHUB-ACTIONS.md)   | The GitHub Actions workflow at `.github/workflows/ci.yml` — anatomy, triggers, local reproduction, artifacts, troubleshooting, extensions. |
| [**JENKINS.md**](./JENKINS.md)                 | The Jenkins declarative pipeline at `Jenkinsfile` — anatomy, local Jenkins LTS bring-up via Docker, first-login, creating the pipeline job, running builds, troubleshooting, extensions, and a side-by-side comparison with GitHub Actions. |

Both guides are structured identically so you can diff them mentally:

1. Pipeline at a glance
2. Pipeline file anatomy
3. Triggers and execution
4. Viewing results and artifacts
5. Local reproduction (`./scripts/ci-local.sh`)
6. Troubleshooting
7. Extending the pipeline
8. Quick reference

### New here?

1. Read the main [README](../README.md) for the project overview.
2. Run `./scripts/setup.sh` to install the toolchain.
3. Run `./scripts/ci-local.sh` to exercise the same three commands both
   pipelines run (`npm ci`, `npm run lint`, `npm run test:coverage`).
4. Pick a pipeline guide and follow it top-to-bottom.
