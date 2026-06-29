# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Changed
- Move `Lurk.Deploy`, `Lurk.Deploy.*` from library to CLI 
- Rename `validateForm` → `runGuards` for consistency with `FormGuard` type

## [0.1.0.0] - 2026-06-28

Initial release.

### Added

#### Core
- `[lurk|...|]` QuasiQuoter for compile-time HTML templates with `{{expr}}` interpolation
- Type-safe i18n routing with implicit params (`get homePath homeAction`)
- File-backed session management with expiry, atomic writes, and `destroySession`
- CSRF token generation, validation, and WAI middleware
- Flash messages (`flashSuccess`, `flashError`, `flashWarning`)
- Composable `FormGuard` pipeline with honeypot, min submit time, MX verification, and field length guards
- Self-contained SMTP client (STARTTLS/SMTPS, AUTH LOGIN)
- Structured JSON logging with per-file mutex
- `.env` file loading (`loadEnv`, `getEnv`, `requireEnv`)
- SEO data types (title, meta, OG, Twitter cards, hreflang)
- Compile-time fingerprinted asset paths (`mkAssetPath`)
- Cloudflare typed header access
- HTTP security headers middleware
- Default 404/500 error views with exception middleware
- Cloudflare header detection (country, city, ASN, bot score)

#### CLI
- `lurk run` / `lurk build` — start dev server or build native binary
- `lurk kill [port]` — stop dev server
- `lurk deploy` / `lurk deploy init` — deploy via SSH (systemd), Docker, or shell scripts
- `lurk new website` — scaffold a complete project
- `lurk add page` / `lurk add form` / `lurk add email` — interactive scaffolding
- `--help` flag on all commands

#### Templates
- Website scaffold with router, controller, locale, view, and default layout
- Public assets (CSS, JS, robots.txt, sitemap.xml, llms.txt)

#### Tests
- Test suite covering sessions, CSRF, flash messages, requests, QQ, logging, security headers, error handling, language detection, and SMTP
