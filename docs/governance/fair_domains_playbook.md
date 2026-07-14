# FAIR metadata — domains playbook

How **domains and product lines** **audit** and **fix** metadata in bi-etl-ejuice.

## One rule

**FAIR audit or remediation → skill `fair-metadata`** (Trino via `trino/SKILL.md`, not `@tars`).

## Three flows

| Goal | What to do | Cursor mode |
|------|------------|-------------|
| **Audit** by domain or owner | `Audit FAIR for domain {folder}` (e.g. `for_rent`, `governance`) — default scope: folder `dags/{folder}/`; YAML `domain:` field: see mapping table in `fair-metadata/reference/domain_disambiguation.md` | Agent or Ask |
| **Fix** after reviewing the plan | `go ahead` (same thread, after plan posted) | **Agent** |
| **New table** in your PR | `create-metadata-files` + validators below | Any |

Skill: `.cursor/skills/fair-metadata/SKILL.md`

## Local validators (before push)

```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
```

- **Yamale** (`validate-metadata-files-content`) — schema: required fields, min length per layer.
- **FAIR CLI** (`validate-fair-metadata`) — F2-01 substantive table + F2-02 substantive column descriptions on clean+.
- **Lineage** — metadata `columns` ↔ paired SQL (sqlglot).

## PR bar vs lake tier

| When | What it checks |
|------|----------------|
| **Woodpecker on PR** | F2-01 table + F2-02 column substantive descriptions on clean+ metadata in the diff |
| **Lake** (`fairness_assessment`) | Full tier + Platform checks; query via `trino/SKILL.md` |

Perfect metadata in a PR can still show tier &lt; 2 in the lake if Platform-owned checks fail — not a metadata-PR action.

## Owner ACTIVE — important

**Green CI ≠ ACTIVE owner.** Woodpecker does not call `org_chart`. Before merge, verify with `trino/SKILL.md` + `fair-metadata/sql/check_owner_active.sql`.

On the **first FAIR audit turn**, follow **`fair-metadata/reference/owner_remediation.md`** (Trino kick-off): call **`mcp_auth`** when the Trino MCP plugin is enabled, before posting a plan with UNVERIFIED owners.

## CI failed on one file?

Use **`fix-ci-failure`** (SQL/declaration only) or fix manually. Bulk remediation → **`fair-metadata`**.

## References

- Domain allowlist SSOT: `packages/bietlejuice-core/src/bietlejuice/governance/domains.yml` (read via `bietlejuice.governance.domain_registry`)
- Authoring rules: `.cursor/rules/fairness_metadata.mdc`
- Glossary: `fair_requirement_glossary.md`
- Lake detail: `fair_metadata_remediation.md`
