# Contributing to Ubumwe Connect

Thank you for considering contributing! 🌍 This document explains how to set up your
environment and the standards we follow.

## Code of Conduct

By participating, you agree to uphold our [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting Started

1. **Fork & clone** the repository
2. **Backend setup**
   ```bash
   cd backend
   python -m venv .venv
   .venv\Scripts\activate          # Windows
   pip install -r requirements.txt
   copy .env.example .env          # fill in required values
   ```
3. **Frontend setup**
   ```bash
   cd frontend
   flutter pub get
   ```
4. Create a feature branch:
   ```bash
   git checkout -b feat/your-feature
   ```

## Standards

| Area | Standard |
|---|---|
| Python style | PEP 8; type hints on public functions; `ruff`/`flake8` clean |
| Dart style | `flutter analyze` must pass with no warnings |
| Backend tests | `pytest` — new features require tests; all tests must pass |
| Frontend tests | `flutter test` — widget tests for new UI components |
| Commits | Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`) |
| Secrets | Never commit `.env`, credentials, or tokens |

### Commit examples

```
feat: add group creation flow with per-member language preference
fix: reconnect websocket with exponential backoff on mobile networks
docs: update API reference for /translate endpoint
```

## Pull Request Process

1. Ensure `pytest`, `flutter analyze`, and `flutter test` all pass locally
2. Update documentation for any user-facing or API change
3. Open the PR with a clear description, screenshots for UI changes, and reference to any related issue
4. A maintainer will review — address feedback and rebase if requested

## Reporting Bugs

Open an issue including:
- Steps to reproduce
- Expected vs actual behaviour
- Platform (Android/iOS/Web) and relevant logs

## Suggesting Features

Open an issue tagged `enhancement` describing the problem you're solving and the
proposed behaviour. Check [`docs/FUTURE_ENHANCEMENTS.md`](docs/FUTURE_ENHANCEMENTS.md)
first — your idea may already be on the roadmap.
