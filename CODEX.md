# Ralph Agent Instructions

You are running inside Codex CLI as one fresh Ralph iteration.

## Your Task

1. Read the PRD at `prd.json` in the same directory as this file.
2. Read the progress log at `progress.txt` and check the `Codebase Patterns` section first.
3. Check you are on the correct branch from PRD `branchName`. If not, check it out or create it from `main`.
4. Pick the highest-priority user story where `passes: false`.
5. Implement that single user story.
6. Run the quality checks required by the project.
7. Update nearby `AGENTS.md` files if you discover reusable patterns.
8. If checks pass, commit all relevant changes with message: `feat: [Story ID] - [Story Title]`.
9. Update `prd.json` to set `passes: true` for the completed story.
10. Append your progress to `progress.txt`.

## Progress Report Format

Append to `progress.txt` and never replace earlier entries:

```text
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- Quality checks run
- Commit created
- Learnings for future iterations:
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

The learnings section is critical. Future Ralph iterations should be able to start from this file instead of depending on your current context window.

## Consolidate Patterns

If you discover a reusable pattern that future iterations should know, add it to the `## Codebase Patterns` section at the top of `progress.txt`.

Only add patterns that are general and reusable, not story-specific notes.

## Update AGENTS.md Files

Before committing, check whether edited areas have reusable learnings worth preserving in nearby `AGENTS.md` files:

- API or module conventions
- gotchas and hidden coupling
- testing expectations
- configuration requirements

Do not add story-specific notes or temporary debugging debris.

## Quality Requirements

- All committed changes must pass the relevant quality checks.
- Do not commit broken code.
- Keep changes focused and minimal.
- Follow existing code patterns.

## Browser Verification

For UI stories, verify behavior in a browser if browser tooling is available in the environment. If no browser tooling is available, note that manual browser verification is still required in `progress.txt`.

## Stop Condition

After completing one user story, check whether all stories now have `passes: true`.

If all stories are complete, reply with exactly:

```text
<promise>COMPLETE</promise>
```

If there are still stories with `passes: false`, end normally. Another fresh Ralph iteration will continue later.

## Important

- Work on one story per iteration.
- Read `progress.txt` before starting.
- Prefer durable memory in files and commits over relying on hidden context.
