# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit Agent `model`). Alias entries in a panel list still count toward its fan-out.
# Values are `<model> <effort>` for the Claude Code Agent tool: model `opus` (Opus 5.5), effort `high`.
# budget: medium (high)
feature, refactoring: opus high
bug-fix: opus high
perf-issue: opus high
hillclimb: opus high
judgment and prose: opus high
hardest tasks: opus high
how explorer: opus high
how explainer: opus high
why investigators: opus high
why synthesizer: opus high
reflect tooling: opus high
reflect judgment, divergent, synthesizer: opus high
arena runners: opus high, opus high
arena cross-judge pool: opus high, opus high
swarm workers: opus high
architect runners: opus high, opus high
interrogate reviewers: opus high, opus high
