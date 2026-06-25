# PII governance

Normative types: [`../pii_catalog/pii_catalog.yml`](../pii_catalog/pii_catalog.yml) (version in file — short slugs such as `cpf`, `rg`, `cnh`; `classification` is `personal`, `sensitive`, or `highly_personal`).

## Roadmap

| Phase | Scope |
|-------|--------|
| **1** | Catalog, Yamale `columns.*.privacy`, `validate-pii-privacy`, RAE controls |
| **2** | Optional table-level `privacy.dataSubjectType`, lineage propagation checks, governance-domain pilot backfill |
| **3** | Metadata backfill PRs (YAML only), lineage-first local tooling |
| **Post-backfill** | Table `privacy.dataSubjectType` required in Yamale + CI hard fail |

## Declare PII (Phase 2 contract)

**Titular (who the data is about)** — optional until post-backfill gate; preferred format when classifying:

```yaml
privacy:
  dataSubjectType:
    - employee
    # add more lines when needed: - customer  - partner
```

**Type of personal data** — per column (or `jsonPaths`):

```yaml
columns:
  work_email:
    lineage:
      - datalake_pin_core_clean.person.work_email
    description: "Corporate email."
    privacy:
      piiType: corporate_email
```

- Table `privacy.dataSubjectType` is **optional** during Phase 2/3 backfill.
- List **includes `customer`** → customer PII masked in authX after metadata is on `master` (unless RAE in [`../pii_anonymization_controls/`](../pii_anonymization_controls/)).
- Production masking is configured in authX, not in this repo.

### Lineage-first classification

1. Classify **upstream** tables/columns first (raw → clean → enrich → dw).
2. For downstream columns, use `lineage` to inherit `piiType` from the source column.
3. Propagate **table** `dataSubjectType` from upstream datasets when the whole table is the same titular.
4. Use **column-level** `dataSubjectType` only as an override (e.g. mixed titular in one dataset).

### Legacy (Phase 1) column format

Still supported during migration:

```yaml
privacy:
  piiType: cpf
  dataSubjectType:
    - customer
```

Prefer moving `dataSubjectType` to the table `privacy` block when backfilling.

### JSON columns (`jsonPaths`)

```yaml
privacy:
  dataSubjectType:
    - customer
columns:
  person_payload:
    privacy:
      jsonPaths:
        - path: $.holder.cpf
          piiType: cpf
```

## CI

```bash
make validate-pii-privacy CI_COMMIT_BRANCH=<branch>
make validate-metadata-files-content CI_COMMIT_BRANCH=<branch>
```

Both run on **metadata files changed in the PR** (not the whole repo). Positive validation only: no `privacy` section → CI passes.

- **Branch / PR:** schema + lineage privacy mismatches on changed metadata files → **errors**.
- **All files (`-a`):** lineage issues → **warnings** (informational).

Classification backfill is done locally under `governance/pii/local/` (not committed); follow-up PRs contain **only** updated DAG metadata YAML.

## Where this lives (and what it is)

`governance/` (repo root) holds **normative policy-as-data** — not narrative docs, not Python:

- `pii_catalog/pii_catalog.yml` — the normative PII type catalog (CI-enforced).
- `pii_anonymization_controls/` — the RAE registry (CI-enforced).

Owned by `@quintoandar/data-ops-governance` (see `CODEOWNERS`). Do not confuse with the two other "governance" namespaces:

- `dags/governance/` — governance **pipelines** (DAGs).
- `packages/*/src/bietlejuice/governance/` — governance **Python code** (FAIR, anonymization).

The path is resolved once in `pii_privacy_checks.py` (`GOVERNANCE_POLICY_ROOT`), so relocating the folder is a one-line change there.
