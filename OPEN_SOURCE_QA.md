# Open Source QA Process

This project uses a lightweight open source QA process focused on public
documentation, repeatable local checks, and automated verification in the
development workflow.

## QA Documentation Published

QA expectations are published in this repository and in the MkDocs site so
contributors can review the process before opening a pull request.

Published QA documentation includes:

- Project setup and usage documentation in `README.md`.
- Contribution requirements in `CONTRIBUTING.md`.
- Project scope and governance in `PROJECT_CHARTER.md`.
- Public QA process in this document.
- Generated Flutter API documentation in the documentation site.

## Tests Executed as Part of Development Workflow

Contributors should run the same checks locally before opening a pull request:

```sh
cd speech_recognizer
flutter pub get
flutter analyze
flutter test --coverage
cd ..
mkdocs build --strict
```

The GitHub Pages workflow also executes the automated Flutter test suite before
publishing the documentation site. It writes line coverage to the GitHub Actions
job summary and uploads `speech_recognizer/coverage/lcov.info` as a workflow
artifact. A failed test run or missing coverage report blocks the documentation
deployment.

Integration tests that exercise real model loading or audio recognition should
be run on supported devices or simulators when changing recognizer behavior.

## Review Checklist

Before merging changes, maintainers should confirm:

- Public documentation is updated when setup, behavior, or APIs change.
- Flutter analyzer checks pass.
- Flutter tests pass with coverage generated.
- Device or simulator integration testing is completed for recognizer changes.
- MkDocs builds successfully with strict validation.
