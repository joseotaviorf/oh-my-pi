# FAIR requirement glossary (IDs → business language)

Technical IDs (`F2-01`, `I1-01`, …) appear in `checks_result_json` and lake tables. **Agents and domain / product line comms should prefer the business names below** when explaining gaps to non-engineers. Keep IDs in logs, SQL exports, and PR comments for engineers.

## FAIR letter prefix

| Prefix | Pillar | Business meaning |
|--------|--------|------------------|
| **F** | Findable | Can people discover the table and understand what it is? |
| **A** | Accessible | Can authorized people reach the data under policy? |
| **I** | Interoperable | Does documentation match reality and integrate with catalog/contracts? |
| **R** | Reusable | Can others trust and reuse the asset long-term? (higher tiers) |

## Tier labels (`tier_achieved` / `classification`)

| `tier_achieved` | `classification` (lake) | Business summary |
|-----------------|-------------------------|------------------|
| 0 | Not FAIR | Blocking gaps (metadata and/or platform catalog signals) |
| 1 | Findable, Accessible | Discoverable/reachable, but column docs or schema alignment still fail |
| 2 | Findable, Accessible, Interoperable | MVP program bar met (all scoped checks pass, including platform-owned) |
| 3–4 | … | Reserved; not emitted in current MVP mode |

A table can have perfect metadata and still show tier &lt; 2 if **platform-owned** checks fail — that is not a metadata-PR action item.

## Domain metadata scope (remediate in bi-etl-ejuice)

| ID | Business name | Typical fix |
|----|---------------|-------------|
| **F2-01** | Table-level catalog basics | `owner`, `domain`, table `description` in metadata YAML |
| **F2-02** | Column descriptions are useful | `columns.*.description` in metadata YAML |
| **I1-01** | Documentation matches physical table | `columns:` vs SQL / metastore; `validate-lineage-consistency` |
| **F1-01** | Table has a stable identity | `database_name`, `table_name` in metadata |

Often domain + platform together:

| ID | Business name | Who |
|----|---------------|-----|
| **F1-02** | Single pipeline owns the table | Platform / DE (inventory) |
| **F1-03** | Table exists in lake catalog | Deploy + platform metastore sync |

### F2-01 failure codes (`reason` in JSON)

| Code | Business wording |
|------|------------------|
| `owner_missing` | No table owner set |
| `owner_email_invalid_format` | Owner is not a valid corporate email |
| `owner_not_active_employee` | Owner is not an active employee in HR org chart |
| `domain_missing` | Data domain not set |
| `domain_not_in_allowlist` | Domain value not in approved list |
| `table_description_missing` | Table description empty |
| `table_description_not_substantive` | Table description too short or generic (echoes name/boilerplate) |

### F2-02 / I1-01 failure codes (common)

| Code | Business wording |
|------|------------------|
| `column_description_not_substantive` | Column descriptions too short or generic |
| `no_column_docs_in_lake` | No column documentation in the lake yet |
| `undocumented_columns` | Physical columns not documented |
| `documented_not_in_physical` | Documented columns not in the table |
| `spark_schema_not_in_columns_metastore_snapshot` | Table not in metastore snapshot yet (often pre-deploy) |

## Platform-owned (do not assign to metadata agents)

Still scored in `fairness_assessment`; **escalate to Platform** — no Cursor skill, no metadata PR playbook.

| ID | Business name | Owner |
|----|---------------|--------|
| **F4-01** | Table visible in DataHub | Platform (indexing / catalog) |
| **I1-02** | Data contract assigned | Platform (contracts on Databricks entity) |
| **A1.2-03** | Access policy signal (interim) | Platform |
| **I3-01** | Ownership in DataHub UI | Platform (observability; not MVP tier driver alone) |
| **I3-02** | Lineage in DataHub UI | Platform (same) |

When reporting to domains / product lines: *“Metadata fixes are done; remaining gaps are Platform catalog/contract — open Platform request.”*

## Agent communication rule

1. Read `checks_result_json` using **IDs** (machine source of truth).
2. For humans, use **business names** from the tables above; separate metadata vs platform actions.
3. Example: “**Column descriptions are not useful enough** — update `id_order`, `dt_signed` in metadata YAML.” Not: “fix F4-01”.
4. Remediation playbook (metadata only): `fair_metadata_remediation.md`, skill `fair-metadata/`, domains entry `fair_domains_playbook.md`.

## Related docs

- `fair_metadata_remediation.md`
- `.cursor/rules/fairness_metadata.mdc`
- `.cursor/skills/fair-metadata/reference/description_remediation.md`
