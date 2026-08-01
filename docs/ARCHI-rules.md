# Architecture Documentation Rules

[ARCHI.md](ARCHI.md) documents the nvidia-container-spin-fix architecture. After each task (new feature, refactor, bug fix), determine if ARCHI.md needs updating.

## When to Update

Update after ANY change that alters:

- Project structure (new files, moved files) — §4 Project Structure
- Technology stack or platform assumptions (PowerShell version, new system tools invoked) — §3 Technology Stack
- Safety invariants or their scope — §5 Core Architecture Principles (owner-gated; never weaken silently)
- CLI modes, parameters, thresholds, or verdict logic — §8 Command Structure, §9 Target System Interaction Model
- Newly discovered failure modes or field-debugging knowledge — §10 Known Failure Modes
- Confirmed or contradicting hardware reports — §11 Compatibility Matrix
- Elevation, ownership/ACL, or worker-IPC behavior — §12 Elevation & Privilege Model
- GUI states, widgets, or event flow — §13 GUI Architecture
- User-facing copy ownership or tone rules — §15 Docs & UX Copy Map
- Error-handling or verification strategy — §17 Error Handling Strategy, §18 Testing Strategy
- Release assets, packaging, or versioning — §6 Build System, §21 Deployment, §22 Release Packaging Runbook
- Data flow between components — update the mermaid diagrams in §16

## How to Update by Change Type

### Major Feature / Refactor

Review: §2 Overview, §4 Project Structure, §5 Core Architecture Principles, §8 Command Structure, §9 Target System Interaction Model, §16 Data Flow Diagrams, §23 Conclusion

### Minor Feature / Enhancement

Update: the specific section(s) touched — most often §8–§15

### Bug Fix

Usually no update needed, unless it reveals a new failure mode (§10) or changes a compatibility conclusion (§11)

### Field Reports

New confirmed configurations, or reports contradicting the discovery/verdict logic: add rows and notes to §11 Compatibility Matrix

### Dependency Changes

The shipped scripts must not gain runtime dependencies (§5.4) — such a change needs the invariant itself revisited, which is owner-gated. Dev-tooling additions (e.g. PSScriptAnalyzer): update §18 Testing Strategy

## Guidelines

- Be precise and factual — reflect the actual scripts, not an idealized version
- Be concise — enough detail to understand, not implementation dumps
- Keep the intentional-duplication note (§4) true: if helpers are ever unified or allowed to diverge, document it
- Update diagrams when flows change
- Reference actual file paths
