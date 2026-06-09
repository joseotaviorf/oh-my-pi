# FAIR metadata remediation — lake reference

Lake-side detail for **metadata agents** and engineers. Squads start at **`fair_squad_playbook.md`**.

**Out of scope (Platform):** F4-01, I1-02, A1.2-03, I3-01, I3-02 — escalate when metadata is correct and only these fail. See `fair_requirement_glossary.md`.

## Lake tables

| Table | Use for remediation? |
|-------|------------------------|
| `datalake_fairness_assessment.fairness_assessment` | **Yes** — `checks_result_json`, `tier_achieved`, `ts_assessed` |
| `datalake_fairness_assessment.fairness_classification` | **No alone** — join to `fairness_assessment` on `ts_assessed` |

Always parse **`checks_result_json`** from the latest `ts_assessed` per FQN. Do not fix from `classification` alone.

## When to use lake vs offline CLI

| Situation | Source |
|-----------|--------|
| Row in latest `enrich_fairness_assessment` run | `checks_result_json` + glossary (metadata-squad IDs only) |
| No assessment row | `make validate-fair-metadata` / `validate-lineage-consistency` for that FQN only |

## Metadata-squad IDs in `checks_result_json`

See **`fair_requirement_glossary.md`** for business names and fix guidance (F2-01, F2-02, I1-01, F1-*).

## Production cadence

`enrich_fairness_assessment` runs after `documentation_metrics` (~1 day after metadata deploy).

## Agents

Skill: `.cursor/skills/fair-metadata/SKILL.md` — requires **`@tars`**, PLAN gate in `reference/plan_gate.md`.
