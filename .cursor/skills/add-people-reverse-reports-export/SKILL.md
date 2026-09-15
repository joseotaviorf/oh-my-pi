---
name: add-people-reverse-reports-export
description: >-
  People domain (`dags/people/` only). Add, migrate, or edit a Google Sheets export under
  `dags/people/reverse_reports/`. Interactive one-question-at-a-time flow in PT-BR
  (notebook migration, net-new tab, edit existing, validation/Forno/PR/cutover). DBP Jira
  kickoff on Enterprise Engineering (DBP). First turn: AskQuestion flow selection (like
  provision-data-contract). Source priority: prefer `dw_employee_details` over
  `dw_people` for employee identity/assignments, then other DW (`dw_*`), then
  metric-layer; avoid enrich/clean unless documented exception.
---

# Add People `reverse_reports` export

End-to-end flow to **add, migrate, edit, validate, and cut over** a People Google Sheets export via `dags/people/reverse_reports/` (lake table → `load_to_gsheet`).

Technical rules live in [reference.md](reference.md). Apply them when generating artifacts — **after** the user confirms the summary.

## Interaction (mandatory)

- Ask **one question at a time**. Wait for the user's answer before the next step.
- **User-facing questions and option labels → PT-BR.** Jira **summary**, **description**, and **comments** → **English** ([`dbp-jira-reference.md`](../../rules/people/dbp-jira-reference.md)).
- **DBP** = Jira project/board of the **Enterprise Engineering** squad. In PT-BR prompts: **"board do Jira de Enterprise Engineering (DBP)"**. Do not expand the legacy board name (*Data Bedrock and People*) — the Bedrock team no longer exists; only the acronym/name in Jira remains.
- **First turn:** call the **AskQuestion** tool with [Flow selection](#flow-selection) — **mandatory** when the user invokes the skill without a clear flow already chosen. One short ack line is OK; **do not** substitute a prose-only menu or open with [Intake inicial](#shared--intake-inicial). **Do not** explore the repo before that AskQuestion (except reading this skill + `reference.md`).
- **AskQuestion is required** whenever options are known — listing bullets in chat **does not** count. Same pattern as [`provision-data-contract`](https://github.com/quintoandar/data-contracts/tree/main/.cursor/skills/provision-data-contract).
- **Do not** dump a multi-field intake table on the first turn.
- **Do not** edit repo files until the user confirms the **summary** (Flow 1 step 13 / Flow 2 step 9 / Flow 3 step 7).
- **Do not** open a PR until validation and local Forno run are proved — unless the user explicitly waives in writing (document in PR body).
- Reuse answers already in the thread; skip questions that are already answered.
- **Never invent** governance consumers, owners, or integration patterns — ask.
- **Validation:** Tier 1–3 diffs run on **Databricks** — the legacy notebook outputs on one side of the diff only exist there, so run the full diff on Databricks rather than splitting across engines.

**Shortcuts:** If the first message already picks a flow **and** includes material (DBP key, SQL/notebook, sheet URL, business description), acknowledge both, skip Flow selection and duplicate intake AskQuestions, and jump to the next missing step.

### Migration notebook inference

When the user selects **migrate** and supplies a notebook (`.ipynb`, workspace URL, or exported path) — or explicitly says tabs/sheets are correct for a migration — **do not** re-ask per-tab sheet URL, tab name, legacy SQL, or service-account ACL unless they dispute a value. Treat `table_to_gsheets` / `send_data_to_sheet` calls as production contract:

| Infer from notebook | Use for |
| --- | --- |
| `sheet_url` / `sheet_id`, `sheet_tab` | Declaration `extra_spark_job_arguments` |
| SQL in the cell above each export | Legacy logic + column contract |
| `force_int_to_str=True` | Note in remap / declaration if needed |
| Row counts in cell output | Tier-1 validation baseline |
| Multiple writes of the same `table_name` | Flag dual-sheet cutover (one `tables_customization` entry per destination) |

**Default for migrations:** legacy headers **Sim** (step 8); remap `dw_employee.*` → domain `dw_*` / `metric_people.employee_snapshots` per [reference.md](reference.md). **Never** leave `datalake_people_analytics_sandbox` in reverse SQL — resolve via `datalake_workable_redshift_clean`, governed tables, or `datalake_gsheets_people_clean` bridge ingestion ([reference.md — sandbox resolution](reference.md#resolving-legacy-people_analytics_sandbox-dependencies)). **Batch** steps 5–9: present one consolidated table for all tabs, then governance — still **one governance question per turn**. **Still ask** (never invent): business owner, technical owner, operational consumer, why Sheets when not in Jira/notebook.

**Sandbox ban (mandatory):** `datalake_people_analytics_sandbox` is **never** an approved source for `queries/reverse/*.sql`. If the legacy notebook references sandbox (e.g. `base_quintocred_ta`, `base_completa_hierarquia`, `base_requisitions_wb`), flag it in the remap plan and **block implementation** until each sandbox table has an approved replacement (`employee_snapshots`, `gsheets_people_static`, `workable_redshift_clean` inline, etc.). See [reference.md — Sandbox static tables](reference.md#sandbox-static-tables-never-in-reverse-sql).

---

## Flow selection

**Always first** — unless the shortcut above applies.

Call **AskQuestion** (tool) with prompt **"O que você quer fazer?"** and these options:

| id | label |
| --- | --- |
| `migrate` | Migrar export de notebook Databricks |
| `new` | Adicionar nova exportação (sem notebook) |
| `edit` | Editar export existente |
| `continue` | Continuar trabalho em andamento (validação, Forno, PR ou cutover) |

Then enter the matching flow:

- `migrate` → [Flow 1](#flow-1--migrate-notebook-export)
- `new` → [Flow 2](#flow-2--new-export-no-notebook)
- `edit` → [Flow 3](#flow-3--edit-existing-export)
- `continue` → [Flow 4](#flow-4--continue-in-flight)

---

## Shared — Intake inicial

**After Flow 1 or Flow 2 is selected** — unless the thread already has enough context (card, query/notebook, and/or what to export).

### Step A — What do you have?

Call **AskQuestion** with prompt **"O que você já tem em mãos?"**:

| id | label |
| --- | --- |
| `dbp_key` | Tenho chave DBP (ex.: DBP-1422) |
| `query_notebook` | Tenho query, notebook ou `.ipynb` |
| `description` | Tenho só a descrição do que exportar |
| `other` | Outro — vou explicar na próxima mensagem |

### Step B — Collect (one turn each)

| User chose | Next ask |
| --- | --- |
| `dbp_key` | **"Qual a chave do issue? (ex.: DBP-1422)"** → store `{KEY}`; optionally `getJiraIssue` |
| `query_notebook` | **"Cole a query, URL do notebook ou anexe o `.ipynb`."** → parse tabs/SQL; infer grain, columns, sources |
| `description` | **"Descreva o que precisa exportar — processo, aba, colunas principais."** |
| `other` | Free text — acknowledge; ask only what is still missing |

| Also in thread | Agent does |
| --- | --- |
| **Mix** (shortcut) | Acknowledge all; skip Step A/B items already answered |

Do **not** ask which `dw_*` or metric tables to read — infer sources from the query/notebook and [reference.md](reference.md); confirm in the **remap plan**.

## Flow 1 — Migrate notebook export

Follow steps in order. Skip any step whose answer is already in the thread or in [Intake inicial](#shared--intake-inicial).

### 1. Intake inicial

Follow [Shared — Intake inicial](#shared--intake-inicial).

### 2. Notebook

If intake did not include a notebook URL, path, or `.ipynb`, ask: **"Qual notebook Databricks devemos migrar? Cole a URL do workspace, o caminho ou o `.ipynb` exportado."**

### 3. Jira (DBP)

If `{KEY}` is missing, follow [Shared — Jira (DBP kickoff)](#shared--jira-dbp-kickoff). Continue at step 4 when `{KEY}` is set (or **local-only** is explicitly waived).

### 4. Scope — tabs

Inspect the notebook and list tabs (cell titles, `table_to_gsheets` / `send_data_to_sheet`).

Ask: **"Este notebook grava na(s) aba(s): {list}. Migrar todas agora ou só algumas?"**

### 5–9. Per tab (or batched when notebook is complete)

If a **migration notebook** is attached and the user has **not** disputed sheet targets, apply [Migration notebook inference](#migration-notebook-inference) — skip steps 5, 8 (default Sim), and 9; present one consolidated delivery table for all tabs before governance.

Otherwise repeat for each tab before the shared remap step:

- **5.** **"Qual a URL da planilha de produção (ou `sheet_id`) e o nome exato da aba `{tab}`?"** (+ Editor for `gsheets-people-access@airflow-186119.iam.gserviceaccount.com`)
- **6.** Business purpose — skip if intake already described it; otherwise **"Qual processo de negócio a aba `{tab}` sustenta? Quem usa e com que frequência?"**
- **7.** **"Por que isso ainda é uma aba no Google Sheets em vez de Databricks / Superset / integração direta?"**
- **8.** Call **AskQuestion**: **"Os cabeçalhos exportados precisam ser idênticos ao notebook/planilha legado (Looker, PIN, scripts)?"** — Sim / Não / Não tenho certeza (default Sim)
- **9.** Legacy SQL — skip if intake already included SQL/notebook; otherwise **"Cole o SQL da aba `{tab}`, ou anexe o notebook exportado / `@file`."**

### 10. `table_name`

Propose `snake_case` name. Ask: **"Usamos `{table_name}` como nome da tabela no lake, ou prefere outro?"**

### 11. Governance

One at a time: business owner, technical owner, operational consumer; upstream owner only if not DW-only.

### 12. Remap plan

Present remap table + grain, headers, risks, cutover scope. If legacy SQL references `datalake_people_analytics_sandbox`, include a **Sandbox → approved lake** row for every sandbox table and call out any missing ingestion (e.g. static roster → `gsheets_people_static`). Ask: **"Esse plano de remap está correto?"**

### 13. Summary

Present resumo in PT-BR. Ask: **"Está tudo certo? Posso implementar no repositório?"**

→ [Shared — Implement](#shared--implement-in-repo)

---

## Flow 2 — New export (no notebook)

1. [Shared — Intake inicial](#shared--intake-inicial)
2. [Shared — Jira (DBP kickoff)](#shared--jira-dbp-kickoff) — only if `{KEY}` still missing
3. **"Por que Google Sheets para esse processo?"** — skip business purpose if intake already covered it
4. **"URL da planilha de produção (ou `sheet_id`) e nome da aba?"**
5. **"O que cada linha da planilha representa?"** — skip if inferrable from intake SQL/description; optional examples: colaborador, cargo, tabela + banda
6. AskQuestion: cabeçalhos — naming_conventions vs nomes fixos legados
7. Governance (Flow 1 step 11)
8. Remap plan (sources inferred from intake — confirm with **"Esse plano de remap está correto?"**)
9. Resumo → **"Está tudo certo? Posso implementar no repositório?"**

---

## Flow 3 — Edit existing export

1. Read `reverse_reports_declaration.yml`. Call **AskQuestion** with export options (or **"Qual export você quer editar?"** if too many for a list).
2. [Shared — Jira (DBP kickoff)](#shared--jira-dbp-kickoff)
3. Summarize SQL, docs, declaration. Ask: **"É esse export que você quer alterar?"**
4. Call **AskQuestion**: o que mudar — SQL / colunas / planilha / governance / declaration / outro
5. Detalhes — uma pergunta por turno (see [reference.md](reference.md))
6. **"Tem mais alguma alteração nesse export antes de eu aplicar?"**
7. Resumo → **"Posso aplicar essas alterações no repositório?"** → then validation/Forno/PR as needed

---

## Flow 4 — Continue in-flight

Call **AskQuestion** with prompt **"Em que ponto você parou?"**:

| id | label |
| --- | --- |
| `validation` | Validação SQL (Tier 1–3) |
| `validation_ok` | Validação OK — falta Forno |
| `forno_ok` | Forno OK — falta PR / merge |
| `prod_ok` | Merge + prod OK — falta cutover |

If `{KEY}` unknown: **"Qual issue DBP cobre esse trabalho?"**

---

## Shared — Jira (DBP kickoff)

Use on **Flows 1–3** before repo edits. **One question per turn.**

Read [`dbp-jira-reference.md`](../../rules/people/dbp-jira-reference.md) before Atlassian MCP calls.

**Shortcut:** thread contains `DBP-<number>` → **"Confirmo: o card é `{KEY}`?"**

### Step 1 — Card on the board?

Ask with **AskQuestion** (tool):

**"Já existe um card no board do Jira de Enterprise Engineering (DBP) para esse trabalho?"**

- **Sim — tenho a chave** → [Step 2a](#step-2a--issue-key)
- **Sim — mas não lembro a chave** → [Step 2b](#step-2b--find-existing-issue)
- **Não / não sei** → [Step 3](#step-3--create-a-card)

### Step 2a — Issue key

Ask: **"Qual a chave do issue? (ex.: DBP-1422)"**

Optionally `getJiraIssue` to confirm summary. Store `{KEY}`.

### Step 2b — Find existing issue

Ask: **"Descreva o card — notebook, export/`table_name`, aba ou palavras do summary — para eu buscar no DBP."**

`searchJiraIssuesUsingJql` → present matches. Ask: **"Qual issue é?"**

No match → Step 3.

### Step 3 — Create a card?

Ask: **"Quer que eu crie um card no board do Jira de Enterprise Engineering (DBP) para esse trabalho?"**

- **Não** → **"Continuar como local-only (sem Jira) ou parar até você ter um card?"**
- **Sim** → [Shared — Create DBP issue](#shared--create-dbp-issue)

### Step 4 — Git branch (optional)

Ask: **"Quer que eu configure a branch Git agora?"** → skill **`people-jira-branch-setup`** if yes.

---

## Shared — Create DBP issue

One question per turn. Jira body in **English**.

- **C1** AskQuestion: Story ou Sub-task (`Sub-task` API name)
- **C2** (Sub-task) **"Qual a chave do issue pai (Story ou Epic)?"**
- **C3** AskQuestion: planejado na sprint ou buffer (`[buffer]` prefix if buffer)
- **C4** Propose English summary → **"Uso este summary no Jira: `{proposal}`?"**
- **C5** Show English description draft → **"Quer acrescentar ou mudar algo antes de criar o issue?"**
- **C6** **"Posso criar o issue no DBP?"** → `createJiraIssue`, share `{KEY}` + URL

---

## Shared — Implement in repo

After summary confirmation — [reference.md — Implementation checklist](reference.md#implementation-checklist).

Run skill **`databricks-emr-sql-lint`** after `.sql` edits.

**Naming:** CTEs, internal aliases, and `table_name` must be English; Portuguese only in final export column aliases — see [reference.md — English identifiers](reference.md#english-identifiers-everywhere-except-sheet-headers).

Ask: **"Implementação concluída. Gerar SQL de validação ou ir direto para o Airflow local (Forno)?"**

---

## Shared — Validation

**Runtime:** `reverse_reports.*` and `dw_*` are in Trino, but the legacy notebook outputs on the other side of the diff are Databricks-only. Run all Tier 1–3 validation SQL on **Databricks** prod (`quintoandar_prod`) so both sides of the diff come from the same engine.

### Databricks CLI (agents)

Use the **People domain Databricks CLI runbook** ([`people_domain.mdc`](../../rules/people/people_domain.mdc) — *Ad-hoc SQL and pre-merge DQ validation*):

1. List People test clusters; pick one in **RUNNING** state.
2. `env -u DATABRICKS_TOKEN -u DATABRICKS_HOST -u DATABRICKS_USERNAME databricks … -p PROD`
3. Commands API: `contexts/create` → `commands/execute` → poll `commands/status`.
4. Always prefix: `USE CATALOG quintoandar_prod;`

Save artifacts under `.cursor/temp/{JIRA_KEY}/{branch-slug}/validation/`:

- `databricks_sql_runner.py` — ad-hoc single query
- `run_{migration}_validation.py` — batch Tier 1–3 (see [`exodus_validation_playbook.md`](../../../dags/people/reverse_reports/docs/exodus_validation_playbook.md) when present)

**`metric_people.employee_snapshots` current-state filter:** use `es.is_current = TRUE AND es.is_primary_assignment_for_snapshot = TRUE`. Do **not** use `dt_reference = CURRENT_DATE()` (month-end column; returns 0 rows most days) or `MAX(dt_reference)` as a snapshot picker — see [reference.md](reference.md#filtering-metric_peopleemployee_snapshots).

**HRBP:** never export bare `es.hrbp_work_email` alone — use `LOWER(COALESCE(es.hrbp_work_email, cc_current.hrbp_work_email))` with current `dim_cost_center` fallback (terminated snapshots often null HRBP on the versioned CC). See [reference.md](reference.md#hrbp-from-employee_snapshots-mandatory-remap).

### Columns excluded from Tier 2 (do not validate)

**Load-time stamps** — omit from Tier 2 `EXCEPT` compare lists:

| Pattern | Examples |
| --- | --- |
| Raw **`ts_load`** | `fact_*.ts_load`, `employee_snapshots.ts_load` |
| **`NOW()`**, **`CURRENT_TIMESTAMP()`**, or columns derived only from them | `NOW() AS ts_load`, `CURRENT_TIMESTAMP() AS dt_extracted` |
| Date columns **sourced from load `ts_load`** | `CAST(ts_load AS DATE) AS dt_last_update`, `CAST(FROM_UTC_TIMESTAMP(es.ts_load, …) AS DATE) AS data_extracao` |

These record **when the pipeline loaded the row**, not a business event. Legacy (`dw_employee`) and DW 2.0 (`metric_people`, `dw_*`) load times **always** diverge after remap — expected, not a migration defect.

**Business date columns stay in Tier 2** — validate mismatches on dates that represent domain facts, e.g. `dt_birth`, `dt_hired`, `dt_inicio`, `dt_nascimento`, `dt_terminated`, `dt_desligamento`, SK-as-date for hire/termination (`sk_hired_date` → `dt_inicio`), validity windows (`dt_valid_from` / `dt_valid_to`), and similar.

- Tier 1 row counts and all non–load-time columns still require validation.

**"Rode as queries no Databricks e cole os resultados Tier 1–3, depois responda validation OK."** — agents should run the CLI themselves when possible, not only ask the user to paste.

---

## Shared — Local Airflow (Forno)

[`run-dag-locally`](../run-dag-locally/SKILL.md). Env check → trigger `bietlejuice.reverse_reports`.

**"O run no Forno deu certo para `{table_name}`? Responda local run OK ou envie os logs."**

---

## Shared — Open PR

[`review-pr`](../review-pr/SKILL.md) → [`create-or-update-pr`](../create-or-update-pr/SKILL.md) (`DBP-xxxx | …`).

**"Quando merge + prod estiverem OK, responda PR merged, prod OK para o checklist de cutover."**

---

## Shared — Post-merge cutover

Comment notebook write cells; remove Daily Pipeline task if full migration. [`exodus_migration_guide.md`](../../../dags/people/reverse_reports/docs/exodus_migration_guide.md).

**"Responda cutover done quando terminar a limpeza no notebook/job."**

---

## References

- [reference.md](reference.md)
- [`dbp-jira-reference.md`](../../rules/people/dbp-jira-reference.md) — project **DBP**, squad **Enterprise Engineering**
- [`people-jira-branch-setup`](../people-jira-branch-setup/SKILL.md)
- [DBP-1310](https://quintoandar.atlassian.net/browse/DBP-1310)

## Out of scope

Other domains, BI-only without reverse lake table, human sheet ACLs outside service account.
