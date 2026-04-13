# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-04-13

### Added
- Initial Express service with `/`, `/health`, and `/sum` endpoints.
- Centralized error handling and 404 middleware.
- Graceful shutdown on `SIGTERM` / `SIGINT` in `server.js`.
- Jest + Supertest suite covering success, validation, and 404 paths.
- Jest coverage thresholds enforced in `package.json`.
- ESLint 9 flat configuration with recommended rules.
- GitHub Actions pipeline with lint job, Node.js 18/20 test matrix, npm
  caching, and coverage artifact upload.
- Documentation: `README.md` (including architecture and CI/CD sections),
  `CONTRIBUTING.md`, and this changelog.
