# Project Instructions

## Purpose

This is a learning project. Move slowly and explain what you are doing and why.

## Scope

- Only build for **dev** and **sb** environments unless explicitly asked for qa or prod.
- Do not scaffold qa/prod changes unless the user asks.

## Commit and PR workflow

- Before committing, ask the user if there is anything else to add or change.
- Before creating a PR, confirm with the user first.
- Never create a commit or PR without explicit confirmation.

## Commit messages and PRs

Never add `Co-Authored-By` or `Co-authored-by` trailers to commit messages or PR descriptions.
This project uses python-semantic-release to auto-generate CHANGELOG.md from commit bodies — any trailer added to a commit body will appear verbatim in the changelog.
