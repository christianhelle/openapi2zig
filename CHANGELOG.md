# Changelog

## [Unreleased Changes]

### Features
- Fix path argument order and slow 204 and 304 responses ([#125](https://github.com/christianhelle/openapi2zig/pull/125)) ([@christianhelle](https://github.com/christianhelle/))
- Return an error instead of crashing on a corrupt compressed response ([#123](https://github.com/christianhelle/openapi2zig/pull/123)) ([@christianhelle](https://github.com/christianhelle/))
- Add Linux and Windows ARM64 release targets and align the release with puny ([#124](https://github.com/christianhelle/openapi2zig/pull/124)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.6.1](https://github.com/christianhelle/openapi2zig/releases/tag/v0.6.1) (2026-11-05)

### Features
- Fix zig build install-release failing on the yaml size assertion ([#122](https://github.com/christianhelle/openapi2zig/pull/122)) ([@christianhelle](https://github.com/christianhelle/))
- Follow redirects safely and close provider generation gaps ([#121](https://github.com/christianhelle/openapi2zig/pull/121)) ([@christianhelle](https://github.com/christianhelle/))
- Remove unused code ([#118](https://github.com/christianhelle/openapi2zig/pull/118)) ([@christianhelle](https://github.com/christianhelle/))
- Fix provider schema generation and streaming parameters ([#120](https://github.com/christianhelle/openapi2zig/pull/120)) ([@h0rv](https://github.com/h0rv/))

### Closed Issues
- Pass method parameters as struct instead of individual arguments. ([#83](https://github.com/christianhelle/openapi2zig/issues/83)) ([@jcollie](https://github.com/jcollie/))


## [v0.6.0](https://github.com/christianhelle/openapi2zig/releases/tag/v0.6.0) (2026-10-12)

### Features
- Upgrade to Zig 0.17.0 ([#119](https://github.com/christianhelle/openapi2zig/pull/119)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.5.7](https://github.com/christianhelle/openapi2zig/releases/tag/v0.5.7) (2026-10-12)

### Merged Pull Requests
- Raise code coverage from 85.5% to 97% ([#116](https://github.com/christianhelle/openapi2zig/pull/116)) ([@christianhelle](https://github.com/christianhelle/))

### Features
- Embed the application icon into the openapi2zig binary ([#117](https://github.com/christianhelle/openapi2zig/pull/117)) ([@christianhelle](https://github.com/christianhelle/))
- Honour allOf in the OpenAPI 3.0 converter ([#115](https://github.com/christianhelle/openapi2zig/pull/115)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.5.6](https://github.com/christianhelle/openapi2zig/releases/tag/v0.5.6) (2026-09-04)

### Merged Pull Requests
- Expand library usage examples ([#112](https://github.com/christianhelle/openapi2zig/pull/112)) ([@christianhelle](https://github.com/christianhelle/))

### Features
- Generate camelCase function names from non-identifier operation ids ([#114](https://github.com/christianhelle/openapi2zig/pull/114)) ([@christianhelle](https://github.com/christianhelle/))
- Support large OpenAPI specifications ([#113](https://github.com/christianhelle/openapi2zig/pull/113)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.5.5](https://github.com/christianhelle/openapi2zig/releases/tag/v0.5.5) (2026-09-03)

### Features
- Cover the converter $ref branches and assert on leaks ([#111](https://github.com/christianhelle/openapi2zig/pull/111)) ([@christianhelle](https://github.com/christianhelle/))
- Expose the generate pipeline to library consumers ([#110](https://github.com/christianhelle/openapi2zig/pull/110)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.5.3](https://github.com/christianhelle/openapi2zig/releases/tag/v0.5.3) (2026-09-03)

### Features
- Fix incorrect commands and stale API references in the docs ([#109](https://github.com/christianhelle/openapi2zig/pull/109)) ([@christianhelle](https://github.com/christianhelle/))
- Fix skip-unchanged-output to survive CRLF checkouts ([#108](https://github.com/christianhelle/openapi2zig/pull/108)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.5.2](https://github.com/christianhelle/openapi2zig/releases/tag/v0.5.2) (2026-09-02)

### Merged Pull Requests
- Stop rewriting generated files that have not changed ([#106](https://github.com/christianhelle/openapi2zig/pull/106)) ([@christianhelle](https://github.com/christianhelle/))
- Preserve OpenAPI header parameters and fixed query parameters in generated clients ([#102](https://github.com/christianhelle/openapi2zig/pull/102)) ([@christianhelle](https://github.com/christianhelle/))

### Features
- Add runtime-only code generation ([#107](https://github.com/christianhelle/openapi2zig/pull/107)) ([@christianhelle](https://github.com/christianhelle/))
- Split the four largest source files into focused modules ([#105](https://github.com/christianhelle/openapi2zig/pull/105)) ([@christianhelle](https://github.com/christianhelle/))
- Generate provider-compatible API key authentication ([#104](https://github.com/christianhelle/openapi2zig/pull/104)) ([@christianhelle](https://github.com/christianhelle/))
- Interrupt stalled SSE reads when streaming is cancelled ([#100](https://github.com/christianhelle/openapi2zig/pull/100)) ([@christianhelle](https://github.com/christianhelle/))
- Add --runtime-only flag to generate just the runtime module ([#98](https://github.com/christianhelle/openapi2zig/pull/98)) ([@christianhelle](https://github.com/christianhelle/))
- Reuse existing runtime via --runtime-module ([#94](https://github.com/christianhelle/openapi2zig/pull/94)) ([@christianhelle](https://github.com/christianhelle/))
- Add install-release build steps ([#93](https://github.com/christianhelle/openapi2zig/pull/93)) ([@christianhelle](https://github.com/christianhelle/))
- Support inline cancellation of streaming SSE reads via Client.cancel_check ([#92](https://github.com/christianhelle/openapi2zig/pull/92)) ([@christianhelle](https://github.com/christianhelle/))
- Add --parameters-as-struct flag to wrap method parameters in a struct ([#91](https://github.com/christianhelle/openapi2zig/pull/91)) ([@christianhelle](https://github.com/christianhelle/))
- Allow keywords like `type` as struct field names while keeping them escaped in function arguments ([#90](https://github.com/christianhelle/openapi2zig/pull/90)) ([@christianhelle](https://github.com/christianhelle/))
- Fix failing zig fmt --check on generated code ([#89](https://github.com/christianhelle/openapi2zig/pull/89)) ([@christianhelle](https://github.com/christianhelle/))
- Simplify CI workflow ([#88](https://github.com/christianhelle/openapi2zig/pull/88)) ([@christianhelle](https://github.com/christianhelle/))
- Reserve Zig type keyword in generated identifiers ([#86](https://github.com/christianhelle/openapi2zig/pull/86)) ([@christianhelle](https://github.com/christianhelle/))

### Closed Issues
- Port generated provider runtime fixes from puny PR #161 ([#103](https://github.com/christianhelle/openapi2zig/issues/103)) ([@christianhelle](https://github.com/christianhelle/))
- Generate interruptible cancellation (CancelWatcher) for stalled SSE streams ([#99](https://github.com/christianhelle/openapi2zig/issues/99)) ([@christianhelle](https://github.com/christianhelle/))
- PRD: Preserve OpenAPI header parameters and fixed query parameters in generated clients ([#101](https://github.com/christianhelle/openapi2zig/issues/101)) ([@christianhelle](https://github.com/christianhelle/))
- "type" needs to be a reserved word ([#84](https://github.com/christianhelle/openapi2zig/issues/84)) ([@jcollie](https://github.com/jcollie/))


## [v0.5.0](https://github.com/christianhelle/openapi2zig/releases/tag/v0.5.0) (2026-08-20)

### Features
- Fix Windows self-upgrade failing with error.FileBusy ([#76](https://github.com/christianhelle/openapi2zig/pull/76)) ([@christianhelle](https://github.com/christianhelle/))
- Add build-time Zig coverage reporting and Codecov publishing ([#82](https://github.com/christianhelle/openapi2zig/pull/82)) (@Copilot)
- Add checksum-based change detection to avoid unnecessary timestamp updates ([#81](https://github.com/christianhelle/openapi2zig/pull/81)) ([@christianhelle](https://github.com/christianhelle/))
- Add --tag option to filter generated endpoints and models ([#80](https://github.com/christianhelle/openapi2zig/pull/80)) ([@christianhelle](https://github.com/christianhelle/))
- Add --multiple-clients flag for per-tag and per-endpoint client generation ([#79](https://github.com/christianhelle/openapi2zig/pull/79)) ([@christianhelle](https://github.com/christianhelle/))
- Add PerTag methods for operations without an operationId ([#78](https://github.com/christianhelle/openapi2zig/pull/78)) ([@christianhelle](https://github.com/christianhelle/))
- Add --file-name option to customize multi-file output names ([#77](https://github.com/christianhelle/openapi2zig/pull/77)) ([@christianhelle](https://github.com/christianhelle/))
- Add empty lines between headers and generated content ([#75](https://github.com/christianhelle/openapi2zig/pull/75)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.4.2](https://github.com/christianhelle/openapi2zig/releases/tag/v0.4.2) (2026-07-30)

### Features
- Remove --sse-buffer flag, default to large buffer sizes ([#74](https://github.com/christianhelle/openapi2zig/pull/74)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.4.1](https://github.com/christianhelle/openapi2zig/releases/tag/v0.4.1) (2026-07-29)

### Features
- Remove `type` from reserved keywords ([#68](https://github.com/christianhelle/openapi2zig/pull/68)) ([@christianhelle](https://github.com/christianhelle/))
- Add multi-file code generation support (--multiple-files) ([#73](https://github.com/christianhelle/openapi2zig/pull/73)) ([@christianhelle](https://github.com/christianhelle/))
- Update generated header indentation ([#72](https://github.com/christianhelle/openapi2zig/pull/72)) ([@christianhelle](https://github.com/christianhelle/))
- Remove vendor specific implementation details ([#71](https://github.com/christianhelle/openapi2zig/pull/71)) ([@christianhelle](https://github.com/christianhelle/))
- Configurable SSE buffer sizes ([#70](https://github.com/christianhelle/openapi2zig/pull/70)) ([@christianhelle](https://github.com/christianhelle/))
- Fix Anthropic spec compatibility ([#69](https://github.com/christianhelle/openapi2zig/pull/69)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.4.0](https://github.com/christianhelle/openapi2zig/releases/tag/v0.4.0) (2026-07-19)

### Features
- Add support for observing HTTP request/response ([#67](https://github.com/christianhelle/openapi2zig/pull/67)) ([@christianhelle](https://github.com/christianhelle/))
- Add <auto-generated> header to output file ([#66](https://github.com/christianhelle/openapi2zig/pull/66)) ([@christianhelle](https://github.com/christianhelle/))
- Add CancellationToken support for SSE streaming endpoints ([#65](https://github.com/christianhelle/openapi2zig/pull/65)) ([@christianhelle](https://github.com/christianhelle/))
- Change upgrade from option to command in CLI args ([#64](https://github.com/christianhelle/openapi2zig/pull/64)) ([@christianhelle](https://github.com/christianhelle/))
- Introduce --upgrade CLI argument ([#63](https://github.com/christianhelle/openapi2zig/pull/63)) ([@christianhelle](https://github.com/christianhelle/))

### Closed Issues
- application/octet-stream content ([#53](https://github.com/christianhelle/openapi2zig/issues/53)) ([@jayvdb](https://github.com/jayvdb/))
- Unable to use as a library. ([#43](https://github.com/christianhelle/openapi2zig/issues/43)) ([@jcollie](https://github.com/jcollie/))


## [v0.3.0](https://github.com/christianhelle/openapi2zig/releases/tag/v0.3.0) (2026-07-06)

### Merged Pull Requests
- Remove Squad ([#58](https://github.com/christianhelle/openapi2zig/pull/58)) ([@christianhelle](https://github.com/christianhelle/))
- Add missing GPA deinit assertions to binary payload tests ([#56](https://github.com/christianhelle/openapi2zig/pull/56)) (@Copilot)
- Add YAML verification to Smoke Tests ([#51](https://github.com/christianhelle/openapi2zig/pull/51)) ([@christianhelle](https://github.com/christianhelle/))
- Add Smoke Tests as part of PR verification ([#47](https://github.com/christianhelle/openapi2zig/pull/47)) ([@christianhelle](https://github.com/christianhelle/))

### Features
- Add support for Server-Sent-Events for operations with text/event-stream content-type ([#62](https://github.com/christianhelle/openapi2zig/pull/62)) ([@christianhelle](https://github.com/christianhelle/))
- Fix resource wrapper method name collisions when segment equals operation ID ([#61](https://github.com/christianhelle/openapi2zig/pull/61)) ([@christianhelle](https://github.com/christianhelle/))
- Reduce code duplication ([#60](https://github.com/christianhelle/openapi2zig/pull/60)) ([@christianhelle](https://github.com/christianhelle/))
- Add --models-only option ([#57](https://github.com/christianhelle/openapi2zig/pull/57)) ([@keeshux](https://github.com/keeshux/))
- Optional schema numeric bound parsing ([#59](https://github.com/christianhelle/openapi2zig/pull/59)) ([@christianhelle](https://github.com/christianhelle/))
- Add support for binary payloads ([#55](https://github.com/christianhelle/openapi2zig/pull/55)) ([@christianhelle](https://github.com/christianhelle/))
- Add YAML OpenAPI parsing ([#50](https://github.com/christianhelle/openapi2zig/pull/50)) ([@christianhelle](https://github.com/christianhelle/))

### Closed Issues
- Schema parsing assume float when integer is active in JSON object union ([#52](https://github.com/christianhelle/openapi2zig/issues/52)) ([@ForeverZer0](https://github.com/ForeverZer0/))


## [v0.2.0](https://github.com/christianhelle/openapi2zig/releases/tag/v0.2.0) (2026-04-30)

### Merged Pull Requests
- FIX: parse integer minimum values in v2.0 parameters ([#41](https://github.com/christianhelle/openapi2zig/pull/41)) ([@Boomatang](https://github.com/Boomatang/))
- Add full OpenAPI 3.1 support: parsing, converting, and code generation ([#42](https://github.com/christianhelle/openapi2zig/pull/42)) (@Copilot)
- Upgrade to Zig 0.15.2 ([#38](https://github.com/christianhelle/openapi2zig/pull/38)) ([@christianhelle](https://github.com/christianhelle/))
- Fix generated code compilation and remove unnecessary error unions ([#37](https://github.com/christianhelle/openapi2zig/pull/37)) (@Copilot)
- Update Zig version to 0.15.1 and fix related build issues ([#36](https://github.com/christianhelle/openapi2zig/pull/36)) ([@christianhelle](https://github.com/christianhelle/))
- Implement working GET methods ([#32](https://github.com/christianhelle/openapi2zig/pull/32)) ([@christianhelle](https://github.com/christianhelle/))
- Create comprehensive GitHub Copilot instructions for openapi2zig development ([#29](https://github.com/christianhelle/openapi2zig/pull/29)) (@Copilot)
- Generate API and Models from Swagger v2.0 ([#19](https://github.com/christianhelle/openapi2zig/pull/19)) ([@christianhelle](https://github.com/christianhelle/))

### Features
- Fix real-world OpenAPI code generation ([#46](https://github.com/christianhelle/openapi2zig/pull/46)) ([@h0rv](https://github.com/h0rv/))
- Upgrade to Zig 0.16.0 ([#45](https://github.com/christianhelle/openapi2zig/pull/45)) ([@h0rv](https://github.com/h0rv/))
- Add support for using remote URL with --input ([#44](https://github.com/christianhelle/openapi2zig/pull/44)) ([@christianhelle](https://github.com/christianhelle/))
- Add OpenAPI 3.2 specification support ([#40](https://github.com/christianhelle/openapi2zig/pull/40)) ([@christianhelle](https://github.com/christianhelle/))
- Fix missing requestBody when converting OpenAPI v3 to Unified OpenAPI Document ([#33](https://github.com/christianhelle/openapi2zig/pull/33)) ([@christianhelle](https://github.com/christianhelle/))
- Fix incorrect generated function return types ([#31](https://github.com/christianhelle/openapi2zig/pull/31)) ([@christianhelle](https://github.com/christianhelle/))
- Expose OpenAPI/Swagger parsing as library and documentation updates ([#30](https://github.com/christianhelle/openapi2zig/pull/30)) ([@christianhelle](https://github.com/christianhelle/))
- Cleanup AI Agent code mess ([#27](https://github.com/christianhelle/openapi2zig/pull/27)) ([@christianhelle](https://github.com/christianhelle/))
- House Keeping ([#26](https://github.com/christianhelle/openapi2zig/pull/26)) ([@christianhelle](https://github.com/christianhelle/))
- Add tests for unified document conversion ([#25](https://github.com/christianhelle/openapi2zig/pull/25)) ([@christianhelle](https://github.com/christianhelle/))
- Unified OpenAPI Document ([#24](https://github.com/christianhelle/openapi2zig/pull/24)) ([@christianhelle](https://github.com/christianhelle/))
- Fix missing memory leaks in generated code example ([#23](https://github.com/christianhelle/openapi2zig/pull/23)) ([@christianhelle](https://github.com/christianhelle/))
- Fix memory leaks and improve resource management ([#22](https://github.com/christianhelle/openapi2zig/pull/22)) ([@christianhelle](https://github.com/christianhelle/))
- Fix Memory Leaks when generating code from Swagger v2.0 ([#21](https://github.com/christianhelle/openapi2zig/pull/21)) ([@christianhelle](https://github.com/christianhelle/))
- Setup Dev Container ([#20](https://github.com/christianhelle/openapi2zig/pull/20)) ([@christianhelle](https://github.com/christianhelle/))
- Restructure code generation and tests ([#18](https://github.com/christianhelle/openapi2zig/pull/18)) ([@christianhelle](https://github.com/christianhelle/))

### Closed Issues
- Upgrade Zig to version 0.15.1 and address breaking changes ([#34](https://github.com/christianhelle/openapi2zig/issues/34)) ([@christianhelle](https://github.com/christianhelle/))
- Setup CoPilot Instructions ([#28](https://github.com/christianhelle/openapi2zig/issues/28)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.1.1](https://github.com/christianhelle/openapi2zig/releases/tag/v0.1.1) (2025-07-21)

### Merged Pull Requests
- Update code examples in docs ([#14](https://github.com/christianhelle/openapi2zig/pull/14)) ([@christianhelle](https://github.com/christianhelle/))
- Add support for specifying the base URL for all requests ([#12](https://github.com/christianhelle/openapi2zig/pull/12)) ([@christianhelle](https://github.com/christianhelle/))
- fix: add extension validation ([#11](https://github.com/christianhelle/openapi2zig/pull/11)) ([@rafaelsousa](https://github.com/rafaelsousa/))

### Features
- Detect OpenAPI Version ([#17](https://github.com/christianhelle/openapi2zig/pull/17)) ([@christianhelle](https://github.com/christianhelle/))
- Add Swagger v2.0 parsing support ([#15](https://github.com/christianhelle/openapi2zig/pull/15)) ([@christianhelle](https://github.com/christianhelle/))
- Implement version_info.zig generation in build.zig ([#16](https://github.com/christianhelle/openapi2zig/pull/16)) ([@christianhelle](https://github.com/christianhelle/))
- Show Version Information ([#13](https://github.com/christianhelle/openapi2zig/pull/13)) ([@christianhelle](https://github.com/christianhelle/))

### Closed Issues
- Implement OpenAPI v3.0 data structures and deserialization test ([#7](https://github.com/christianhelle/openapi2zig/issues/7)) ([@christianhelle](https://github.com/christianhelle/))
- Implement OpenAPI v3.0 data structures ([#9](https://github.com/christianhelle/openapi2zig/issues/9)) ([@christianhelle](https://github.com/christianhelle/))


## [v0.1.0](https://github.com/christianhelle/openapi2zig/releases/tag/v0.1.0) (2025-07-15)

### Merged Pull Requests
- Fix memory management issues causing segmentation fault in OpenAPI parsing ([#2](https://github.com/christianhelle/openapi2zig/pull/2)) (@Copilot)
- Create README and LICENSE files with project description and badges ([#6](https://github.com/christianhelle/openapi2zig/pull/6)) (@Copilot)
- Setup comprehensive CI/CD pipeline for pull request verification ([#4](https://github.com/christianhelle/openapi2zig/pull/4)) (@Copilot)

### Closed Issues
- Fix failing test: can deserialize petstore into OpenApiDocument ([#1](https://github.com/christianhelle/openapi2zig/issues/1)) ([@christianhelle](https://github.com/christianhelle/))
- Create README and LICENSE (MIT license) files with project description and badges ([#5](https://github.com/christianhelle/openapi2zig/issues/5)) ([@christianhelle](https://github.com/christianhelle/))
- Setup CI/CD pipeline for pull request verification ([#3](https://github.com/christianhelle/openapi2zig/issues/3)) ([@christianhelle](https://github.com/christianhelle/))


---
***This changelog was generated with [chlogr](https://github.com/christianhelle/chlogr). Any changes to this file will be overwritten.***