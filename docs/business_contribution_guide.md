# Business Contribution Guide

<!--
  Canonical doc: business self-service + technical reference (single file).
  Maintainers: CODEOWNERS for dags/ops_poc + dags/planning_and_performance; sync business_contribution.mdc + business-contribution skill.
  History: prior Section A/B/C evolution 2025-03-19 → 2025-03-28; 2025-03-31 — narrative (§1–7) + §8 technical reference; preserved anchor ids for redirects.
-->

Welcome to the Business Contribution Guide for the **`quintoandar/bi-etl-ejuice`** repository. It helps **Business Intelligence (BI)** and **Planning & Performance (P&P)** teams add **governed data assets** (tables and metrics): SQL plus metadata, reviewed through PRs, and executed on the shared **Airflow + Databricks** platform.

<a id="index-of-whats-included"></a>

## Index of what’s included

| # | Section | What you get |
|---|---------|----------------|
| **1** | [Introduction & concepts](#1-introduction--concepts) | DAGs, declaration, SQL, metadata, generated Python. |
| **2** | [Setup & prerequisites](#2-setup--prerequisites) | IDN / GitHub / VPN / Cursor. |
| **3** | [Choosing your development path](#3-choosing-your-development-path) | Cursor, VS Code + clone + `make`, or Path C (Github UI / no `make`). |
| **4** | [Practical walkthroughs & recipes](#4-practical-walkthroughs--recipes) | New table, new DAG, reverse ETL, optional `dependencies.yaml`. |
| **5** | [Rules of the road](#5-rules-of-the-road--sandbox-limits) | Safe zones, RAW, SQL hygiene, metadata, Forno Option B, CODEOWNERS, PR template; contact code owners when you need help. |
| **6** | [Pro-tips & advanced logic](#6-pro-tips--advanced-logic) | Short-circuit scheduling, backfill / config. |
| **7** | [Troubleshooting CI failures](#7-troubleshooting-ci-failures) | Woodpecker / Databricks conn IDs. |
| **8** | [Technical reference & policy](#8-technical-reference--policy) | Full DAG Builder detail, workflows, dependencies deep dive, Cursor map, extended troubleshooting. |

**Quick navigation (legacy bookmarks):** [Onboarding anchor](#section-a-onboarding) · [Recipes anchor](#section-b-recipes) · [Technical reference anchor](#section-c-technical-reference-and-policy)

**Quick contribution loop:** **Setup** (§2–3) → **Branch & build** (§4) → **Green CI** (§5–7) → **PR to `master`** using the **[PR description template](../.cursor/rules/pr_template.mdc)** → **Deploy** (§4 notes on unpause / escalation).

---

<a id="section-a-onboarding"></a>

## 1. Introduction & concepts

As an analyst or BI developer, you are already comfortable with **SQL**. In this repository we use **Airflow DAGs** (Directed Acyclic Graphs) to orchestrate when and how those SQL queries run.

Think of a DAG as an **automated scheduling manager**. Instead of writing complex Python orchestration code, the platform uses the **DAG Builder**. You provide:

1. **The declaration (`*_declaration.yml`):** Schedule, DAG name, connection IDs, Databricks cluster, and **layer** (where the table lives in the lake/DW). **`workflow.type`** and other builder knobs (for example **`query_delta`**) are set here too — see **[Scenario B: Creating a brand new DAG](#recipe-2-new-dag-new-folder)** and [§8.2 Workflow overview](#c2-workflow-overview); most business-path SQL pipelines use **`query_delta`**.
2. **The logic (`.sql`):** One SQL file **per output table** (typical SQL pipelines).
3. **The metadata (`.yml`):** Governance — columns, **lineage**, **ownership**, classifications, and business-path fields (see §5).

The framework **generates** the Airflow Python file (`*_dag.py`). **Do not** hand-edit `*_dag.py` for task logic — change the YAML and run `make create-dag-files`.

**Layer chain (read vs write):** Data flows **raw → clean → enrich → dw** (and onward to **metric** / **Qube** where those products apply). **Reverse** is for data **leaving** the platform.

**Where business-path contributors usually *write* new outputs:** **`enrich`** or **`dw`**, typically with workflow type **`query_delta`**, unless your program or **code owner** directs otherwise (for example a **metric** KPI deliverable).

**DW vs metric (short):**

- **DW (`dw`)** — Curated **dimensions / facts** (Kimball-style) meant to be **reused** across teams and dashboards.
- **Metric (`metric`)** — **Pre-aggregated** measures/KPIs, often fed by DW or enrich; use when the deliverable is a **defined indicator**, not a wide exploratory table. If you are unsure, default to **enrich/dw** and ask your **code owner** before choosing **metric**.

**What you usually *read* in SQL:** Tables **at or below** the layer of your output (for example enrich SQL may read **clean**; DW SQL may read **enrich** and **clean** — not the other way around). See **[§8 — Technical reference & policy](#8-technical-reference--policy)** for the full cross-layer rule and workflow detail.

---

## 2. Setup & prerequisites

Before you can build, request access through **IdentityNow (Central de Solicitações)**:

| Request | Notes |
|---------|--------|
| **GitHub — Associate User** | Provide your **personal GitHub username**. Account must have **2FA** enabled. |
| **GitHub — Repository Access** | Repository: **`quintoandar/bi-etl-ejuice`** (internal catalog may list it as **BI-ETL-EJUICE**). |
| **Zscaler-Github (VPN)** | Needed for internal tooling and **Woodpecker** CI visibility in some setups. |
| **Cursor** | **AI-assisted IDE** — request via IDN if your program uses it. **VS Code** remains fully supported (**§3 Path B**). |

**Never commit secrets:** passwords, tokens, or API keys in YAML, SQL, or git history → security incident and PR rejection.

---

## 3. Choosing your development path

**Default git branch:** this repository uses **`master`** as the default branch for PRs and `git checkout` (confirm in GitHub’s branch dropdown if unsure).

### Path A: Cursor (recommended if you have access)

- Open the **`bi-etl-ejuice`** folder in **Cursor**.
- In chat, you can invoke skills such as **`business-contribution`** (business rules), **`setup-local-environment`** (local stack), or **`create-dag`** (scaffold). Exact UI depends on your Cursor version (e.g. **Skills** picker or `@` mentions).

### Path B: VS Code (local clone + terminal)

1. **Clone** the repo (SSH or HTTPS), then open the folder in VS Code:

```bash
# SSH (example)
mkdir -p ~/Projects && cd ~/Projects
git clone git@github.com:quintoandar/bi-etl-ejuice.git
cd bi-etl-ejuice
```

```bash
# HTTPS (example)
mkdir -p ~/Projects && cd ~/Projects
git clone https://github.com/quintoandar/bi-etl-ejuice.git
cd bi-etl-ejuice
```

2. **Company machine setup** (tools, tokens): [github.com/quintoandar/local-setup](https://github.com/quintoandar/local-setup) · [Google Doc — local setup](https://docs.google.com/document/d/12o4A-ja9Lv2rA-uTIphI0sSZbR-QJRpwk57idO_Tpx0/edit?tab=t.0)

3. From the **repository root** (folder that contains `Makefile`), run:

```bash
make environment
make requirements
make requirements-scripts
make dependencies-file
```

If **`make dependencies-file`** fails with a missing **`quintoandar_logger`** (or similar) module, ensure **`make requirements-scripts`** completed successfully first, then retry.

### Path C: Github UI

This path is named for the most common case — editing on **github.com** — but the same constraints apply if you use **VS Code / Cursor on a clone** (or another editor) **without** running `make` (including **Windows without WSL**, where `make` is often unavailable).

- Create a **branch** and edit **`.sql` / `.yml` / `*_declaration.yml`** on **github.com** or in an editor **without** running `make`.
- You **cannot** run `make create-dag-files` locally → CI may report missing or stale `*_dag.py`. **Contact a code owner** ([§5.7](#a7-who-reviews-your-pr-codeowners)) and ask them to run `make create-dag-files` on your branch and push.

**Windows:** without **WSL**, treat **`make` as often unavailable** — rely on **GitHub → Checks** and **contact a code owner** ([§5.7](#a7-who-reviews-your-pr-codeowners)) if you need `make create-dag-files`, Forno, or other local steps.

---

<a id="section-b-recipes"></a>

## 4. Practical walkthroughs & recipes

Work **only** under **`dags/ops_poc/`** or **`dags/planning_and_performance/`** unless leadership gave a **written** exception.

**New table vs new DAG (which recipe?):**

- **Add a table to an existing DAG ([Scenario A](#recipe-1-new-table-in-an-existing-dag))** when the **same Airflow DAG**, **same schedule**, and **same product area** already exist — you add `queries/…` + `metadata/…` under that folder.
- **Create a new DAG folder ([Scenario B](#recipe-2-new-dag-new-folder))** when you need a **new `dag.name`**, a **different schedule**, or a **clearly separated** ownership / blast radius.
- If you are unsure, ask your **code owner**; many teams prefer **Scenario A** when the use case still fits the existing DAG.

<a id="recipe-1-new-table-in-an-existing-dag"></a>

### Scenario A: Adding a new table to an existing DAG

**Step 1 — Update and branch**

```bash
git checkout master && git pull && git checkout -b feat/add-my-table
```

**Step 2 — Build files**  
In the existing DAG folder, add `queries/<layer>/<new_table>.sql` and `metadata/<layer>/<new_table>.yml` with the **same base name**. Copy a sibling as a template. Set **`owner`**, descriptions, and **`lineage`** where required (do **not** add `personal_data_classification` — CI does not accept it yet); include **`retention_policy`** and **`cost_center`** when the schema requires those keys (§5.4 — **no fill guidance here**). If the declaration must list tables, edit **only** `*_declaration.yml`.

**Step 3 — Generate Python** ⚠️ *Skip if no local `make`; contact a code owner ([§5.7](#a7-who-reviews-your-pr-codeowners)).*  

```bash
make create-dag-files dag_name=EXISTING_DAG_FOLDER_NAME
```

**Step 4 — Validate locally** ⚠️ *Skip commands if no local `make`.*

```bash
make validate-dag-declaration-files dag_name=EXISTING_DAG_FOLDER_NAME
make validate-metadata-files-exist
make validate-metadata-files-content
make validate-lineage-consistency
```

**Step 5 — Commit and open PR**  
Open the PR against **`master`**. Use the **[PR description template](../.cursor/rules/pr_template.mdc)** as described in [§5.8](#a8-pull-requests-description-template).

```bash
git add -A
git commit -m "Add my_new_table to existing DAG"
git push -u origin feat/add-my-table
```

**Step 6 — Deploy**  
After merge, the table is part of the DAG schedule. If CI was red because `*_dag.py` was missing, ensure a code owner regenerated and pushed.

---

<a id="recipe-2-new-dag-new-folder"></a>

### Scenario B: Creating a brand new DAG

**Step 1 — Branch**

```bash
git checkout master && git pull && git checkout -b feat/new-dag-xyz
```

**Step 2 — Duplicate and customize**  
Copy a **similar** DAG folder under the **same** allowed root. Rename the folder, `*_declaration.yml`, `*_dag.py` name pattern, and SQL/metadata files. Set **`dag.name`** per [layer / naming rules](#c2-workflow-overview). Use **`_declaration.yml`** (not `.yaml`).

**Step 3 — Generate Airflow code** ⚠️ *Skip if no local `make`.*

```bash
make create-dag-files dag_name=NEW_DAG_FOLDER_NAME
```

**Step 4 — Validate** ⚠️ *Skip if no local `make`.*

```bash
make validate-dag-declaration-files dag_name=NEW_DAG_FOLDER_NAME
make validate-metadata-files-exist
make validate-metadata-files-content
make validate-lineage-consistency
```

**Step 5 — Commit and open PR**  
State clearly in the PR title/body that this is a **new DAG**. Use the **[PR description template](../.cursor/rules/pr_template.mdc)** as described in [§5.8](#a8-pull-requests-description-template).

```bash
git add -A
git commit -m "Create new DAG: NEW_DAG_FOLDER_NAME"
git push -u origin feat/new-dag-xyz
```

**Step 6 — Deploy & unpause**  
New DAGs are often **paused** in production Airflow. Business contributors typically **cannot** unpause in the prod UI — **ping your Data Engineer or code owner** to enable the DAG. Coordinate **Forno** if your code owner asks ([§5 Forno](#a6-ci-vs-forno-business-path)).

---

<a id="recipe-3-reverse-etl-export-or-outbound-data"></a>

### Scenario C: Reverse ETL (exporting data outward)

**Step 0 — Pre-flight (before code)**  
Outbound flows need **approved use case**, **DPIA / ROPA** (or equivalent), and **InfoSec / Privacy** alignment. If that is **not** documented, **stop** and engage your **data owner** and open the appropriate **service desk** requests (log in with your QuintoAndar account):

- **Cybersec:** [Jira Service Management — portal 4203](https://quintoandar.atlassian.net/servicedesk/customer/portal/4203)
- **Privacy:** [Jira Service Management — portal 3939](https://quintoandar.atlassian.net/servicedesk/customer/portal/3939)

**CI does not replace** this sign-off. This guide does **not** replace your organization’s privacy/security process — **Scenario C** below covers **repository** steps only **after** your **code owner** confirms you may proceed.

**Step 1 — Branch**

```bash
git checkout master && git pull && git checkout -b feat/reverse-export-xyz
```

**Step 2 — Build with Data Engineering**  
Set **`workflow.type`** to `load`, `access`, or `load_access` on the **reverse** layer; **`databricks_conn_id`** is usually **`databricks_new`** ([table](#databricks-conn-by-layer)). PR must state **destination**, **purpose**, and **data categories** (especially personal data).

**Step 3 — Generate & push** ⚠️ *Skip `make` if no local setup.*

```bash
make create-dag-files dag_name=YOUR_REVERSE_DAG_FOLDER
git add -A && git commit -m "Add reverse ETL to [Destination]" && git push -u origin feat/reverse-export-xyz
```

**Step 4 — Deploy & unpause**  
Same as Scenario B: after merge, ask **DE / code owner** to **unpause** and to run **Forno** / receiving-system tests if agreed.

**References:** [`create-dag` skill](../.cursor/skills/create-dag/SKILL.md) · [`dag_build.mdc`](../.cursor/rules/dag_build.mdc) · [§8.2 Workflow overview](#c2-workflow-overview)

---

<a id="recipe-d-dependencies-yaml"></a>

### Scenario D: You were asked to edit `dags/dependencies.yaml`

**Warning:** Do **not** open this file on your own. It controls **global** DAG run order; mistakes affect **other teams** and can fail CI. Edit **only** if a **code owner** asked you to. If your pipeline **must** wait on another DAG, tell your **code owner** — they usually add the upstream edge. If you change SQL in a DAG that **others depend on**, state that clearly in the PR description.

List **upstream** DAGs **you** wait on — not downstream consumers. After editing:

```bash
make validate-dags-dependencies
make validate-dependency-file-correctness
```

Plain-language primer: [§5.5 DAG execution dependencies](#a11-dag-execution-dependencies-plain-english). Full spec: [DAG dependencies (full)](#dag-dependencies-full).

---

<a id="appendix-command-cheat-sheet-repo-root"></a>

### Command cheat sheet (repo root)

```bash
make create-dag-files dag_name=YOUR_DAG_FOLDER_NAME

make validate-dag-declaration-files dag_name=YOUR_DAG_FOLDER_NAME
make validate-metadata-files-exist
make validate-metadata-files-content
make validate-lineage-consistency
```

**If you touched `dags/dependencies.yaml`:** `make validate-dags-dependencies` · `make validate-dependency-file-correctness`  
**Optional local Airflow:** [`local/README.md`](../local/README.md) · `make setup-local-variables`

---

<a id="5-rules-of-the-road--sandbox-limits"></a>

## 5. Rules of the road

This section collects **merge and governance rules** in one place (allowed folders, layers, SQL hygiene, metadata, CI, Forno expectations, and **who reviews**). It complements **§4** — read it before you open a PR.

### 5.1 Do’s and don’ts

| ✅ Do | ❌ Don’t |
|-------|---------|
| Keep work in **`dags/ops_poc/`** or **`dags/planning_and_performance/`** | Edit other teams’ DAG folders without an exception |
| Read from **clean**, **enrich**, **dw**, etc. as **sources** in SQL (with correct metadata and lineage) | Read **`datalake_*_raw`** in business-path SQL (**#Hard-Blocker-02**) |
| Default **new tables** to **enrich** or **`dw`** per [§1](#1-introduction--concepts) | **Create** new **clean** or **raw** **outputs** as self-service business-path tables unless a **code owner** explicitly directs otherwise |
| Use **CTEs (`WITH`)** for readability where it helps | Rely on **deep nested subqueries** when a CTE is clearer |
| Avoid **`SELECT *`** | Ship **`SELECT *`** in production SQL |
| Restrict access to PII-bearing tables via **`table_privileges`** | Add a **`personal_data_classification`** key or any PII-tier text (classification isn't part of metadata yet — CI rejects the key) |
| Keep **`.sql` and `.yml` paired** (same base name) | Hand-edit **`*_dag.py`** |
| Get **green Woodpecker / GitHub Checks** before merge | Commit **passwords, tokens, API keys** |

### 5.2 SQL style & column ordering (summary)

Code owners may check **structure**. Follow repository conventions:

- **Column order (priority):** IDs (e.g. `sk_*`) → properties → metrics → dates/timestamps → partitions (see **[`naming_conventions.mdc`](../.cursor/rules/naming_conventions.mdc)** for the full list).
- **Prefixes:** `id_*`, `ts_*`, `dt_*`, `is_*` / `has_*` per naming rules.
- **Keywords:** Many teams use **uppercase** for SQL reserved words (`SELECT`, `WHERE`, …) — match **sibling queries** in the same DAG.

Full detail: **[`sql_conventions.mdc`](../.cursor/rules/sql_conventions.mdc)**.

### 5.3 `dags/dependencies.yaml` (execution order)

**One-line summary:** `dependencies.yaml` controls **when DAGs run relative to each other**, not column **lineage** (that lives in metadata). **Do not** edit this file unless a **code owner** asked you to.

**Details and mental model:** [§5.5 DAG execution dependencies](#a11-dag-execution-dependencies-plain-english). **If you were asked to edit the file:** follow [§4 Scenario D](#recipe-d-dependencies-yaml) and run the validators shown there.

---

### 5.4 Metadata & governance

**Standard fields (CI):** valid YAML, `description`, `domain`, columns, **`lineage`** where values come from other tables — see **[`governance_metadata.mdc`](../.cursor/rules/governance_metadata.mdc)**. PII classification is **not** part of metadata authoring yet (no `personal_data_classification` key, no PII-tier text in `description`). LGPD controls such as `table_privileges` are set in the **declaration**, inferred from column semantics or domain rules — see "Personal Data Handling" in that rule.

**Business-path table fields** (tables under the two allowed roots):

- **`owner`** — contributor email (as required by governance / CI).
- **`retention_policy`** and **`cost_center`** — **currently under definition.** This guide does **not** document how to choose or format values. Follow **`governance_metadata.mdc`**, failing CI messages, and **code owner** direction as those sources are updated.

| Tag | Rule |
|-----|------|
| **#Hard-Blocker-01** | New business work only under **`dags/ops_poc/**`** or **`dags/planning_and_performance/**`**. |
| **#Hard-Blocker-02** | **No RAW** (`datalake_*_raw`) in SQL. **CLEAN** allowed with correct metadata. |
| **#Metadata-Schema** | Governance YAML + business-path fields per **`governance_metadata.mdc`** and §5.4. |

**Cursor (optional):** [`.cursor/rules/business_contribution.mdc`](../.cursor/rules/business_contribution.mdc) · [`.cursor/skills/business-contribution/SKILL.md`](../.cursor/skills/business-contribution/SKILL.md)

---

<a id="a11-dag-execution-dependencies-plain-english"></a>

### 5.5 DAG execution dependencies (plain English)

**What:** `dependencies.yaml` says “**my** DAG waits until **these** upstream DAGs/tasks finish.”  
**How:** Only the **consumer** lists **upstream**. Downstream teams add **their** edge to **you** — never list downstream consumers on the producer’s entry.  
**Why it matters:** **Cycles** and wrong edges break scheduling and CI. Most business PRs **never** edit this file; ask a **code owner** if you think you need a new edge.

---

<a id="a6-ci-vs-forno-business-path"></a>

### 5.6 Testing & Forno (Option B — business path)

For work **only** under **`dags/ops_poc/**`** and **`dags/planning_and_performance/**`** following this guide, **merge is allowed when all GitHub CI checks (Woodpecker) are green**, **without** a mandatory **Forno** run **by default**, because many contributors lack Forno access.

**Still use Forno** when your **code owner** asks, or for **higher-risk** work (e.g. **new DAG**, **reverse ETL**, sensitive logic).

**Repo-wide note:** **[`core.mdc`](../.cursor/rules/core.mdc)** is **unchanged** and still describes engineering expectations (including Forno) for the **whole** repository. **This subsection does not amend `core.mdc`** — it records the **approved business-path** model **alongside** it.

---

<a id="a7-who-reviews-your-pr-codeowners"></a>

### 5.7 Code owners (GitHub)

GitHub uses **`CODEOWNERS`** so the right people are requested on pull requests:

- **`dags/ops_poc/**`** — @luisarodriguees @GabriellRodrigues @henriquedepaulo  
- **`dags/planning_and_performance/**`** — @luisarodriguees @GabriellRodrigues  

You may **also** see review requests for **`@quintoandar/bi-etl-ejuice-code-owners`**. That team provides **repo-wide** review on sensitive or high-impact paths (for example **`dags/dependencies.yaml`**). GitHub can show **both** the folder **CODEOWNERS** and **`bi-etl-ejuice-code-owners`** on the same PR — that reflects **branch protection and ownership rules**, not a mistake in your change.

---

<a id="a8-pull-requests-description-template"></a>

### 5.8 Pull requests: description template

**PR body:** use the repo **[PR description template](../.cursor/rules/pr_template.mdc)** (context, changes, testing, risk, links). Open PRs against **`master`** unless your team names another base.

If you **cannot** run `make` locally, need **`make create-dag-files`** on your branch, want a **Forno** run, or need help reading CI logs, **contact the code owners** for your path — see [§5.7 Code owners](#a7-who-reviews-your-pr-codeowners). GitHub usually suggests them as **Reviewers** on your PR; you can @-mention them in a PR comment with what you need.

---

## 6. Pro-tips & advanced logic

### 6.1 Short-circuit scheduling

To skip runs on days you don’t need (example: **first business day of month**), your team may add a **`short_circuit_customization`** block in `*_declaration.yml` (confirm exact function names with Data Engineering):

```yaml
short_circuit_customization:
  function: CHECK_IS_FIRST_BUSINESS_DAY_OF_MONTH
```

### 6.2 Historical reprocessing (“time travel”)

**What it is:** Re-running the pipeline for a **past date range** (backfill, restatement, or fixing data that was wrong or missing for a window).

**When it is used:** After a bug fix that must **rewrite history**, when a new column needs **historical** values, or for an agreed **one-off** reload — usually with **code owner** awareness.

**Who runs it:** If you **cannot** use the Airflow UI, a **Data Engineer or code owner** may **Trigger DAG w/ config** with the JSON window shown below.

Incremental loads often use **`extra_query_template_params`** in the declaration, for example:

```yaml
extra_query_template_params:
  load_start_date: "{{ get_date_param(dag_run, macros.ds_add(data_interval_start | ds, -1), 'load_start_date') }}"
  load_end_date: "{{ get_date_param(dag_run, data_interval_start | ds, 'load_end_date') }}"
```

Use **`{load_start_date}`** / **`{load_end_date}`** (or your param names) in SQL `WHERE` clauses. If you **cannot** open Airflow UI, ask a **DE or code owner** to **Trigger DAG w/ config** with JSON such as:

```json
{"load_start_date": "2024-01-01", "load_end_date": "2024-03-04"}
```

(Adjust keys to match your DAG’s configured params.)

---

## 7. Troubleshooting CI failures

**Databricks `databricks_conn_id`:** typical SQL pipelines (**raw / clean / enrich / dw** path) use **`databricks_new_env`**. **Metric**, **Qube**, and **reverse** use **`databricks_new`**. Wrong ID → runtime failures.

| Error type | Likely cause | What to try |
|------------|--------------|-------------|
| **Metadata / governance** | Missing twin `.yml`, short `description`, missing `lineage` or classification | Match `.sql`/`.yml` base names; fix paths from the log; see [`governance_metadata.mdc`](../.cursor/rules/governance_metadata.mdc) |
| **Declaration** | Invalid `dag.owner`, cluster, workflow | Compare `*_declaration.yml` to a working DAG in the same folder |
| **Stale / missing `*_dag.py`** | Declaration changed without regenerate | `make create-dag-files dag_name=...` or contact a code owner ([§5.7](#a7-who-reviews-your-pr-codeowners)) |
| **Dependencies** | Bad `dependencies.yaml` or task id | `make validate-dags-dependencies` |
| **Merge blocked** | Missing approvals | Add suggested **Code owners** |
| **Checks stalling** | Transient CI | Empty commit: `git commit --allow-empty -m "chore: trigger CI" && git push` |

**Where to look:** PR → **Checks** → failed job → failed **step** → **bottom** of log (file + line).

More: [Extended troubleshooting](#extended-troubleshooting) · [`fix-ci-failure` skill](../.cursor/skills/fix-ci-failure/SKILL.md)

---

<a id="section-c-technical-reference-and-policy"></a>

## 8. Technical reference & policy

Use when **CI or a reviewer** points you here, or you need **full** workflow and dependency detail.

### C.1 DAGs in a nutshell

<a id="c1-dags-in-a-nutshell"></a>

#### How a DAG is declared

Airflow DAGs are built from a **YAML declaration**, not by hand-writing task logic in Python. The thin `*_dag.py` file is generated — do not put business logic there.

Every declaration is named **`{dag_name}_declaration.yml`** (`.yml` only, not `.yaml`).

**Canonical reference:** [`.cursor/rules/dag_build.mdc`](../.cursor/rules/dag_build.mdc) · **Scaffold playbook:** [`.cursor/skills/create-dag/SKILL.md`](../.cursor/skills/create-dag/SKILL.md)

#### Folder layout (typical SQL pipeline)

```
dags/{business_domain}/{dag_name}/
├── {dag_name}_declaration.yml    # Source of truth for the DAG
├── {dag_name}_dag.py               # Generated — run make create-dag-files
├── queries/{layer}/*.sql           # One .sql per output table
├── metadata/{layer}/*.yml          # Governance — one .yml per .sql (same base name)
└── data_quality/{layer}/*.yml      # Optional — Great Expectations (Inmetro)
```

**Qube** DAGs under `dags/qube/` follow a different layout (no `queries/` / `metadata/` folders); logic lives in `bietlejuice/qube/jobs/`.

**Canonical reference:** [`.cursor/rules/core.mdc`](../.cursor/rules/core.mdc)

#### Declaration skeleton

Three required sections: **`dag`**, **`workflow`**, **`cluster`**.

| Section | Role |
|---------|------|
| `dag` | Airflow id (`name` without `bietlejuice.` prefix), owner, schedule, optional docs |
| `workflow` | `layer`, `type` (workflow kind), layer-specific options (e.g. `custom_schema`) |
| `cluster` | Databricks preset and `databricks_conn_id` |

After editing any `*_declaration.yml`:

```bash
make create-dag-files
```

#### Rules per artifact

| Artifact | Do | Don’t |
|----------|----|--------|
| **Declaration** | Match layer naming (`dw_`, `enrich_`, `metric_*__*`, etc.); use correct `databricks_conn_id` for the layer | Use `.yaml` extension; skip `make create-dag-files` after YAML edits |
| **SQL** | Match project SQL style; filter partitions; avoid `SELECT *` | Reference tables from a **higher** layer than your own (cross-layer rule) |
| **Metadata** | One YAML per SQL file; satisfy CI (descriptions, lineage / dimension-metric blocks) | Ship PII without classification and required controls |
| **Python (`bietlejuice/`)** | Follow Python conventions; add tests for new logic modules | Hardcode `prod` / `forno` or secrets — use `ConfigurationService` |

**Canonical references:** [`sql_conventions.mdc`](../.cursor/rules/sql_conventions.mdc) · [`governance_metadata.mdc`](../.cursor/rules/governance_metadata.mdc) · [`create-metadata-files` skill](../.cursor/skills/create-metadata-files/SKILL.md) · [`naming_conventions.mdc`](../.cursor/rules/naming_conventions.mdc)

#### Cross-layer joins

A query at layer **N** may only read tables from layer **N** or **below** (e.g. enrich may use clean; not dw or metric).

**Reference:** [`core.mdc`](../.cursor/rules/core.mdc) · [`.cursor/subagents/data_engineer_architect.md`](../.cursor/subagents/data_engineer_architect.md)

#### When to pull in a specialist

| Topic | Pointer |
|-------|---------|
| New/changed DAG across layers, workflow choice, CDC | [`data_engineer_architect.md`](../.cursor/subagents/data_engineer_architect.md) |
| Metadata, PII, sensitive data | [`governance_officer.md`](../.cursor/subagents/governance_officer.md) |
| Cluster sizing, backfills, performance | [`reliability_engineer.md`](../.cursor/subagents/reliability_engineer.md) |

---

<a id="c2-workflow-overview"></a>

### C.2 Workflow overview — what business teams usually use

**Workflow** = `workflow.type` in the declaration. **Layer** = where the table lives. **Typical lake/DW chain:** `raw` → `clean` → `enrich` → `dw`. **Metric** and **Qube** are **separate** pipelines (often parallel to DW for KPIs and the semantic layer), not an automatic “next step” after every DW table.

| Layer | Typical use | Recommended `workflow.type` | Notes |
|-------|-------------|----------------------------|--------|
| **raw** | Ingestion | `cdc`, `database_pull_delta`, etc. | Usually **not** business self-service paths |
| **clean** | Conform raw tables | `query_delta` | |
| **enrich** | Business logic, joins | `query_delta` | Cross-layer rule applies |
| **dw** | Kimball dims/facts | `query_delta` | `sk_*` / person model |
| **metric** | Pre-aggregated KPIs | `query` or `query_delta` | Metric DAGs often have **separate** CODEOWNERS |
| **reverse** | Exports | `load`, `access`, `load_access` | See [Scenario C](#recipe-3-reverse-etl-export-or-outbound-data) |
| **qube** | Semantic layer | `qube_*` specs | Under `dags/qube/` — different layout |

Job-cluster DAGs (`query_delta`, etc.) are capped at **100 tasks** per DAG.

<a id="databricks-conn-by-layer"></a>

#### Databricks connection ID by layer (`databricks_conn_id`)

| Layers | `databricks_conn_id` |
|--------|----------------------|
| raw (CDC / custom), clean, enrich, dw | `databricks_new_env` |
| metric, qube, reverse | `databricks_new` |

---

### C.3 Build → run — validate, Forno, ship

Use your team’s branching policy. **Pre-push checklist:** [`.cursor/skills/review-pr/SKILL.md`](../.cursor/skills/review-pr/SKILL.md)

**Local stack:** [`local/README.md`](../local/README.md) · [`setup-local-environment` skill](../.cursor/skills/setup-local-environment/SKILL.md)

| Step | Command |
|------|---------|
| Regenerate DAG Python | `make create-dag-files` or `make create-dag-files dag_name=<name>` |
| Style | `make check-style` / `make lint` |
| Unit tests | `make requirements-test` && `make unit-tests` |
| Declarations | `make validate-dag-declaration-files dag_name=<name>` |
| Metadata | `make validate-metadata-files-content` · `make validate-metadata-files-exist` |
| Lineage | `make validate-lineage-consistency` |

**Forno:** see [§5.6](#a6-ci-vs-forno-business-path) (**green CI** required; Forno **optional by default** on business folders). **[`core.mdc`](../.cursor/rules/core.mdc)** unchanged for repo-wide expectations. Skills: [`forno-merge`](../.cursor/skills/forno-merge/SKILL.md) · [`run-dag-locally`](../.cursor/skills/run-dag-locally/SKILL.md)

**CI failures:** [`fix-ci-failure` skill](../.cursor/skills/fix-ci-failure/SKILL.md) · PR template: [`pr_template.mdc`](../.cursor/rules/pr_template.mdc)

---

### Allowed contribution paths (summary)

Same as [§5.7 Code owners](#a7-who-reviews-your-pr-codeowners).

---

### DAG dependencies (full)

**What this file is for:** **`dags/dependencies.yaml`** encodes **orchestration only**—*when* DAGs run relative to each other. It does **not** replace **metadata `lineage`** (which column came from which source table).

**How entries work (mental model):** think “**waiting DAG** → **must finish after these upstream DAGs (or tasks)**.” Only the **consumer** that **needs** upstream freshness should declare the edge. If **DAG X** reads outputs of **DAG Y**, **X** lists **Y** as upstream—not the other way around.

**Why cycles and odd edges are dangerous:**

- **Circular dependencies** (even indirect) break scheduling assumptions and are rejected by validators.
- **Redundant** duplicate edges add noise and make incidents harder to debug.
- **Downstream listed on the producer’s entry** is the wrong direction and confuses ownership.

**CI/CD:** Pull requests that touch this file are checked by the same **Woodpecker** pipeline as the rest of the repo; `make validate-dags-dependencies` and `make validate-dependency-file-correctness` mirror what fails in CI. On a normal PR that **only** changes SQL/metadata under your DAG folder, **dependency file mechanics are not your blocker**—you usually never open `dependencies.yaml`.

**YAML shape (reference):**

- **Keys** = DAGs that **wait**. **Values** = **upstream** `bietlejuice.upstream_dag` or `bietlejuice.upstream_dag:task-name`.
- **Do not** list downstream consumers on **your** DAG entry—they declare **their** dependency on **you**.

**Automation:** `make dependencies-file` (`automate_dependencies.py`). **Fixes:** `dags/dependency_exceptions/manual_modifications.yaml`. More scripts: [`scripts/dependency_handling/README.md`](../scripts/dependency_handling/README.md).

| Command | Purpose |
|---------|---------|
| `make validate-dags-dependencies` | Cross-DAG consistency |
| `make validate-dependency-file-correctness` | File shape |

**Cursor:** [`create-dag` skill](../.cursor/skills/create-dag/SKILL.md) + [`business-contribution` skill](../.cursor/skills/business-contribution/SKILL.md)

**Onboarding summary:** [§5.5](#a11-dag-execution-dependencies-plain-english).

---

### For Cursor / AI assistant users (optional)

**If you do not use Cursor**, ignore this—your GitHub steps are unchanged.

| Your journey step | Cursor skill file (for the AI) |
|-------------------|--------------------------------|
| Local machine setup | `setup-local-environment` |
| Scaffold / metadata detail | `create-dag` · `create-metadata-files` |
| Business path rules | **`business-contribution`** |
| Dependencies file | `create-dag` + [`dependency_handling` README](../scripts/dependency_handling/README.md) |
| CI / Forno | `review-pr` · `fix-ci-failure` · `run-dag-locally` |
| Merge to Forno branch | `forno-merge` |

Humans: [Cursor AI guide](cursor_ai_guide.md).

---

<a id="extended-troubleshooting"></a>

### Extended troubleshooting

| Symptom | Where / example log hint | Likely cause | Fix |
|---------|--------------------------|--------------|-----|
| Metadata CI | `validate-metadata` / `governance` | Twin `.yml` missing, short `description`, missing `lineage` | Open path in log; [`governance_metadata.mdc`](../.cursor/rules/governance_metadata.mdc) |
| Declaration CI | `validate-dag-declaration` | Invalid `dag.owner`, bad `cluster` / `workflow` | Compare `*_declaration.yml` to peer DAG |
| Stale DAG in UI | Airflow shows old task list | `*_dag.py` not regenerated | `make create-dag-files` |
| Dependency CI | `validate-dags-dependencies` | Bad `dependencies.yaml` or task id | `make validate-dags-dependencies`; fix YAML |
| Merge blocked | PR **Reviewers** / “code owners” | Missing approval | Add reviewers from [§5.7](#a7-who-reviews-your-pr-codeowners) |

---

### Quick “see also” map (repo-wide)

| Need | File |
|------|------|
| This guide §1–7 (narrative + recipes) | **This doc** |
| Repo architecture | [`core.mdc`](../.cursor/rules/core.mdc) |
| Full DAG / cluster reference | [`dag_build.mdc`](../.cursor/rules/dag_build.mdc) |
| Scaffold DAG | [`create-dag` skill](../.cursor/skills/create-dag/SKILL.md) |
| Metadata | [`create-metadata-files` skill](../.cursor/skills/create-metadata-files/SKILL.md) |
| Qube | [`create-qube-spec` skill](../.cursor/skills/create-qube-spec/SKILL.md) |
| Databricks SQL | [`databricks_conventions.mdc`](../.cursor/rules/databricks_conventions.mdc) |

---

### Related docs

- [Documentation index](README.md)  
- [Cursor AI guide](cursor_ai_guide.md)  
- **Dependency scripts:** [`scripts/dependency_handling/README.md`](../scripts/dependency_handling/README.md)  
