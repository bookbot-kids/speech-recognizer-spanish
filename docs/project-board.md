# Project Board Suggestion

## Project Name

Bookbot Spanish Speech Recognizer Quality & Release Board

## Short Description

Tracks open-source maintenance, QA, documentation, CI coverage, and release
readiness for the Bookbot Spanish speech recognizer Flutter app.

## README

This project board is the public planning surface for
`bookbot-kids/speech-recognizer-spanish`. It should help contributors and
maintainers see what is planned, in progress, blocked, and ready for review.

Recommended views:

- **Triage**: New issues and incoming contributor reports.
- **Development**: Recognizer implementation tasks, bug fixes, and documentation
  work.
- **QA & CI**: Test coverage, workflow health, branch protection, and release
  checks.
- **Device Validation**: Android, iOS, and macOS simulator or device checks for
  model loading, audio capture, and recognition behavior.
- **Release Readiness**: Items required before publishing a new tag or
  distribution package.

Recommended fields:

- **Status**: Triage, Ready, In Progress, In Review, Blocked, Done.
- **Type**: Bug, Feature, Documentation, QA, CI, Release.
- **Priority**: High, Medium, Low.
- **Area**: Flutter UI, Speech Controller, Android, iOS, macOS, Models,
  Documentation, CI.

Suggested automation:

- Add newly opened issues to **Triage**.
- Move linked issues to **In Review** when a pull request is opened.
- Move linked issues to **Done** when a pull request is merged.

Initial cards to create:

- Enable branch protection and required PR review on `main`.
- Add and monitor CI coverage reporting.
- Track simulator/device validation for recognizer changes.
- Review public documentation after each API or setup change.

