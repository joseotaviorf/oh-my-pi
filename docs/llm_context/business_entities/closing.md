# Closing

## Overview

Closing (also called **CC2CS**, "Contract Created to Contract Signed") is the final step of the For Rent pre-contract journey. At this stage, a contract is generated for an accepted proposal and sent to the signatories — tenants, landlords, dwellers, sponsors (guarantors), and partners — who can request changes, refuse, or sign it. Closing is what materializes a deal, the bridge between a proposal and an active rental contract.

The lifecycle typically follows these stages:
1. **Draft** — the contract is being written/created (`dim_contract.status = 'Minuta'`, `dim_contract.closing_status = 'RedacaoContrato'`, `dim_contract.ts_draft_approved`)
2. **Sent for signature** — the draft is approved and sent to all signatories (`dim_contract.status = 'PreAssinaturas'`, `dim_contract.closing_status = 'ContratoEnviado'`)
3. **Signed** — all signatories signed; the closing is complete (`dim_contract.status = 'Ativo'`, `dim_contract.closing_status = 'ContratoAssinado'`, `dim_contract.ts_signature`)
4. **Cancelled before signing** — the closing fails (`dim_contract.status = 'Cancelado'`, `dim_contract.ts_canceled`, `dim_contract.cancellation_reason`)
5. **Finalized after signing** — the contract is finalized (`dim_contract.status = 'Finalizado'`) before or after the entrance date (`dim_contract.dt_entrance`)

Do note that `dim_contract.status` and `dim_contract.closing_status` do not encode the same information and should always be checked in tandem.

Not all closings reach signature. Some are cancelled before any signature (`OWNER_GAVE_UP_RENTING`, `TENANT_DOESNT_AGREE`, `SIG_DEADLINE_EXPIRED`, etc. in `cancellation_reason`); others go through multiple draft revisions when signatories request changes.

## Glossary and Synonyms

- **Closing**, **fechamento**, **fechamento de contrato** → the closing process that ends with a signed contract; identify in `dw_rent.dim_contract` via `closing_status` / `ts_signature`
- **CA2CS** (Credit Approved to Contract Signed) → metric that connects the credit stage with the closing stage by representing how many credit approvals eventually become signed contracts
- **CC2CS** (Contract Created to Contract Signed) → Can refer to the closing stage as a whole or to the closing leadtime metric, pre-computed as `dw_rent.fact_listing_rent_flows.cc2cs_working_minutes`
- **Minuta** → the contract draft (`dim_contract.status = 'Minuta'`)
- **Pré-assinatura**, **PreAssinaturas** → contract sent and waiting for signatures (`dim_contract.status = 'PreAssinaturas'`)
- **Contrato enviado** → `dim_contract.closing_status = 'ContratoEnviado'`
- **Contrato assinado**, **assinatura de contrato**, **assinatura** → `dim_contract.closing_status = 'ContratoAssinado'`; signing timestamp is `dim_contract.ts_signature`
- **Signatário**, **signatory** → a person involved in signing the contract; one row per person in `dw_rent.fact_contract_people`, identified by `contract_role`
- **Inquilino**, **locatário**, **tenant** → `fact_contract_people.contract_role = 'tenant'`
- **Proprietário**, **locador**, **landlord** → `fact_contract_people.contract_role = 'landlord'`
- **Fiador**, **sponsor**, **guarantor** → `fact_contract_people.contract_role = 'sponsor'`
- **Morador**, **dweller** → `fact_contract_people.contract_role = 'dweller'`
- **Partner** → `fact_contract_people.contract_role = 'partner'`
- **Data de vigência**, **data de entrada**, **data de início do contrato** → `dw_rent.dim_contract.dt_entrance`
- **Early Demand** → a listing that starts a new rent flow (proposal → closing) before the previous contract on the same house finishes its termination process. The house is still published (`dw_rent.dim_house_listing.status = 'PUBLISHED'`), the previous contract is still active (`dw_rent.dim_contract.status = 'Ativo'`), and the termination end date is still in the future (`datalake_terminator_clean.termination.dt_termination`)
- **Representante legal**, **legal representative**, **procurador** → a landlord (`type = 'Proprietario'`) whose `datalake_ebdb_clean.contract_person.legal_representative_cpf IS NOT NULL`. These are still registered as landlords (`contract_role = 'landlord'`), not as a separate role.
- **Partner**, **imobiliária parceira** → `dw_rent.fact_contract_people.contract_role = 'partner'`

## Tables

> **`id_contract` vs `sk_contract`:** `dim_contract` carries both columns — they hold the same numeric value (the EBDB contract ID). All other DW tables (`fact_contracts`, `fact_contract_people`, `fact_listing_rent_flows`) expose only `sk_contract`. Clean/lake tables expose only `id_contract`. Within the DW layer, join on `sk_contract = sk_contract`. For cross-layer joins (clean → DW), use `clean_table.id_contract = dw_table.sk_contract` (cast to BIGINT if the clean column is a string).

| You need... | Use this table |
|-------------|----------------|
| Contract attributes and signing state at contract grain (one row per contract) | `dw_rent.dim_contract` (`dc`) — primary table for closing analysis. Carries `status`, `closing_status`, `signature_type`, `ts_signature`, `ts_draft_approved`, `ts_canceled`, `cancellation_reason`, `is_ongoing_contract`. **Does not carry house/tenant/owner FKs** — see `fact_contracts`. |
| House, tenant, owner FKs at contract grain | `dw_rent.fact_contracts` (`fc`) — exposes `sk_contract`, `sk_house`, `sk_tenant`, `sk_owner`, `sk_proposal`, `sk_house_listing`. JOIN to `dim_contract` via `sk_contract`. |
| Signatories per contract (multiple rows per contract) | `dw_rent.fact_contract_people` (`fcp`) — one row per person involved in the contract. Filter or group by `contract_role` (`tenant`, `landlord`, `sponsor`, `dweller`, `partner`). JOIN to `dim_contract` via `fcp.sk_contract = dc.sk_contract`. |
| CC2CS funnel timestamps and pre-computed SLA | `dw_rent.fact_listing_rent_flows` (`flrf`) — carries `sk_contract`, `sk_proposal`, `ts_contract_created`, `ts_contract_signed`, and `cc2cs_working_minutes` (working-time leadtime from creation to signature). JOIN to `dim_contract` via `flrf.sk_contract = dc.sk_contract`. |
| Raw signature events per recipient (sent, signed, refused, version) | `datalake_signatures_clean.signature` (`sig`) joined with `datalake_signatures_clean.agreement_document` (`ad`) via `sig.id_agreement_document = ad.id`, and `datalake_signatures_clean.recipient` (`r`) via `sig.id_recipient = r.id`. **No direct contract FK exists** in these tables — see Critical rules. |
| Termination dates for the previous contract (Early Demand detection) | `datalake_terminator_clean.termination` (`t`) — carries `dt_termination` (scheduled termination end date) and `ts_created` (when the termination request was filed). JOIN to `dim_contract` via `CAST(t.id_contract AS BIGINT) = dc.sk_contract`; match house via `id_house`. |
| Offer attributes (one row per offer on a property) | `dw_rent.dim_offer` (`do`) — one row per offer a tenant makes on a house. Key columns for closing context: `sk_offer` (PK), `id_property` (house FK), `id_user` (tenant FK), `status` (`Aprovada`, `EmNegociacao`, `Rejeitada`), `dt_first_sent` (when the offer was first sent — use this as the "offer date" for Early Demand detection), `dt_created`, `dt_analysis` (owner decision timestamp). Does not carry `sk_contract` — walk from offer to contract via `fact_listing_rent_flows` (`sk_proposal`) or `fact_contracts`. |
| House listing publication status | `dw_rent.dim_house_listing` — `status = 'PUBLISHED'` indicates the house is actively listed. |
| Legal representative details per signatory (CPF, name, email, RG, flag) | `datalake_ebdb_clean.contract_person` (`cp`) — one row per person per contract, same grain as `fact_contract_people`. Key columns for legal rep: `is_with_representative` (boolean flag), `legal_representative_cpf`, `legal_representative_name`, `legal_representative_email`, `legal_representative_rg`. Role field is `type` (values: `Proprietario`, `Inquilino`, `Fiador`, `Morador`, `Partner`, `ThirdPartyPartner`). JOIN to `dim_contract` via `CAST(cp.id_contract AS BIGINT) = dc.sk_contract`. Use this table only when the question involves legal representatives — for all other signatory analysis, prefer `dw_rent.fact_contract_people`. |

**Critical rules:**
- **`dim_contract` does not carry `sk_house`, `sk_tenant`, or `sk_owner`** — these live in `dw_rent.fact_contracts`. JOIN via `sk_contract` whenever a closing question references house, tenant, or owner.
- **Signed-state filter**: a contract is "signed" when `closing_status = 'ContratoAssinado'` or, equivalently, when `ts_signature IS NOT NULL`. Prefer either of these for the broader "has been signed at some point" question. `status = 'Ativo'` is correct only for currently-active signed contracts and excludes signed contracts that were later finalized (`Finalizado`) or cancelled — do not use it as a generic signed-state filter.
- **Signature clean tables have no `id_contract`** — `datalake_signatures_clean.signature` / `agreement_document` / `recipient` only expose `id_internal_reference`, `id_external_reference`, `internal_reference_name`, `external_reference_name`. The mapping to `dw_rent.dim_contract` is not defined anywhere in this repo's SQL. For contract-grain signing analysis, use `dim_contract.ts_signature` and `closing_status` instead of joining with `datalake_signatures_clean.*`. Use the signatures clean tables only when the question is genuinely about per-recipient signature events (e.g., refusal rate by recipient, time between sent and signed at the recipient level), and even then expect to inspect `internal_reference_name` to identify the entity type.
- **`dim_contract` includes drafts and cancelled rows** — there is one row per contract regardless of stage. Filter explicitly when you need only signed deals.
- **`fact_contract_people` does not carry legal representative data** — columns like `is_with_representative`, `legal_representative_cpf`, etc. exist only in the clean layer (`datalake_ebdb_clean.contract_person`). To identify whether a landlord has a legal representative, you must join to that table via `CAST(cp.id_contract AS BIGINT) = fcp.sk_contract` and `cp.type = 'Proprietario'`.
- **`contract_role` values in DW vs `type` values in clean** — the DW uses English lowercase (`landlord`, `tenant`, `sponsor`, `dweller`, `partner`); the clean table uses Portuguese/mixed-case (`Proprietario`, `Inquilino`, `Fiador`, `Morador`, `Partner`, `ThirdPartyPartner`). Always match the correct vocabulary for the layer you're querying.

## Key Metrics

- Contracts signed in a period (`COUNT(*)` over `dw_rent.dim_contract` filtered by `DATE(ts_signature)` and `closing_status = 'ContratoAssinado'`)
- Signing rate — signed contracts over contracts created in a period (uses `closing_status` and `ts_created`)
- CC2CS leadtime — `dw_rent.fact_listing_rent_flows.cc2cs_working_minutes` (working minutes from contract creation to signature)
- Cancellation rate before signing — `dim_contract.status = 'Cancelado' AND ts_signature IS NULL`, broken down by `cancellation_reason`
- Distribution of signatories per contract — `COUNT(*)` over `dw_rent.fact_contract_people` `GROUP BY sk_contract`
- Distribution of signatures by `signature_type` (`Eletronica` or null) in `dim_contract`
- New contracts created on houses that already have an active contract — self-pattern over `fact_contracts` by `sk_house` plus `dim_contract.is_ongoing_contract`
- Early Demand rent flows — listings where a new proposal was sent while the previous contract's termination is still pending; detected by comparing `dw_rent.dim_offer` timestamps against `datalake_terminator_clean.termination.dt_termination` and `ts_created` for the same house
- Annulment rate before entrance date: Volume of contracts finalized before contract start date, divided by contracts started in each period

## Relationships with Other Entities

### Proposal (1:1 — one contract is born from one proposal)

- `fc.sk_proposal = dp.sk_proposal` (`fact_contracts` joined with `dw_rent.dim_proposal`)
- Use this to walk the funnel backwards: proposal acceptance → contract creation → signature
- `fc.sk_proposal = -1` means there is no source proposal (rare; treat as orphan contract)

### House and Listing (N:1 — many contracts to one house)

- `fc.sk_contract = dc.sk_contract`, then `fc.sk_house` for the house and `fc.sk_house_listing` for the listing
- Use this JOIN whenever the question references a property (e.g., "houses with multiple contracts", "houses already rented")
- For house grain, listing version grain, and Early Demand flags see [`business_entities/house_and_listing.md`](house_and_listing.md)

### Signatories (1:N — one contract has multiple signatories)

- `fcp.sk_contract = dc.sk_contract`
- Roles: `contract_role` ∈ `tenant`, `landlord`, `sponsor`, `dweller`, `partner`
- Multiple rows per role are possible (e.g., two tenants, two landlords, one or more sponsors)
- For signatory counts use this table; for signature events at the recipient level use `datalake_signatures_clean.signature`

### Termination (1:0..1 — a signed contract may later be terminated)

- `ft.sk_contract = dc.sk_contract` (`dw_offboarding.fact_terminations`)
- Closing precedes termination; see the Termination entity for the post-signature lifecycle
- Restrict to signed contracts when comparing closing volume vs termination volume

### Early Demand (special case — new rent flow starts before previous contract ends)

- Join `dw_rent.dim_offer.dt_first_sent` against `datalake_terminator_clean.termination.ts_created` / `dt_termination` on the same house to detect whether the new flow started during the previous contract's termination window.

### Payments (1:N — a signed contract generates many invoices)

- Payment tables join via `id_contract` — use `dim_contract.id_contract` (same value as `sk_contract`)
- See the Payments entity for the full payment lifecycle

## Dos and Don'ts

**Do:**
- Use `dw_rent.dim_contract` as the entry point for closing-centric questions
- Filter signed contracts with `closing_status = 'ContratoAssinado'` (or equivalently `ts_signature IS NOT NULL`)
- Join through `dw_rent.fact_contracts` whenever the question mentions house, tenant, owner, or proposal — `dim_contract` does not have those FKs
- Use `dw_rent.fact_contract_people` (one row per signatory) for any question about signatory counts, roles, or distribution
- Use `dw_rent.fact_listing_rent_flows.cc2cs_working_minutes` for CC2CS leadtime instead of computing the date diff yourself — it already accounts for working hours
- For "houses with active contract" use `dim_contract.is_ongoing_contract = TRUE` and walk to the house via `fact_contracts.sk_house`
- For Early Demand detection, compare the new proposal date against `datalake_terminator_clean.termination.ts_created` (termination request) and `dt_termination` (scheduled end) on the same house

**Don't:**
- Don't try to join `datalake_signatures_clean.signature` (or `agreement_document`) directly to `dw_rent.dim_contract` — there is no `id_contract` in those clean tables, only `id_internal_reference` / `id_external_reference` / `*_reference_name`
- Don't use `dim_contract.status = 'Ativo'` as a generic "has been signed" filter — `Ativo` only captures currently-active signed contracts and excludes signed contracts that were later finalized (`Finalizado`) or cancelled. For the broader signed-state question use `closing_status = 'ContratoAssinado'` or `ts_signature IS NOT NULL`; reserve `status = 'Ativo'` for the "currently active" question
- Don't count `dim_contract` rows assuming each represents a closed deal — drafts (`Minuta`), pre-signature (`PreAssinaturas`), and cancelled (`Cancelado`) rows are also present
- Don't compute CC2CS by hand from `ts_created` and `ts_signature` if `fact_listing_rent_flows` is available — the pre-computed `cc2cs_working_minutes` already excludes non-working hours
- Don't confuse `ts_canceled` (cancelled before signing) with `dt_annulment` (annulled after signing); the former lives in the closing journey, the latter belongs to early termination
- Don't confuse Early Demand (new rent flow starting before the previous contract ends termination) with a simple contract overlap — Early Demand specifically requires the new proposal to fall between the termination request (`ts_created`) and the scheduled termination end date (`dt_termination`)

## Golden Queries

### Query 1 — Contracts signed in a period

How many contracts were signed yesterday, last week, or this year. Pattern: filter `dim_contract` by signed state and `ts_signature`.

```sql
SELECT
    DATE(dc.ts_signature) AS dt_signed,
    COUNT(*) AS total_signed
FROM dw_rent.dim_contract AS dc
WHERE dc.closing_status = 'ContratoAssinado'
  AND dc.ts_signature >= DATE '2026-01-01'
GROUP BY DATE(dc.ts_signature)
ORDER BY dt_signed DESC
```

### Query 2 — Distribution of signatories per contract

Histogram of how many signatories each signed contract has, broken down by role. Uses `fact_contract_people` joined with `dim_contract`.

```sql
WITH signatories_per_contract AS (
    SELECT
        fcp.sk_contract,
        COUNT(*) AS total_signatories,
        COUNT_IF(fcp.contract_role = 'tenant') AS total_tenants,
        COUNT_IF(fcp.contract_role = 'landlord') AS total_landlords,
        COUNT_IF(fcp.contract_role = 'sponsor') AS total_sponsors,
        COUNT_IF(fcp.contract_role = 'dweller') AS total_dwellers,
        COUNT_IF(fcp.contract_role = 'partner') AS total_partners
    FROM dw_rent.fact_contract_people AS fcp
    GROUP BY fcp.sk_contract
)
SELECT
    spc.total_signatories,
    COUNT(*) AS total_contracts
FROM signatories_per_contract AS spc
JOIN dw_rent.dim_contract AS dc
    ON spc.sk_contract = dc.sk_contract
WHERE dc.closing_status = 'ContratoAssinado'
GROUP BY spc.total_signatories
ORDER BY spc.total_signatories
```

### Query 3 — New contracts created on houses that already have an active contract

Identifies overlap closings: a new contract is created for a house while a previous contract is still ongoing. Self-joins `fact_contracts` on `sk_house` and uses `dim_contract.is_ongoing_contract` on the previous side.

```sql
SELECT
    fc_new.sk_contract AS sk_new_contract,
    dc_new.ts_created AS ts_new_contract_created,
    dc_new.closing_status AS new_closing_status,
    fc_existing.sk_contract AS sk_existing_contract,
    dc_existing.dt_start AS existing_contract_started,
    dc_existing.dt_intended_end AS existing_contract_intended_end,
    fc_new.sk_house
FROM dw_rent.fact_contracts AS fc_new
JOIN dw_rent.dim_contract AS dc_new
    ON fc_new.sk_contract = dc_new.sk_contract
JOIN dw_rent.fact_contracts AS fc_existing
    ON fc_existing.sk_house = fc_new.sk_house
    AND fc_existing.sk_contract <> fc_new.sk_contract
JOIN dw_rent.dim_contract AS dc_existing
    ON fc_existing.sk_contract = dc_existing.sk_contract
WHERE dc_existing.is_ongoing_contract = TRUE
  AND dc_new.ts_created >= DATE '2026-01-01'
  AND dc_new.ts_created BETWEEN dc_existing.dt_start AND COALESCE(dc_existing.dt_intended_end, DATE '9999-12-31')
ORDER BY dc_new.ts_created DESC
```

### Query 4 — CC2CS leadtime per signed contract

Closing leadtime (working minutes from contract creation to signature). Uses the pre-computed `cc2cs_working_minutes` in `fact_listing_rent_flows`.

```sql
SELECT
    flrf.sk_contract,
    flrf.ts_contract_created,
    flrf.ts_contract_signed,
    flrf.cc2cs_working_minutes,
    flrf.cc2cs_working_minutes / 60.0 AS cc2cs_working_hours
FROM dw_rent.fact_listing_rent_flows AS flrf
WHERE flrf.ts_contract_signed >= DATE '2026-01-01'
ORDER BY flrf.cc2cs_working_minutes DESC
```

### Query 5 — Share of contracts with multiple owners and/or legal representatives

Proportion of signed contracts that have more than one landlord or at least one landlord acting through a legal representative. Uses `datalake_ebdb_clean.contract_person` for representative data and `dim_contract` for signed-state filter.

```sql
WITH landlord_info AS (
    SELECT
        cp.id_contract,
        COUNT(*) AS total_landlords,
        COUNT_IF(cp.legal_representative_cpf IS NOT NULL) AS landlords_with_representative
    FROM datalake_ebdb_clean.contract_person AS cp
    INNER JOIN dw_rent.dim_contract AS dc
        ON dc.sk_contract = CAST(cp.id_contract AS BIGINT)
    WHERE dc.closing_status = 'ContratoAssinado'
      AND dc.ts_signature >= DATE '2025-01-01'
      AND cp.type = 'Proprietario'
    GROUP BY cp.id_contract
)
SELECT
    COUNT(*) AS total_contracts,
    COUNT_IF(total_landlords > 1) AS contracts_multiple_landlords,
    COUNT_IF(landlords_with_representative > 0) AS contracts_with_legal_rep,
    COUNT_IF(total_landlords > 1 OR landlords_with_representative > 0) AS contracts_multi_landlord_or_rep,
    ROUND(100.0 * COUNT_IF(total_landlords > 1) / COUNT(*), 2) AS pct_multiple_landlords,
    ROUND(100.0 * COUNT_IF(landlords_with_representative > 0) / COUNT(*), 2) AS pct_with_legal_rep,
    ROUND(100.0 * COUNT_IF(total_landlords > 1 OR landlords_with_representative > 0) / COUNT(*), 2) AS pct_multi_landlord_or_rep
FROM landlord_info
```
