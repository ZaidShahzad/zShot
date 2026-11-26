# zShot

An open source screenshot tool. macOS comes first.

## How we work

- Build with pstack (the `pstack@cursor-plugins` plugin, enabled in `.claude/settings.json`). Start a piece of work with `/pstack:poteto-mode`. Model choices for pstack roles are in `.claude/rules/pstack-models.md`.
- Before building a feature, align on it with `/grill-with-docs`. It keeps `GLOSSARY.md` and `docs/adr/` up to date.
- Write pull request bodies with the `pr` skill.
- Code is written on a Windows machine, but the macOS app can only be built and run on a Mac. Keep build and test steps runnable from macOS, and say in each PR what still needs checking on the Mac.
