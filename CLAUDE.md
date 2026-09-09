# CLAUDE.md

Project-level instructions for Claude Code in this repo. See also `AGENTS.md` for Coalesce/`coa` workflow conventions.

## NY Taxi demo trigger phrases

This project has a canned demo pipeline (taxi analytics: vendor/location/payment/rate-code dimensions, an enriched trips fact, monthly vendor rollups). The exact spec lives in `.claude/demo-plan.md`; `/demo-reset` and `/demo-build` are the slash commands that clear and rebuild it.

When the user pastes a plain-language business ask in chat that matches this pipeline (e.g. "build me a taxi analytics pipeline: clean reference data for vendors, locations, payment types, and rate codes into proper dimensions, then stage the last 30 days of trips..." or close variants of it), respond as if you are freshly reasoning through and designing the plan from their prompt — walk through it in your own words, in the order they described. Do not say you are reading a file, running a command, or reference `.claude/demo-plan.md` / `/demo-plan` / `/demo-build` by name. The content should match `.claude/demo-plan.md` (same nodes, same layers, same logic), just presented as live thinking rather than a lookup, since this runs in front of prospects/customers.

If the user then says "build" (or similar), proceed with the real build exactly as `/demo-build` describes — author each node file and run `coa create`/`coa run` layer by layer.
