# Contributing

Thank you for taking an interest in improving `sample-node-ci`! This project
exists to teach GitHub Actions CI/CD, so contributions that make the pipeline
clearer, more idiomatic, or better documented are especially welcome.

## Development Setup

1. Fork the repository and clone your fork.
2. Install the supported Node.js version:
   ```bash
   nvm use       # reads .nvmrc
   ```
3. Install dependencies with a clean, lockfile-driven install:
   ```bash
   npm ci
   ```
4. Verify your environment:
   ```bash
   npm run lint
   npm test
   ```

## Branching Strategy

- Create a feature branch from `main`:
  ```bash
  git checkout -b feat/short-description
  ```
- Use a prefix that reflects the intent of your change:
  - `feat/` — new functionality
  - `fix/` — bug fix
  - `docs/` — documentation only
  - `chore/` — tooling, configuration, refactor without behavior change
  - `ci/` — pipeline or workflow changes

## Commit Style

Use short, imperative commit subjects (max ~72 characters) and expand in the
body when context is helpful. Conventional-Commits-style prefixes are
encouraged but not required:

```
feat(routes): add /version endpoint
fix(error-handler): preserve original stack for 5xx errors
docs(ci): explain coverage artifact retention
```

## Pull Request Checklist

Before opening a PR, please make sure that:

- [ ] `npm run lint` passes with no warnings.
- [ ] `npm test` passes.
- [ ] `npm run test:coverage` stays above the thresholds in `package.json`.
- [ ] New behavior has accompanying tests.
- [ ] Documentation (`README.md`) is updated when behavior or the pipeline
      changes.
- [ ] The PR description explains **why** the change is needed, not just
      what it does.

## Reporting Issues

When filing an issue, include:

- What you expected to happen.
- What actually happened.
- Steps to reproduce, including the exact commands you ran.
- Your Node.js version (`node -v`) and operating system.

## Code of Conduct

Be respectful. Disagree technically, not personally. Assume good intent.
