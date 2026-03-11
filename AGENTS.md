# Ralph Codex Notes

## Overview

This repository is a Codex-first fork of Ralph. The goal is to preserve the `snarktank/ralph` workflow shape while making `Codex CLI` the primary execution engine.

Each Ralph iteration should still be a fresh agent run with durable memory in:

- git history
- `progress.txt`
- `prd.json`

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph with Codex (default)
./ralph.sh [max_iterations]

# Run Ralph with Codex explicitly
./ralph.sh --tool codex [max_iterations]

# Run Ralph with Claude Code
./ralph.sh --tool claude [max_iterations]
```

## Key Files

- `ralph.sh` - The bash loop that spawns fresh AI instances (supports `--tool codex`, `--tool amp`, `--tool claude`)
- `CODEX.md` - Instructions given to each Codex iteration
- `prompt.md` - Instructions given to each Amp iteration
- `CLAUDE.md` - Instructions given to each Claude Code iteration
- `prd.json.example` - Example PRD format
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

## Flowchart

The `flowchart/` directory contains an interactive visualization built with React Flow. It's designed for presentations - click through to reveal each step with animations.

To run locally:
```bash
cd flowchart
npm install
npm run dev
```

## Patterns

- Each iteration spawns a fresh AI instance with clean context
- Memory persists via git history, `progress.txt`, and `prd.json`
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations
- Codex is the default execution path in this fork
