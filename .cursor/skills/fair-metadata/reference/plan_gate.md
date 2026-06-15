# PLAN gate (mandatory — read first)

Hard stop for **`fair-metadata`**. If you have not completed the checklist below, you **must not** create, edit, or delete any file under `dags/**/metadata/**/*.yml`.

## Default = PLAN only

| User asks | You deliver | Forbidden until approval |
|-----------|-------------|---------------------------|
| audit FAIR, melhorar metadados, remediar domain/owner/table | **Remediation plan** + scope audit report | Any metadata YAML change |
| “execute”, “pode executar”, “approved”, “go ahead”, “aplica o plano” | **EXECUTE** phase | — |

**Ambiguous message** (“continua”, “faz isso”, “arruma”) → stay in **PLAN**; ask whether to execute.

## Checklist before any metadata edit

1. [ ] **Scope resolved** — inventory matches user request (repo folder / YAML `domain:` / owner / table / DAG) per [`scoping.md`](scoping.md) and [`domain_disambiguation.md`](domain_disambiguation.md); count published (`N files`); plan states **scope type**, repo folder (if any), and YAML allowlist value when fixing `domain:`
2. [ ] **Gate A** — every distinct `owner:` in inventory verified ACTIVE via `@tars` or **AskQuestion** completed for replacements; **none skipped** (offline audit lists UNVERIFIED until Trino)
3. [ ] **Gate B** — `make audit-fair-metadata-scope …` shows 0 F2-01/F2-02 description failures on clean / core / enrich / dw / metric in scope
4. [ ] **Gate C** — physical layout assessed; failures listed in plan gate summary (see [`SKILL.md`](../SKILL.md) Gate C)
5. [ ] Posted plan with heading `## FAIR metadata remediation plan` ([`remediation_plan.md`](remediation_plan.md) Phase D)
6. [ ] Ended PLAN message with **“Waiting for your approval before editing any metadata files.”**
7. [ ] User replied with **explicit execute approval**

**All seven checked** → only then use Write / StrReplace / Delete on metadata YAML.

## Discovery order

1. **Resolve scope** → closed inventory ([`scoping.md`](scoping.md))
2. **Local gates** → `make audit-fair-metadata-scope domain=…` (or `--owner`, `--fqn`, `--dag`); Gates A/B/C per [`SKILL.md`](../SKILL.md)
3. **Lake (`@tars`, optional)** → `checks_result_json` for production priority — supplements, does not replace steps 1–2

**Forbidden as sole audit:** PR diff only, BugBot comment paths only, or `-b branch` without scope flags when user asked for domain/owner/table.

## What PLAN phase may use

- `make audit-fair-metadata-scope` / `validate_metadata_cli --audit`
- Trino (`@tars`) for owner ACTIVE and lake assessment
- Read repo: SQL, declarations, metadata
- **AskQuestion** for owner decisions

## What PLAN phase must not use

- Write / StrReplace / Delete on `dags/**/metadata/**`
- `git commit` of metadata changes
- Shrinking scope below what the user requested
