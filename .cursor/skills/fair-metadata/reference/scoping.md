# Scoping FAIR audits and remediation

**Scope = exactly what the user asked for.** Build a **closed inventory** of metadata YAML paths, then run Gates A/B/C per [`SKILL.md`](../SKILL.md) on **every file in that inventory**.

Do **not** substitute PR diff, CI-changed files, or BugBot comment paths for scope.

> **Repo folder vs YAML `domain:`** — the CLI `--domain` flag is a **folder basename** (`for_rent`, `governance`, …); metadata `domain:` is an **allowlist** value (`For Rent`, `Data Ops & Governance`, …). Read [`domain_disambiguation.md`](domain_disambiguation.md) before Step 0 for **any** domain or product line request.

---

## Scope resolution (mandatory Step 0)

| User intent | Inventory command | CLI flag |
|-------------|-------------------|----------|
| **Repo folder** — e.g. “FAIR do for_rent” / “domain people” | `find "dags/{folder}" -path '*/metadata/*/*.yml' \| sort` | `--domain {folder}` |
| **YAML `domain:`** — e.g. “tabelas For Rent no catálogo” | `rg -l '^domain:\s*{Allowlist Value}\s*$' dags --glob '**/metadata/*/*.yml'` | `-f` each path + `--audit` |
| **Owner** | `rg -l '^owner:\s*x@…' dags --glob '**/metadata/*/*.yml'` | `--owner x@quintoandar.com.br` |
| **Owner + repo folder** | Same `rg`, root `dags/{folder}/` | `--domain for_rent --owner x@…` |
| **Single DAG** | `find dags/{folder}/{dag}/metadata -name '*.yml'` | `--dag for_rent/dw_rent_demand` |
| **Single table / FQN** | Match `database_name` + `table_name` across layers | `--fqn datalake_*_clean.table` |
| **Explicit file list** | Paths given by user | `-f path.yml` (repeatable) |

Publish in the plan (adjust folder and allowlist per [`domain_disambiguation.md`](domain_disambiguation.md)):

```markdown
**Scope type:** repo folder
**Repo folder:** `dags/for_rent/`
**YAML domain (allowlist):** `For Rent`
**Inventory:** N metadata file(s)
```

Then run:

```bash
make audit-fair-metadata-scope domain=for_rent
# or: --audit --domain … --owner … --fqn … --dag …
```

---

## By repo folder — `dags/{folder}/`

CLI `--domain` means **repo folder basename** under `dags/`, not the YAML `domain:` allowlist. Example: `--domain for_rent` → `dags/for_rent/` while YAML uses **`For Rent`**; `--domain governance` → `dags/governance/` while YAML uses **`Data Ops & Governance`**. See [`domain_disambiguation.md`](domain_disambiguation.md) for the full mapping.

### Repo (authoritative for inventory)

```bash
find "dags/${DOMAIN}" -path '*/metadata/*/*.yml' | sort
```

Read `database_name` + `table_name` from each YAML. Cross-check `dags/${DOMAIN}/**/*_declaration.yml`.

### Lake (supplementary, `@tars`)

[`sql/list_tables_for_remediation.sql`](../sql/list_tables_for_remediation.sql) — production `checks_result_json` for priority and Platform vs domain-remediable failures. **Does not replace** local Gates A/B/C on the full repo inventory.

---

## By owner — `owner@quintoandar.com.br`

Use when the user asks for “all tables owned by X”.

### Repo — metadata YAML (authoritative for inventory)

```bash
rg -l '^owner:\s*<OWNER_EMAIL>\s*$' dags --glob '**/metadata/*/*.yml'
```

Narrow to one domain when the user says so:

```bash
rg -l '^owner:\s*<OWNER_EMAIL>\s*$' "dags/${DOMAIN}" --glob '**/metadata/*/*.yml'
```

### Lake (`@tars`, supplementary)

[`sql/list_tables_for_remediation.sql`](../sql/list_tables_for_remediation.sql) filtered by owner in `tables_documentation`, or the owner query in the previous version of this doc — for **`checks_result_json`** and `owner_not_active_employee`.

### Gate A

Collect **every distinct** `owner:` from the inventory — verify **each** is ACTIVE with `check_owner_active.sql` via `@tars` before EXECUTE. **No owner skipped.**

---

## By single table — `database_name.table_name`

Resolve **all layers** present in the repo (typically `metadata/raw/`, `metadata/clean/`, `metadata/enrich/`, …):

```bash
make audit-fair-metadata-scope fqn=datalake_metabase_clean.metabase_table
```

Apply Gate B to clean+ files. Raw files appear in the scope audit as an **optional** summary — column docs on raw are encouraged but not required.

---

## By DAG — `dags/{domain}/{dag_name}/`

```bash
find "dags/${DOMAIN}/${DAG}" -path '*/metadata/*/*.yml' | sort
```

CLI: `--dag ${DOMAIN}/${DAG}`

---

## Audit scope vs PR diff vs CI

| Concept | Meaning |
|---------|---------|
| **User scope** | Full inventory for Gates A/B/C — repo folder, YAML `domain:`, owner, table, or DAG |
| **PR diff** | Files changed vs `origin/master` — Woodpecker `validate-fair-metadata` only |
| **EXECUTE batch** | Max ~10 tables per PR — slice from scope inventory |

Woodpecker **validate-fair-metadata** runs on **changed files only**. A domain-wide audit in chat is **always wider** than CI. Re-run **scope audit** after EXECUTE to confirm the user’s scope is clean.

---

## General rules

1. **`checks_result_json`** (lake, `@tars`) is authoritative for **production tier** — local gates are authoritative for **repo state before merge**.
2. **Repo inventory** is authoritative for **where to edit**.
3. Max **~10 tables per PR** for EXECUTE; prefer **clean → enrich → dw** over raw.
4. Combine scope flags to **intersect** (e.g. `--domain governance --owner x@…`).
