# State
task: <one sentence>
class: <type> / <S|M|L|XL> / <impact>
modules: <Name: recipe>, …
plan: none | .ai/plans/<id>.md
adrs: none
base: <git sha at start>
sha: <git sha at last handoff>
tool: copilot | claude-code
phase: research | architecture | plan | data | implement | test | review | done | stopped
gate: G0 | G1 | G2 | G3 — passed | waiting | failed
steps: done 0/<total> | current 1 | status green
review_cycles: 0
next: <one imperative line, executable without chat history>

## decisions
- <chat-only agreement, one line>

## notes
- <≤ 10-line research digests, only what later phases need>

## log
- <yyyy-mm-dd hh:mm> <tool> <phase> <result>
