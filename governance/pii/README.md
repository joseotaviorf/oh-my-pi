# PII governance (phase 1)

Normative types: [`../pii_catalog/pii_catalog.yml`](../pii_catalog/pii_catalog.yml) (version in file — short slugs such as `cpf`, `rg`, `cnh`; `classification` is `personal`, `sensitive`, or `highly_personal`).

Declare PII per column in `dags/**/metadata/**/*.yml`:

```yaml
privacy:
  piiType: cpf                  # slug from pii_catalog.yml
  dataSubjectType: [customer]   # customer | employee | partner
```

- No `privacy` section → not declared as PII (CI passes).
- `customer` → masked in authX after metadata is on `master` (unless RAE in [`../pii_anonymization_controls/`](../pii_anonymization_controls/)).
- Production masking is configured in authX, not in this repo.

## CI

```bash
make validate-pii-privacy CI_COMMIT_BRANCH=<branch>
make validate-metadata-files-content CI_COMMIT_BRANCH=<branch>
```

Classification backfill is done locally; follow-up PRs contain **only** updated DAG metadata YAML.

## Where this lives (and what it is)

`governance/` (repo root) holds **normative policy-as-data** — not narrative docs, not Python:

- `pii_catalog/pii_catalog.yml` — the normative PII type catalog (CI-enforced).
- `pii_anonymization_controls/` — the RAE registry (CI-enforced).

Owned by `@quintoandar/data-ops-governance` (see `CODEOWNERS`). Do not confuse with the two other "governance" namespaces:

- `dags/governance/` — governance **pipelines** (DAGs).
- `packages/*/src/bietlejuice/governance/` — governance **Python code** (FAIR, anonymization).

The path is resolved once in `pii_privacy_checks.py` (`GOVERNANCE_POLICY_ROOT`), so relocating the folder is a one-line change there.
