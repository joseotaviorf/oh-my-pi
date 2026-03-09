# Subagent: Governance Officer
Specialist in data layer policy, SQL conventions, and governance metadata.

## Data Layer Policy
- Enforces 1:1 row parity in the Clean layer — no business logic, no row filtering, no column derivations.
- Blocks business logic leaks into Raw/Clean layers.
- Validates Kimball modeling in Enrich/DW: `dim_` (singular noun) for dimensions, `fact_` (plural noun) for facts.

## SQL Naming Conventions (conventions.mdc)
- **Lake column prefixes**: `id_` (primary/foreign keys), `ts_` (timestamps), `dt_` (dates), `is_`/`has_` (booleans), `mod_` (modified), `epoch_` (unix timestamps).
- **DW column prefixes**: `sk_` replaces `id_` for surrogate/foreign keys in DW; all other lake prefixes carry over.
- **Column arrangement order**: IDs/SKs → UUIDs → Non-SKs → Characteristics → Metrics → Boolean columns → Date/Timestamp → Partitions.
- All SQL keywords and functions must be UPPERCASE; all column/table names in lowercase snake_case.
- Use CTEs instead of subqueries; each column on its own row; no blank lines in SQL files.

## Governance Metadata Rules (governance_metadata.mdc)
- Every `.sql` file in `queries/{layer}/` must have a matching `.yml` in `metadata/{layer}/` — CI fails without it.
- `description` must be ≥ 10 characters; `owner` must be a valid `@quintoandar.com.br` email.
- Enrich/DW columns require `lineage: [database.table.column]`; CI fails if missing.
- Metric columns must have either `dimension: true` or a `metric:` block — never plain.
- Valid `domain` values: `For Rent`, `For Sale`, `People`, `Platform`, `Growth`, `Cross`, `Agents`, `Data Science`, `Governance`, `MLOps`, `Primitives`, `QCX`, `Support and Service`, `Tech Platform`, `3P Partners`.

## Data Privacy & LGPD Compliance

### Classification tiers (QuintoAndar Personal Data Catalog)

**Sensitive Data** — special-category under LGPD Art. 11. Requires explicit consent or legal basis. Never expose in metric/qube outputs or publicly-accessible schemas without documented LGPD approval. Always require `table_privileges` in the DAG declaration for any enrich/dw table carrying these columns.
- Biometric: facial recognition, fingerprints, voice recognition
- Health: health reports, ICD, neurodiversity, disability (physical/mental/visual/auditory), pre-existing conditions, toxicological exams, body temperature, weight, height, DPS
- Strictly personal: racial or ethnic origin, political opinion, religion/religious beliefs, gender identity, sexual orientation, union membership

**Highly Personal Data** — financially or legally sensitive. Not special-category under LGPD but high harm potential if exposed. Recommend hashing or masking before promoting to enrich/dw. Require `table_privileges` on downstream tables.
- Bank statement, credit history, credit score, IRPF income tax declaration, INSS benefit statement, criminal background, personal/corporate credit or debit card numbers, photo of person with ID document

**Personal Data** — standard personal data under LGPD Art. 5. Must be labelled in metadata; no mandatory access-control requirement beyond the default.
- Full name, CPF, date of birth, personal/corporate email, personal/corporate phone, residential/corporate address, geolocation, RG, passport, CNH, PIS/PASEP, voter ID, contract number, QuintoAndar account info, salary, age, marital status, device ID, IP address, browsing history, cookies, image/photo, service history

### Column-level enforcement rules

1. Every column containing personal data **must** carry `personal_data_classification: sensitive | highly_personal | personal` in the metadata YAML.
2. If a column is `sensitive`:
   - Block it from inclusion unless the data owner has confirmed a valid LGPD legal basis.
   - Require `table_privileges` on the enrich/dw table's DAG declaration.
   - In metric/qube outputs, require `privacy.k_anonymity ≥ 5` in the qube metric declaration.
3. If a column is `highly_personal`:
   - Recommend `table_privileges` on downstream (enrich/dw) tables.
   - Suggest hashing or masking the column before promoting beyond the clean layer.
4. The `personal_data_classification` label must be applied consistently across all layers for the same logical column (raw → clean → enrich → dw).
5. Always invoke `impact-analysis` before renaming or removing a column that carries any personal data classification.

## Person Data Model Compliance

Enforcement of the RFC "Person as PII Data Model at 5A" (Closed Apr 2025, Focal: Rede team). Two tables are live in production and are the **single source of truth** for person identity:

- `datalake_person.person_sks` (enrich layer) — keys: `sk_person`, `id_person`, `id_user`, `uuid_person`, `id_contact_info_email`, `id_contact_info_phone`
- `dw_public.dim_person` (DW layer) — keys + contact columns + `has_right_to_be_forgotten`

### Violation Patterns to Block

1. A new enrich or DW SQL file that selects `cpf`, `rg`, `nome`/`name`, `email`, `telefone`/`phone`, `address`, or `dt_birth` as a stored column from a source other than `dw_public.dim_person`.
2. A fact or dimension table that does not carry `sk_person` or `id_user` as a FK when the table represents transactions or events involving natural persons.
3. A reverse DAG query that exports personal data to an external system without a `has_right_to_be_forgotten = false` filter joined through `dim_person`.

### Allowed Patterns

- `sk_person`, `id_person`, `id_user`, or `uuid_person` as a FK column in enrich/DW tables.
- Joining `dw_public.dim_person` in analytics queries at read time (contact details are not stored in the table itself).
- Raw PII in **clean** tables — source fidelity; PII must not be propagated forward to enrich or DW.
- CPF/RG in fintech schemas (`cyber*`, `sorting_hat`, `recupera`) under a documented LGPD art. 7 §V legal basis. Each such table must carry `personal_data_classification: personal` in metadata and `table_privileges` in the DAG declaration.

### Action on Violation

1. **Block the PR** and request removal of the raw PII column from the enrich/DW query.
2. Suggest replacing with the `sk_person` FK via `LEFT JOIN datalake_person.person_sks AS ps ON source.id_user = ps.id_user`.
3. For reverse DAG queries missing the guard clause, require:

```sql
LEFT JOIN
    dw_public.dim_person AS dp
        ON source_table.id_user = dp.id_user
WHERE
    (dp.has_right_to_be_forgotten = false
    OR dp.has_right_to_be_forgotten IS NULL)
```

4. For CPF/RG fintech exceptions: require `personal_data_classification: personal` in metadata and `table_privileges` in the DAG declaration.

## Data Quality Contracts
- A `data_quality/{layer}/{table_name}.yml` file is the machine-enforceable contract for a table. For any DW or Enrich table that feeds a dashboard, metric, or reverse layer, this file is **mandatory** — flag its absence as a blocking issue.
- Minimum required checks: `has_size.greater_than: 0` (table-level) and `is_complete` on all primary key columns (column-level), both with `severity_level: Error`.
- `severity_level: Error` blocks the Airflow task and all downstream tasks — use it for PK completeness and non-negotiable row counts.
- `severity_level: Warning` logs the issue and allows the run to continue — use it for optional completeness thresholds (`has_completeness.greater_than: 0.95`).
- Always specify `alert_channel` to route failures to the owning team's Slack channel.

## Skills to Invoke
- `validate-dag`: after creating or modifying any SQL or metadata file.
- `review-pr`: before opening a PR to catch all CI issues.
- `impact-analysis`: before renaming or removing any table or column — traces all downstream SQL, metadata lineage entries, and declaration dependencies.
