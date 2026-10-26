# Capture notes

## Final Duo source set

All 16 `duo-*.png` originals were captured from the running Voteaxis app using
Device Hub's native Screenshot action, at the actual display resolution.
The system export was used because the simulator MCP screenshot preview was
reduced to 800 pixels and captured an inactive black display.

The app was exercised on outer portrait, outer landscape, inner portrait, and
inner landscape. The final quiz capture shows the first question with Neutral
selected. Results and matches come from completing the full 25-question sample
run, with Neutral responses, standard importance, and no dealbreakers. National
matches are selected for the final matches captures.

## Separate app issue observed

With a manually placed Center 0 profile, opening Matches on the Duo outer
landscape display produced a yellow/black Flutter overflow indicator at the
bottom. The manual-placement explanatory banner consumed vertical space above
the matches controls. This app issue was not changed as part of the graphics
task. The final source and marketing images use completed-quiz results, which
were visually checked without that indicator.

Reproduction: Set your level by hand → Use this level → Matches → fold to the
outer display → rotate to 2034 × 1398 landscape. Recheck this path separately
before release if manual placement must work in that orientation.
