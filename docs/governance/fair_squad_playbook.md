# FAIR metadata — squad playbook

How squads **audit** and **fix** metadata in bi-etl-ejuice.

## One rule

**FAIR audit or remediation → start with `@tars`.** Same thread: after the first `@tars` message you can say `pode executar` without repeating it.

## Three flows

| Goal | What to do | Cursor mode |
|------|------------|-------------|
| **Audit** by domain or owner | `@tars Audite FAIR do domain {folder}` (e.g. `for_rent`, `governance`) — escopo padrão: pasta `dags/{folder}/`; campo YAML: ver tabela em `fair-metadata/reference/domain_disambiguation.md` | Agent or Ask |
| **Fix** after reviewing the plan | `pode executar` (same thread, after plan posted) | **Agent** |
| **New table** in your PR | `create-metadata-files` + validators below | Any |

Skill: `.cursor/skills/fair-metadata/SKILL.md`

## Local validators (before push)

```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
```

- **Yamale** (`validate-metadata-files-content`) — schema: required fields, min length per layer.
- **FAIR CLI** (`validate-fair-metadata`) — F2-02 substantive column descriptions on clean+.
- **Lineage** — metadata `columns` ↔ paired SQL (sqlglot).

## PR bar vs lake tier

| When | What it checks |
|------|----------------|
| **Woodpecker on PR** | F2-02 on clean+ metadata in the diff |
| **Lake** (`fairness_assessment`) | Full tier + Platform checks; query via `@tars` |

Perfect metadata in a PR can still show tier &lt; 2 in the lake if Platform-owned checks fail — not a metadata-PR action.

## Owner ACTIVE — important

**CI verde ≠ owner ACTIVE.** Woodpecker does not call `org_chart`. Before merge, verify with `@tars` + `fair-metadata/sql/check_owner_active.sql`.

## CI failed on one file?

Use **`fix-ci-failure`** (SQL/declaration only; no `@tars` required) or fix manually. Bulk remediation → **`fair-metadata`** with `@tars`.

## References

- Authoring rules: `.cursor/rules/fairness_metadata.mdc`
- Glossary: `fair_requirement_glossary.md`
- Lake detail: `fair_metadata_remediation.md`
