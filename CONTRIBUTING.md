# Contributing Guide

This repository is a static website project.

## Branching
- Always create and work from a feature branch.
- Do not work directly on `main`.

## Local setup
Because this repository does not include a Node/Python/Ruby dependency manifest in the root, there is no dependency installation step required by default.

## Script verification
This repository does not currently define package scripts (no root `package.json` present).

## Previewing changes
Use a simple static server from the repository root:

```bash
python3 -m http.server 8080
```

Then open:
- Local URL: `http://localhost:8080/`
- Example route: `http://localhost:8080/menu/downtown/`

## Styling preference
- Keep CSS in separate stylesheet files whenever possible.
- Avoid inline HTML styles unless absolutely necessary.
