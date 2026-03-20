# openapi2zig — Squad Team Initialized

**Date:** 2026-03-20  
**User:** Christian Helle  
**Project:** CLI tool for generating type-safe Zig API clients from OpenAPI/Swagger specs

## Team Roster

| Role | Name | Domain |
|------|------|--------|
| 🏗️ Lead | **Lando** | Architecture, scope, code review |
| 🔧 Backend | **Fenster** | Parser, converters, code generation |
| ⚛️ Frontend | **Juno** | CLI, output formatting, UX |
| 🧪 Tester | **Starkiller** | Test cases, both v2.0 & v3.0 coverage |
| 📋 Logger | **Scribe** | Decisions, memory, logs (automatic) |
| 🔄 Monitor | **Ralph** | Backlog tracking, work queue |

## Key Principles

- **Unified converter pattern:** Parse → normalize → generate (parse → version-specific models → unified document → code generation)
- **Memory safety:** All dynamic structs have `deinit(allocator)`. Always `defer parsed.deinit(allocator)`.
- **Both-spec coverage:** Every feature must work with Swagger v2.0 AND OpenAPI v3.0
- **Test-first:** Starkiller writes test cases from specs. Fenster implements. Lando reviews for architecture.

## Squad Structure

```
.squad/
├── team.md                 # Roster & context (you are here)
├── routing.md              # Work assignment rules
├── decisions.md            # Team decisions & context
├── casting/
│   ├── policy.json         # Universe config (Star Wars Extended)
│   ├── registry.json       # Persistent name mapping
│   └── history.json        # Assignment snapshots
├── agents/
│   ├── lando/              # Charter & history
│   ├── fenster/
│   ├── juno/
│   ├── starkiller/
│   ├── scribe/
│   └── ralph/
├── decisions/inbox/        # Agent decision drop-box (merged by Scribe)
├── orchestration-log/      # Agent work logs (append-only)
├── log/                    # Session logs (append-only)
└── skills/                 # Reusable patterns & expertise
```

## Next Steps

1. **Start work:** Christian, give the team a task: `"Lando, ..."` or `"Team, ..."` or `"Ralph, go"`
2. **Check issues:** `"Ralph, status"` to see GitHub backlog, or `"Ralph, go"` to activate continuous monitoring
3. **Get context:** `"What did the team do?"` for a catch-up summary

**Ready to work!** Try: **"Lando, set up the initial squad state"** or tell us what you're building next.
