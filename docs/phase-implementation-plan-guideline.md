# Phase Implementation Plan Guideline

Use this guideline before writing an implementation plan for any phase of the SnowRunner Tools macOS CLI.

Each phase plan should answer one question:

```text
What is the smallest independently verifiable slice of the tool we can build next?
```

## Required Sections

Every phase implementation plan must include these sections.

## Phase Goal

Write one sentence that describes observable behavior, not internal effort.

Good:

```text
Phase 1 builds read-only PAK inspection and verification; it does not write PAK files.
```

Weak:

```text
Implement ZIP parser utilities.
```

## Non-Goals

List what this phase explicitly will not do.

This prevents scope creep and keeps phase boundaries honest.

Example:

```text
- No `pak pack`.
- No `cache_block` unpacking or packing.
- No `pak.load_list` mutation.
- No game-launch acceptance test because this phase emits no candidate PAK.
```

## Inputs And Fixtures

List the exact fixture files required by the phase.

For each fixture, state what fact it proves.

Example:

```text
- `fixtures/initial.pak`: original game layout; many stored entries; first entry is stored `pak.load_list`.
- `fixtures/initial.repacked.pak`: SnowPakTool-compatible repack layout; only `pak.load_list` is stored.
```

If a fixture does not exist yet, the phase plan must say whether the fixture is required before implementation starts or only before later acceptance testing.

## Commands To Deliver

List the exact CLI commands introduced or changed by the phase.

Example:

```text
snowrunner-tool pak inspect <pak>
snowrunner-tool pak verify-basic <pak>
snowrunner-tool pak verify-content-equivalent <reference.pak> <candidate.pak>
snowrunner-tool pak verify-snowpak-layout <pak>
```

Do not list future commands unless the phase actually implements them.

## Code Structure

List exact Swift Package Manager files to create or modify.

Each file needs one clear responsibility.

Example:

```text
- Create `Package.swift`: Swift Package Manager manifest for the CLI and tests.
- Create `Sources/SnowRunnerTool/main.swift`: process entry point.
- Create `Sources/SnowRunnerTool/CLI.swift`: command parsing and dispatch.
- Create `Sources/SnowRunnerTool/Pak/ZipHeaders.swift`: binary ZIP header structs and little-endian parsing helpers.
- Create `Sources/SnowRunnerTool/Pak/PakReader.swift`: read local headers, central directory, and EOCD.
- Create `Sources/SnowRunnerTool/Pak/PakVerifier.swift`: verifier checks and report formatting.
```

Prefer focused files over large mixed-responsibility files.

## Implementation Tasks

Break the phase into ordered, bite-sized tasks.

Each task must include:

- files touched
- the test to write first
- the minimal implementation
- the verification command
- a commit point

Tasks should be small enough that one task can be reviewed independently.

## Test Strategy

Describe the test layers for the phase.

Use this default structure unless the phase has a specific reason not to:

- Unit tests for small binary parsing helpers.
- Fixture tests against known PAK files.
- Negative tests for malformed or unsupported headers where practical.
- CLI tests for command exit codes and important output.
- Game-launch tests only for phases that emit a candidate game PAK.

Tests must prove the behavior that acceptance criteria depend on.

## Acceptance Criteria

List concrete commands and expected results.

Example:

```bash
swift test
swift run snowrunner-tool pak verify-basic fixtures/initial.pak
swift run snowrunner-tool pak verify-basic fixtures/initial.repacked.pak
swift run snowrunner-tool pak verify-content-equivalent fixtures/initial.pak fixtures/initial.repacked.pak
swift run snowrunner-tool pak verify-snowpak-layout fixtures/initial.repacked.pak
```

If a command is expected to fail, state the exact reason.

Example:

```text
`verify-snowpak-layout fixtures/initial.pak` must fail only for expected layout-policy differences:
order and non-`pak.load_list` stored entries.
```

## Risks

List known tricky parts and how the phase proves or contains them.

Example:

```text
- Raw deflate: prove by inflating all deflated fixture entries and matching CRC32.
- CP437 filenames: current fixtures are ASCII; implement ASCII fast path and fail clearly on non-ASCII until CP437 table is added.
- Header consistency: compare central directory metadata against local headers for every entry.
```

Do not hide major uncertainty inside implementation tasks.

## Stop Rule

A phase is complete only when all acceptance commands pass.

Do not start the next phase because the current phase "looks close".

If acceptance exposes a format misunderstanding, update the phase plan before continuing.

## Project-Specific Rules

Every phase plan must preserve the boundary between format knowledge and feature work.

- Phase 1 proves read-only PAK parsing and verification.
- Phase 2 proves PAK writing.
- Phase 3 proves `cache_block`.
- Phase 4 proves `pak.load_list`.

No phase should quietly implement part of a later format unless it is required for the current phase's acceptance criteria.

Every phase plan must also preserve these decisions from the top-level plan:

- Language: Swift.
- Build system: Swift Package Manager.
- Project format: no hand-managed `.xcodeproj`.
- Target: macOS only.
- Final PAK output: custom writer, no high-level ZIP writer.
- Internal PAK paths: backslash separators.
- Filesystem paths: normal macOS slash-separated paths.
- Filename encoding: CP437 with no ZIP UTF-8 flag.
- Compression: ZIP-compatible raw deflate.
