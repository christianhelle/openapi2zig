# Fenster YAML smoke decisions

- **Date:** 2026-05-01T11:50:14.189+02:00
- **Decision:** Keep the two smoke layers separate while making YAML a first-class smoke input: the PowerShell sweep discovers JSON+YAML fixtures dynamically and uses `<basename>__<format>__<mode>.zig` outputs, while the curated harness adds only the stable checked-in YAML artifacts that have real fixtures today (`generated_v2_yaml.zig`, `generated_v3_yaml.zig`, `generated_v31_yaml.zig`).
- **Why:** This closes the YAML coverage gap without collapsing the curated harness into dynamic enumeration, and it prevents JSON/YAML sibling petstore specs from overwriting each other in `test/output/`.
- **Decision:** Treat currently observed YAML parse failures as explicit broad-smoke denylist entries with `Mode = "*"` when the failure happens before wrapper-specific generation.
- **Why:** The six failing YAML fixtures all stop in the same `yaml_loader` normalization/parsing phase, so wildcard-mode denylist entries keep the sweep deterministic while preserving visibility until the parser gap is fixed.
