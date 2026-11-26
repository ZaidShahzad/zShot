# Vendored skills

These skills are copied from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, see each folder's `LICENSE`) at commit `6f7f7831a625f040a8e06a0e7954826b87ce775a`.

| Skill | Upstream path |
| --- | --- |
| `grill-with-docs` | `skills/engineering/grill-with-docs` |
| `grilling` | `skills/productivity/grilling` (called by `grill-with-docs`) |
| `domain-modeling` | `skills/engineering/domain-modeling` (called by `grill-with-docs`) |
| `pr` | `skills/engineering/pr` (its `CREDITS.md` attributes content from Dex Horthy's `show-me` skill) |

The upstream `agents/openai.yaml` files (Codex metadata) are left out.

pstack is not vendored. It is installed as a project-scoped Claude Code plugin through `.claude/settings.json` (`pstack@cursor-plugins` from the `cursor/plugins` marketplace). Its model choices live in `.claude/rules/pstack-models.md`.
