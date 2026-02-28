# Changelog

## [Unreleased](https://github.com/christianhelle/openapi2zig/tree/HEAD)

[Full Changelog](https://github.com/christianhelle/openapi2zig/compare/v0.1.1...HEAD)

**Implemented enhancements:**

- Add OpenAPI 3.2 specification support [\#40](https://github.com/christianhelle/openapi2zig/pull/40) ([christianhelle](https://github.com/christianhelle))
- Fix missing requestBody when converting OpenAPI v3 to Unified OpenAPI Document [\#33](https://github.com/christianhelle/openapi2zig/pull/33) ([christianhelle](https://github.com/christianhelle))
- Fix incorrect generated function return types [\#31](https://github.com/christianhelle/openapi2zig/pull/31) ([christianhelle](https://github.com/christianhelle))
- Expose OpenAPI/Swagger parsing as library and documentation updates [\#30](https://github.com/christianhelle/openapi2zig/pull/30) ([christianhelle](https://github.com/christianhelle))
- Cleanup AI Agent code mess [\#27](https://github.com/christianhelle/openapi2zig/pull/27) ([christianhelle](https://github.com/christianhelle))
- House Keeping [\#26](https://github.com/christianhelle/openapi2zig/pull/26) ([christianhelle](https://github.com/christianhelle))
- Add tests for unified document conversion [\#25](https://github.com/christianhelle/openapi2zig/pull/25) ([christianhelle](https://github.com/christianhelle))
- Unified OpenAPI Document [\#24](https://github.com/christianhelle/openapi2zig/pull/24) ([christianhelle](https://github.com/christianhelle))
- Fix missing memory leaks in generated code example [\#23](https://github.com/christianhelle/openapi2zig/pull/23) ([christianhelle](https://github.com/christianhelle))
- Fix memory leaks and improve resource management [\#22](https://github.com/christianhelle/openapi2zig/pull/22) ([christianhelle](https://github.com/christianhelle))
- Fix Memory Leaks when generating code from Swagger v2.0 [\#21](https://github.com/christianhelle/openapi2zig/pull/21) ([christianhelle](https://github.com/christianhelle))
- Setup Dev Container [\#20](https://github.com/christianhelle/openapi2zig/pull/20) ([christianhelle](https://github.com/christianhelle))
- Restructure code generation and tests [\#18](https://github.com/christianhelle/openapi2zig/pull/18) ([christianhelle](https://github.com/christianhelle))

**Closed issues:**

- Upgrade Zig to version 0.15.1 and address breaking changes [\#34](https://github.com/christianhelle/openapi2zig/issues/34)
- Setup CoPilot Instructions [\#28](https://github.com/christianhelle/openapi2zig/issues/28)

**Merged pull requests:**

- Add full OpenAPI 3.1 support: parsing, converting, and code generation [\#42](https://github.com/christianhelle/openapi2zig/pull/42) ([Copilot](https://github.com/apps/copilot-swe-agent))
- Upgrade to Zig 0.15.2 [\#38](https://github.com/christianhelle/openapi2zig/pull/38) ([christianhelle](https://github.com/christianhelle))
- Fix generated code compilation and remove unnecessary error unions [\#37](https://github.com/christianhelle/openapi2zig/pull/37) ([Copilot](https://github.com/apps/copilot-swe-agent))
- Update Zig version to 0.15.1 and fix related build issues [\#36](https://github.com/christianhelle/openapi2zig/pull/36) ([christianhelle](https://github.com/christianhelle))
- Implement working GET methods [\#32](https://github.com/christianhelle/openapi2zig/pull/32) ([christianhelle](https://github.com/christianhelle))
- Create comprehensive GitHub Copilot instructions for openapi2zig development [\#29](https://github.com/christianhelle/openapi2zig/pull/29) ([Copilot](https://github.com/apps/copilot-swe-agent))
- Generate API and Models from Swagger v2.0 [\#19](https://github.com/christianhelle/openapi2zig/pull/19) ([christianhelle](https://github.com/christianhelle))

## [v0.1.1](https://github.com/christianhelle/openapi2zig/tree/v0.1.1) (2025-07-21)

[Full Changelog](https://github.com/christianhelle/openapi2zig/compare/v0.1.0...v0.1.1)

**Implemented enhancements:**

- Implement OpenAPI v3.0 data structures [\#9](https://github.com/christianhelle/openapi2zig/issues/9)
- Implement OpenAPI v3.0 data structures and deserialization test [\#7](https://github.com/christianhelle/openapi2zig/issues/7)
- Detect OpenAPI Version [\#17](https://github.com/christianhelle/openapi2zig/pull/17) ([christianhelle](https://github.com/christianhelle))
- Implement version\_info.zig generation in build.zig [\#16](https://github.com/christianhelle/openapi2zig/pull/16) ([christianhelle](https://github.com/christianhelle))
- Add Swagger v2.0 parsing support [\#15](https://github.com/christianhelle/openapi2zig/pull/15) ([christianhelle](https://github.com/christianhelle))
- Show Version Information [\#13](https://github.com/christianhelle/openapi2zig/pull/13) ([christianhelle](https://github.com/christianhelle))

**Merged pull requests:**

- Update code examples in docs [\#14](https://github.com/christianhelle/openapi2zig/pull/14) ([christianhelle](https://github.com/christianhelle))
- Add support for specifying the base URL for all requests [\#12](https://github.com/christianhelle/openapi2zig/pull/12) ([christianhelle](https://github.com/christianhelle))
- fix: add extension validation [\#11](https://github.com/christianhelle/openapi2zig/pull/11) ([rafaelsousa](https://github.com/rafaelsousa))

## [v0.1.0](https://github.com/christianhelle/openapi2zig/tree/v0.1.0) (2025-07-15)

[Full Changelog](https://github.com/christianhelle/openapi2zig/compare/936e59ff4645eee35f59b2da32ec2287661a2a2b...v0.1.0)

**Fixed bugs:**

- Fix failing test: can deserialize petstore into OpenApiDocument [\#1](https://github.com/christianhelle/openapi2zig/issues/1)

**Closed issues:**

- Create README and LICENSE \(MIT license\) files with project description and badges [\#5](https://github.com/christianhelle/openapi2zig/issues/5)
- Setup CI/CD pipeline for pull request verification [\#3](https://github.com/christianhelle/openapi2zig/issues/3)

**Merged pull requests:**

- Create README and LICENSE files with project description and badges [\#6](https://github.com/christianhelle/openapi2zig/pull/6) ([Copilot](https://github.com/apps/copilot-swe-agent))
- Setup comprehensive CI/CD pipeline for pull request verification [\#4](https://github.com/christianhelle/openapi2zig/pull/4) ([Copilot](https://github.com/apps/copilot-swe-agent))
- Fix memory management issues causing segmentation fault in OpenAPI parsing [\#2](https://github.com/christianhelle/openapi2zig/pull/2) ([Copilot](https://github.com/apps/copilot-swe-agent))



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
