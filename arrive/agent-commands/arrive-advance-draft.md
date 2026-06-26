# ARRIVE Advance Draft

Generate or update an Advance file that documents the current change.

## Instructions

1. **Understand scope** from the conversation requirements and the current change:

```bash
arrive status
arrive score
```

2. **Render the canonical advance template** and use its `content` as the base — do not invent the structure (template-first authoring):

```bash
arrive template render --kind advance --json
```

3. **Author the advance from the requirements**, writing to `arrive/systems/<system>/advances/ADV-<COMPONENT>-NNN.md`. Fill Objective / Behavioral Change / Implementation Tasks / Risk + Rollback / Evidence from the conversation. (`arrive draft` is a scaffold/locator fallback and will **not** overwrite an existing advance.)

4. **Set time-tracking fields**:
   - `started_at` when the advance is created
   - `implementation_completed_at` when implementation finishes (or `~` if not done yet)

5. **Honor the org guardrails.** The always-applied `arrive-rules` (rendered by `arrive render --agent`) are **binding**: blocking/mandatory rules must hold. When implementing, run `arrive check --at pr` and `arrive advance attest`; if a blocking rule cannot be satisfied, **stop and surface it** (propose a time-boxed waiver) rather than violating it.

6. **If the advance already exists** (planned status):
   - Read the existing advance
   - Refine sections that need it
   - Don't overwrite the user's custom content

## Drafting Guidelines

### Objective
- One sentence explaining WHY this change exists
- Focus on the problem being solved, not the solution

### Behavioral Change
- Describe what's different AFTER this change ships
- Use "After this advance:" bullet format
- Be specific about observable changes

### Implementation Tasks
- Break into logical phases
- Include tidying, testing, and feature work
- Mark completed items as done

### Risk + Rollback
- Identify what could go wrong
- Describe how to undo the change
- Note any dependencies or migration concerns

### Evidence
- List verification methods
- Include test types (unit, integration, manual)
- Note any TDD/Tidy First practices used

## Expected Output Format

```
📝 Advance Draft

Created/Updated: arrive/systems/[system]/advances/ADV-[COMPONENT]-NNN.md

Summary:
├─ ID: ADV-[COMPONENT]-NNN
├─ Title: [descriptive title]
├─ System: [system-id]
├─ Components: [list]
└─ Score: XX [LEVEL]

Sections:
✓ Objective - [summary]
✓ Behavioral Change - [N bullet points]
✓ Implementation Tasks - [N tasks]
✓ Risk + Rollback - [identified]
✓ Evidence - [N items]

💡 Review the advance file and refine as needed.
```
