# Domain disambiguation — repo folder vs YAML `domain:`

Whenever the user asks to audit or remediate FAIR metadata **by domain**, resolve **two different concepts** before building the inventory. This applies to **every domain folder** under `dags/`, not only governance.

## Two concepts (do not conflate)

| Concept | Meaning | How to scope | CLI today |
|---------|---------|--------------|-----------|
| **Repo folder** | Top-level (or nested) domain folder path under `dags/` | `dags/{folder}/**/metadata/**/*.yml` | `make audit-fair-metadata-scope domain={folder}` |
| **YAML `domain:` field (F2-01)** | Allowlisted catalog domain **inside** metadata YAML | All YAML with `domain: {Allowlist Value}` repo-wide | **No flag** — use `rg` (see below) |

**Default for domain work:** user says “domain X” → scope the **repo folder** `dags/{folder}/`.  
**Exception:** user explicitly names the **allowlist string** (e.g. “tabelas com domain For Rent no catálogo”) → scope by **YAML field** repo-wide.

Inventories **overlap but differ** whenever tables in other folders use the same YAML `domain:` (common for `Data Ops & Governance`, `Data Platform`, `Cross`).

Full allowlist: `.cursor/rules/fairness_metadata.mdc` (synced with `METADATA_DOMAIN_CI_ALLOWLIST_PATTERN`).

---

## Repo folder → YAML `domain:` mapping

CLI `--domain` uses the **folder basename** (snake_case). Metadata `domain:` must be an **allowlist** value (often Title Case, spaces, `&`).

| Repo folder (`--domain`) | Typical YAML `domain:` | Notes |
|--------------------------|------------------------|-------|
| `agents` | `Agents` | Usually 1:1 |
| `atlas_db` | `Atlas DB` | |
| `broker_xp` | `Broker XP` | |
| `conversational_xp` | `Conversational XP` | |
| `cross` | `Cross` | |
| `ds_pricing` | `DS Pricing` | |
| `fintech` | `Fintech` | |
| `for_rent` | `For Rent` | Folder ≠ YAML string |
| `for_sale` | `For Sale` | |
| `governance` | **`Data Ops & Governance`** | **Not** `Governance` / `Data Governance` |
| `growth` | `Growth` | |
| `house_and_listing` | `House and Listing` | |
| `international` | `International` | |
| `journey_optimizer` | `Journey Optimizer` | |
| `mlops` | `MLOps` | |
| `people` | `People` | |
| `qcx` | `QCX` | |
| `support_and_service` | `Support and Services` | Singular folder, plural allowlist |
| `tech_platform` | `Tech Platform` | |
| `platform` | `Data Platform`, `Data Life Cycle`, or `Data Ops & Governance` | **Mixed** — read sibling DAGs in folder |
| `core` | Business domain of the entity (e.g. `House and Listing`, `Broker XP`) or `Data Platform` | Per-DAG — read sibling metadata |
| `planning_and_performance`, `publisher_xp`, other | — | No fixed 1:1 — inspect metadata in folder |

When fixing `domain:` in EXECUTE, use the **allowlist** column — never the repo folder name (e.g. never `domain: for_rent` or `domain: governance`).

Cross-reference: domain mapping in [`create-dag/SKILL.md`](../../create-dag/SKILL.md) Step 4.

---

## When disambiguation is required

Apply Step 0 below when **any** of these hold:

1. User says a **domain or product line name** without specifying repo folder vs catalog field.
2. Repo folder name **does not appear verbatim** in the FAIR allowlist (most folders).
3. Folder has **multiple valid** YAML domains (`platform`, `core`).
4. User uses a **colloquial alias** (“data governance”, “rent”, “listing”, “ops”).
5. User might want **repo-wide** catalog domain (YAML field) including tables outside `dags/{folder}/`.

### When AskQuestion is mandatory

- Ambiguous phrasing: “corrigir domain for rent”, “governance no catálogo”, “platform tables”.
- `platform` or `core` scope without a DAG name.
- User says allowlist value but might mean only one domain folder.

### When default is enough (no AskQuestion)

User clearly says **repo folder** or path:

- “audite FAIR do domain `for_rent`” / “pasta people”
- “DAG `governance/metabase`”
- “tabelas do owner X **no domain governance**” (folder + owner → intersect)

Still **publish both** in the plan: repo folder scope **and** expected YAML `domain:` from the table above.

---

## Step 0 — disambiguate (every domain request)

### 1. Parse user intent

| Signal | Likely scope |
|--------|--------------|
| Folder name, snake_case, “domain folder”, “pasta `dags/…`” | **Repo folder** |
| Exact allowlist string (“For Rent”, “Data Ops & Governance”) | **YAML field** repo-wide |
| DAG name only | **`--dag {folder}/{dag}`** — infer folder from path |
| Owner email | **`--owner`** — optional `--domain` intersect |

### 2. Publish in the plan (always)

```markdown
**Scope type:** repo folder | YAML domain field | DAG | owner | FQN
**Repo folder:** `dags/for_rent/` (if applicable)
**YAML domain (allowlist):** `For Rent` — use when fixing `domain:` in EXECUTE
**Inventory:** N metadata file(s)
```

Replace values per mapping table. For `platform` / `core`, note “per-DAG — see sibling metadata”.

### 3. AskQuestion template (generic)

> Escopo FAIR para “{user_domain_label}”:
>
> 1. **Pasta `dags/{folder}/`** — padrão domain no monorepo (~N YAML)  
> 2. **Campo `domain: {Allowlist Value}`** em todo o repo (~M YAML, pode incluir outras pastas)  
> 3. **DAG específico** — qual? (`{folder}/{dag}`)  
> 4. **Interseção** com owner (email)

Wait for answer before final inventory count when options 1 vs 2 are both plausible.

---

## Worked example — governance (non-exhaustive)

| User says | Default scope | YAML `domain:` when fixing |
|-----------|---------------|----------------------------|
| governance, data governance | `dags/governance/` | `Data Ops & Governance` |
| Data Ops & Governance (explicit) | YAML field repo-wide | already allowlist |
| metabase | `--dag governance/metabase` | usually `Data Ops & Governance` |

Legacy invalid values in `dags/governance/`: `Data Governance`, `Governance` → remediate to **`Data Ops & Governance`**.

Platform DAGs may also set `domain: Data Ops & Governance` — only in scope if user chose YAML-field repo-wide scope.

---

## Commands by scope type

### Repo folder (default)

```bash
find "dags/${FOLDER}" -path '*/metadata/*/*.yml' | sort
make audit-fair-metadata-scope domain="${FOLDER}"
```

Examples: `domain=for_rent`, `domain=people`, `domain=governance`.

### YAML `domain:` field (repo-wide)

```bash
rg -l '^domain:\s*For Rent\s*$' dags --glob '**/metadata/*/*.yml' | sort
```

Allowlist values with `&` or spaces must match YAML literally (quote in shell as needed):

```bash
rg -l '^domain:\s*Data Ops & Governance\s*$' dags --glob '**/metadata/*/*.yml'
```

Run Gates A/B on the path list (`-f` per file or batched `--audit`).

### Intersect folder + owner

```bash
make audit-fair-metadata-scope domain=for_rent owner=name@quintoandar.com.br
```

---

## EXECUTE reminders

- **Scope** = what the user chose in Step 0 (folder, YAML field, DAG, owner, FQN).
- **`domain:` in YAML** = allowlist string from the mapping table — never the repo folder basename.
- Re-run audit on the **same user scope** after EXECUTE, not PR diff alone.
