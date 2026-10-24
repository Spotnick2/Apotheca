# Apotheca

Project instructions live in @AGENTS.md — read that file.

## Consulting Codex

The shared `codex-consult` skill (user level) has the invocation and the gotchas. For this repo:

For Apotheca specifically, good things to hand Codex: anything touching the secure buttons
(`RegisterForClicks`, `ApplySecureItemAttributes`, the waste-prevention ask overlay), an adapter in
`ApothecaCompat.lua` (especially struct-vs-tuple or a nil-means-unknown return), anything that reads
health, power, auras or cooldowns (all can be secret on this client), or a change to the
`ApothecaDB` profile shape.

**Always hand it `docs/FOREVER-PROBE.md` and `AGENTS.md` alongside the diff.** Those findings are
measured on the live client, and a cold reviewer will otherwise argue from Classic-era or Retail
behaviour that does not hold here - that the player's current health and mana are secret even out
of combat, that auras throw in combat, that SavedVariables never load, that the client's secure
handler decides which mouse edge acts. `C:/Projects/WoW/References/Forever/api/forever-api-<version>.<build>.md` (take the highest build) is the
full measured API surface if a question turns on whether something exists.
