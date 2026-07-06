# FR Transact

## Overview

**FR Transact** is the For Rent (aluguel) **pre-contract transaction funnel** at QuintoAndar — every step a tenant prospect goes through on a property *before* the rental contract becomes active. It is the For Rent analog of [`fs-transact.md`](fs-transact.md) (For Sale). The journey is anchored to the **rent flow**: the tuple `(property, tenant prospect)` and all of its events over time.

The pre-contract lifecycle follows these stages (canonical event abbreviation in parentheses, from `dim_rent_event_type`):

1. **Visit booked / completed** (VB / VC) — tenant prospect schedules and attends a property visit (`fact_listing_rent_flows.sk_booking_created_date`, `flg_visit_completed`)
2. **Offer submitted** (OS) — tenant sends an offer to the owner (`dim_offer.dt_first_sent`)
3. **Offer approved** (OA) — owner accepts the offer; an accepted offer becomes a proposal (`dim_offer.dt_analysis`, `dim_offer.status = 'Aprovada'`)
4. **Evaluation started / positive** (ES / EP) — credit evaluation begins and returns positive (`dim_proposal.dt_first_credit_evaluation_init` / `dt_first_credit_evaluation_positive`)
5. **Document sent** (DS) — tenant sends documentation (`dim_proposal.dt_tenant_first_document_sent`)
6. **Credit approved** (CA) — credit analysis is approved; the proposal is cleared for contract (`dim_proposal.dt_credit_last_approved`)
7. **Contract created** (CC) — a contract is drafted (`dim_contract.status = 'Minuta'`, `dim_contract.ts_created`)
8. **Contract sent for signature** — draft approved and sent (`dim_contract.status = 'PreAssinaturas'`, `dim_contract.ts_draft_approved`)
9. **Contract signed** (CS) — all signatories sign (`dim_contract.ts_signature`, `closing_status = 'ContratoAssinado'`)
10. **Contract active** — the rental begins (`dim_contract.status = 'Ativo'`)

Stages 7–9 (contract draft → sent → signed) are the **closing** sub-stage, documented in depth in [`closing.md`](closing.md) (CC2CS journey, signatories, cancellation reasons). FR Transact covers the **whole funnel**; defer to `closing.md` for closing-specific signatory/legal-representative detail.

Not every rent flow follows every step: many drop at visit or offer (no interest, owner stalled, house reserved), some skip the visit via a **direct offer**, and offers can be rejected, proposals can fail credit, and contracts can be cancelled before signing (`dim_contract.status = 'Cancelado'`) or annulled after (`dt_annulment`).

### Advance payment (Sinal)

The **sinal** (advance payment) is an **optional reservation product** within a rent flow: a tenant prospect pays an upfront amount (the `payment_amount`, a fraction of the rent set by `payment_percentage`) to reserve the property and signal intent while documentation and credit run. It is **not a mandatory funnel stage** — only some flows have a sinal — and it is owned by the **Rental Transact** system (`datalake_rental_transact*`), distinct from the For-Sale "Sinal / Earnest Payment" (~6% of the sale price) documented in [`fs-transact.md`](fs-transact.md) and [`bank_reconciliation.md`](bank_reconciliation.md). Each advance payment is keyed by `uuid_advance_payment`, attached to its rent flow via `uuid_offer` (= the rent-flow UUID), and moves through a payment lifecycle: `CREATED → PENDING → PROCESSING → PAID → FINISHED`, with off-ramps `CANCELED`, `PROCESSING_REFUND → REFUNDED`, `CHARGEBACK`, and `RETAINED` (cancelled but QuintoAndar keeps the amount). The advance-payment milestones are also emitted as `ADVANCE_PAYMENT`-stage events in the rent-demand-events funnel (see Tables).

## Glossary and Synonyms

- **Rent flow**, **fluxo de locação**, **jornada de locação** → the `(property, tenant prospect)` tuple and all its pre-contract events; key `sk_rent_flow`. One row per flow in `dw_rent.fact_rent_flows`; one row **per event** in `dw_rent.fact_listing_rent_flows`.
- **Tenant prospect**, **prospect**, **inquilino em potencial** → the candidate tenant driving the flow (`fact_listing_rent_flows.sk_client`, `fact_rent_demand_events.sk_tenant_prospect`)
- **Offer**, **oferta** → tenant proposal of rent value to the owner (`dw_rent.dim_offer`); `status` ∈ `EmNegociacao`, `Aprovada`, `Rejeitada`. OS = `dt_first_sent`, OA = `dt_analysis`
- **Direct offer**, **oferta direta** → offer sent without a prior visit (`fact_rent_flows.nbr_direct_offers_submitted`)
- **Proposal**, **proposta** → an accepted offer that enters documentation + credit (`dw_rent.dim_proposal`); `status` ∈ `Nova`, `EmAnalise`, `PreMinuta`, `Aprovada`, `Rejeitada`
- **Credit analysis / evaluation**, **análise de crédito**, **avaliação de crédito** → tenant credit clearance; ES/EP/CA milestones on `dim_proposal` (`dt_first_credit_evaluation_init`, `dt_first_credit_evaluation_positive`, `dt_credit_last_approved`); outcome in `result_credit_evaluation` (`PRE_APPROVED`, `PRE_REJECTED`, `REGULAR`) and `status_sortinghat`
- **Sorting Hat** → the credit-policy microservice that scores proposals (`dim_proposal.status_sortinghat`)
- **Guarantee**, **garantia**, **fiança**, **seguro fiança** → rental guarantee chosen by the tenant (`dim_proposal.guarantee`, `dim_contract.guarantee`)
- **Minuta** → contract draft (`dim_contract.status = 'Minuta'`; proposal draft is `dim_proposal.status = 'PreMinuta'`)
- **Pré-assinatura**, **PreAssinaturas** → contract sent and awaiting signatures (`dim_contract.status = 'PreAssinaturas'`)
- **Contrato assinado**, **assinatura**, **fechamento** → signed contract (`dim_contract.closing_status = 'ContratoAssinado'`, `ts_signature`) — see [`closing.md`](closing.md)
- **Ativo** → currently active signed contract (`dim_contract.status = 'Ativo'`)
- **CA2CC** → Credit Approved → Contract Created leadtime, pre-computed in **working minutes** (`fact_listing_rent_flows.working_min_credit_approved_to_contract_created`)
- **CA2CS** → Credit Approved → Contract Signed leadtime, working minutes (`working_min_credit_approved_to_contract_signed`)
- **CC2CS** → Contract Created → Contract Signed leadtime, working minutes (`working_min_contract_created_to_contract_signed`)
- **Funnel step**, **etapa do funil** → the stage where the rent flow currently sits or stopped (`fact_listing_rent_flows.funnel_step`)
- **Drop reason**, **motivo de queda** → why the flow stopped at its funnel step (`fact_listing_rent_flows.funnel_step_drop_reason`)
- **Offer Express** → automatic minuta approval path — the dominant `Minuta → PreAssinaturas` transition reason in the contract audit trail
- **contract_aud** → contract audit trail (Hibernate Envers); one row per contract field-level revision, used to time status transitions and read transition reasons
- **Sinal**, **advance payment**, **sinal de reserva** → the optional upfront deposit a tenant prospect pays to reserve a property in a rent flow (`datalake_rental_transact_clean.advance_payment`, key `uuid_advance_payment`); `status` ∈ `CREATED`, `PENDING`, `PROCESSING`, `PAID`, `FINISHED`, `CANCELED`, `PROCESSING_REFUND`, `REFUNDED`, `CHARGEBACK`, `RETAINED`. **For Rent only** — not the For-Sale earnest payment in [`fs-transact.md`](fs-transact.md)
- **Sinal retido**, **retained**, **RETAINED** → advance payment cancelled where QuintoAndar keeps the amount (no refund to the payer) — `advance_payment.status = 'RETAINED'`
- **event_log**, **log de eventos** → the Rental Transact event stream (`datalake_rental_transact_clean.event_log`), one row per event; carries the numeric `id_rent_flow`, `actor_role`, `cancellation_reason`, and event `type`. Advance-payment events link to their sinal via `event_log.id_event_domain = advance_payment.uuid_advance_payment`
- **ADVANCE_PAYMENT stage** → the sinal-lifecycle events in `dim_rent_event_type` (`APC` created, `APP` pending, `APPR` processing, `APPD` paid, `APF` finished, `APCL` cancelled, `APPRF` processing refund, `APRF` refunded, `APCB` chargeback, `APRT` retained)

## Tables

> **Grain matters.** `fact_listing_rent_flows` is **event-grain** (multiple rows per rent flow — one per event) and exposes stage anchors **only as `sk_*_date` integers** (`yyyyMMdd`, `-1` = missing), not `ts_*`. `fact_rent_flows` is **one row per rent flow** with `nbr_*` counts and real `ts_first_*`/`ts_last_*` timestamps. `fact_rent_demand_events` is **one row per event** with a true `ts_event`. Pick the grain that matches the question.

| You need... | Use this table |
|-------------|----------------|
| Event-native funnel volume & conversion (VB/VC/OS/OA/ES/EP/DS/CA/CC/CS) | `dw_rent.fact_rent_demand_events` (`fde`) — one row per event; `ts_event`, partitioned by `year`/`month`/`day`. JOIN `dw_rent.dim_rent_event_type` (`det`) on `sk_event_type` for `abbreviation` / `event_name` / `stage`. |
| Event type catalog (abbreviations & stages) | `dw_rent.dim_rent_event_type` (`det`) — `VB`, `VC`, `OS`, `OA`, `ES`, `EP`, `DS`, `CA`, `CC`, `CS`, plus the `ADVANCE_PAYMENT` stage (`APC`, `APP`, `APPR`, `APPD`, `APF`, `APCL`, `APPRF`, `APRF`, `APCB`, `APRT`). `stage` ∈ `BOOKING`, `OFFER`, `PROPOSAL`, `CONTRACT`, `ADVANCE_PAYMENT`, ... |
| Advance payment (sinal) attributes & lifecycle | `datalake_rental_transact_clean.advance_payment` (`ap`) — one row per advance payment, key `uuid_advance_payment`. `status`, `rejection_reason`, `payment_amount`, `payment_percentage`, `id_house_external` (→ EBDB `house.id`), `id_tenant_external` / `id_owner_external` (→ Person `user.id`), `uuid_offer` (= rent-flow UUID), `ts_created`, `ts_expires`, `ts_cancelled`. |
| Sinal events + the numeric rent flow / actor / cancellation reason | `datalake_rental_transact_clean.event_log` (`el`) — one row per Rental Transact event; `id_rent_flow` (numeric), `id_event_domain`, `actor_role`, `type`, `cancellation_reason`, `ts_created`. Link a sinal to its rent flow via `el.id_event_domain = ap.uuid_advance_payment`. |
| Advance payment audit / status-transition history (SCD) | `datalake_rental_transact.advance_payment` (`ap_aud`) — Hibernate Envers revision history; `rev`, `ts_rev`, `revtype` (0=ADD/1=MOD/2=DEL), `mod_status` and other `mod_*` flags, plus `id_offer`. Use to time `status` transitions of a sinal (e.g. when it became `PAID` / `CANCELED`). |
| Stage-by-stage lead times / SLAs and drop reasons | `dw_rent.fact_listing_rent_flows` (`flrf`) — event-grain funnel fact. `funnel_step`, `funnel_step_drop_reason`, `days_*` (calendar days between stages), `working_min_credit_approved_to_contract_created/_signed`, `working_min_contract_created_to_contract_signed`. Stage anchors are `sk_*_date` (yyyyMMdd). |
| One row per rent flow with counts & timestamps | `dw_rent.fact_rent_flows` (`frf`) — grain `sk_rent_flow`. `nbr_offers_submitted`, `nbr_offers_approved`, `nbr_proposals_created`, `nbr_contracts_created`, `nbr_contracts_signed`, and `ts_first_*` / `ts_last_*` per stage. |
| Offer attributes (rent value, status, rejection reason) | `dw_rent.dim_offer` (`do`) — PK `sk_offer`; `status` (`EmNegociacao`/`Aprovada`/`Rejeitada`), `rejection_reason`, `type`, `is_instant_offer`, `dt_first_sent` (OS), `dt_analysis` (OA), `id_property`, `id_user`. |
| Proposal + credit-analysis attributes | `dw_rent.dim_proposal` (`dp`) — PK `sk_proposal`; `status`, `status_doc_tenant`, `result_credit_evaluation`, `status_sortinghat`, `guarantee`, `dti`, `monthly_income_declared`, and credit milestones `dt_first_credit_evaluation_init/_positive/_negative`, `dt_credit_last_approved`, `dt_tenant_first_document_sent`. |
| Contract status-transition audit metadata (who/when/why a revision happened) | `datalake_ebdb_clean.user_revision_entity` (`ure`) — one row per Hibernate Envers revision; `reason`, `id_user`, `ts_revision`. JOIN to the contract audit trail `contract_aud` (`ca`, owned by [`closing.md`](closing.md)) on `ca.rev = ure.id` to time `Minuta → PreAssinaturas` transitions and read the transition reason. |

> **Contract-grain tables are owned by [`closing.md`](closing.md).** `dim_contract` (status / `closing_status` / `ts_created` / `ts_draft_approved` / `ts_signature` / `ts_canceled` / `is_ongoing_contract`), `fact_contracts` (house / tenant / owner / proposal FKs at contract grain), and the `contract_aud` status-transition audit trail are **documented and owned in [`closing.md`](closing.md)**. FR Transact joins to them (via `sk_contract`, and `ca.rev = ure.id` for the audit) but does not own them — see Relationships → Closing and the Glossary for keys.

**Critical rules:**
- **Filter the event funnel on `det.abbreviation`, never on the raw `sk_event_type` integer.** The codes are assumed stable but **not chronological** — `1`=VB, `2`=VC, `3`=OS, `4`=OA, `5`=ES, `6`=EP, `7`=DS, `8`=CA, `9`=CS, `10`=CC (note `CC`=10 comes *after* `CS`=9), `11`=VR, `12`=VS, `13`=VRS, `14`=VD, `15`–`24`=the `ADVANCE_PAYMENT` events (`APC`,`APP`,`APPR`,`APPD`,`APCL`,`APPRF`,`APRF`,`APCB`,`APF`,`APRT`), and `-1`=unknown. You may see ad-hoc queries hardcoding `sk_event_type = 9` for CS, etc.; always JOIN `dim_rent_event_type` and filter on `abbreviation` instead so the logic survives code drift.
- **`fact_listing_rent_flows` has no `ts_*` funnel timestamps** — stage anchors are `sk_*_date` **integers in `yyyyMMdd`** with `-1` for missing. To get a date, JOIN the public `dim_date` dimension (`dw_public`) on `sk_*_date = dim_date.sk_date` (then use `date`, `year_month`, `month_start`); never subtract `sk_*_date` values directly.
- **Use the pre-computed lead times.** `working_min_*` (CA2CC, CA2CS, CC2CS) already exclude non-working hours; `days_*` are calendar days. Do not recompute from raw timestamps.
- **`funnel_step` value spelling:** the live data uses `offer_approved` (the metadata YAML has a typo `offer_aproved` — ignore it). Other values: `visit_booked`, `visit_completed`, `offer_submitted`, `document_sent`, `document_completed`, `credit_approved`, `contract_created`, `contract_signed`, plus `NULL` for flows with no resolved step.
- **`contract_aud` audit join:** `ca.rev = ure.id` — both are `INTEGER` in `datalake_ebdb_clean`, so a direct equality works (no cast needed). `ca.mod_status = true` captures any transition *into* the new `status`, not necessarily *from* a specific prior status; the `ure.reason` text disambiguates (e.g. reasons containing "Minuta" confirm a Minuta → PreAssinaturas transition).
- **`dim_contract` includes drafts, pre-signature, and cancelled rows** — one row per contract regardless of stage. Filter explicitly (`status` / `closing_status`) when you need only signed/active deals.
- **Advance payment (sinal) lives in `datalake_rental_transact*`, not `dw_rent`.** The numeric `id_rent_flow` is on `event_log`, not on `advance_payment` — bridge via `el.id_event_domain = ap.uuid_advance_payment`. To reach the rent flow without `event_log`, use `ap.uuid_offer` (the rent-flow UUID). `advance_payment` is keyed `uuid_advance_payment`; `event_log` is event-grain, so dedup to the latest event per `id_rent_flow` (ROW_NUMBER over `ts_created DESC`) when you only want the current state.
- **DataHub CI:** list concrete `schema.table` names only — never wildcards.

## Key Metrics

- Funnel volume per stage (`COUNT(DISTINCT fde.sk_rent_flow)` per `det.abbreviation` on `fact_rent_demand_events`)
- Stage conversion rates — OS→OA, OA→CA, CA→CC, CC→CS (ratios of the funnel volumes above)
- Contracts signed in a period (`COUNT(DISTINCT sk_rent_flow)` where `funnel_step = 'contract_signed'`, or `dim_contract.closing_status = 'ContratoAssinado'`)
- CA2CC / CA2CS lead time (`working_min_credit_approved_to_contract_created` / `_signed` on `fact_listing_rent_flows`, in working minutes)
- CC2CS lead time (`working_min_contract_created_to_contract_signed`) — closing SLA, shared with [`closing.md`](closing.md)
- OS→CS calendar lead time (`days_offer_submitted_to_contract_signed`)
- Drop volume by stage and reason (`funnel_step` + `funnel_step_drop_reason`)
- Credit approval rate (`dim_proposal.result_credit_evaluation` / `status_sortinghat` distribution)
- Minuta → PreAssinaturas transition mix (auto Offer Express vs CRM) from `contract_aud` + `user_revision_entity.reason`
- Offer rejection reasons distribution (`dim_offer.rejection_reason`); proposal rejection reasons (`dim_proposal.rejection_reason`)
- Advance payment (sinal) volume and status mix (`COUNT(*)` / `COUNT(DISTINCT uuid_advance_payment)` by `advance_payment.status`)
- Sinal paid / finished rate, refund rate, retained rate (shares of `status` ∈ `PAID`/`FINISHED` vs `REFUNDED`/`PROCESSING_REFUND` vs `RETAINED`)
- Sinal total / average ticket (`SUM` / `AVG` of `advance_payment.payment_amount`)
- Advance-payment funnel volume by stage event (`COUNT(DISTINCT fde.sk_rent_flow)` per `det.abbreviation` where `det.stage = 'ADVANCE_PAYMENT'`)

## Relationships with Other Entities

### Closing (sub-stage of FR Transact — N:1 to contract)

- The contract draft → sent → signed stages (CC → CS) are the **closing** journey. **`closing.md` owns the contract-grain tables** — `dim_contract` (status / `closing_status` / `ts_*`), `fact_contracts` (house / tenant / owner / proposal FKs), and the `contract_aud` status-transition audit trail. FR Transact joins to them via `sk_contract` (and `ca.rev = ure.id` for the audit), but `fact_listing_rent_flows` (the funnel/SLA fact, including `working_min_contract_created_to_contract_signed`) stays owned here. For signatories (`fact_contract_people`), legal representatives, and cancellation-before-signing detail, see [`closing.md`](closing.md).

### Offer → Proposal → Contract (the funnel spine)

- `fact_contracts.sk_proposal = dim_proposal.sk_proposal` (1:1 — a contract is born from one proposal; `sk_proposal = -1` means orphan)
- Proposal → offer: a proposal is an accepted offer; walk via `fact_rent_flows` (`sk_first_offer`/`sk_last_offer`, `sk_first_proposal`) or `fact_listing_rent_flows` (`sk_offer`, `sk_proposal`, `sk_contract` on the same row)
- `dim_offer` does **not** carry `sk_contract`; bridge through `fact_listing_rent_flows`/`fact_rent_flows`

### Advance Payment / Sinal

- A rent flow may have **zero or more** advance payments; each `advance_payment` row attaches to its rent flow via `ap.uuid_offer` (= rent-flow UUID).
- To get the **numeric** `id_rent_flow` (and the actor / cancellation context), join the event stream: `event_log.id_event_domain = advance_payment.uuid_advance_payment`.
- House and region: `advance_payment.id_house_external = datalake_ebdb_clean.house.id`, then `house.id_region = dw_public.dim_region.id` for `city` / `city_group`.
- The sinal milestones also surface in the rent-demand-events funnel: `dw_rent.dim_rent_event_type.stage = 'ADVANCE_PAYMENT'` (events `APC`…`APRT`) joined to `dw_rent.fact_rent_demand_events` on `sk_event_type`, keyed by `sk_rent_flow`.

### House and Listing (N:1 — many rent flows per house)

- `fact_contracts.sk_house` / `fact_listing_rent_flows.sk_house_listing`; see [`house_and_listing.md`](house_and_listing.md)

### Pricing (the offered rent vs the listed price)

- Offered rent lives in `dim_offer`; the listing/registered price history is in [`pricing.md`](pricing.md) (`dw_listing.dim_pricing`, `business_context = 'RENT'`)

### Termination & Closing (post-signature — out of scope)

- Once `dim_contract.status = 'Ativo'`, the contract leaves FR Transact. Terminations live in [`termination.md`](termination.md) (`dw_offboarding.fact_terminations` via `sk_contract`).

## Dos and Don'ts

**Do:**
- Use `dw_rent.fact_rent_demand_events` + `dim_rent_event_type` for **event-native funnel volume and conversion** (VB/VC/OS/OA/ES/EP/DS/CA/CC/CS) — filter on `year`/`month`/`day` partitions and `det.abbreviation`.
- Use `dw_rent.fact_listing_rent_flows` for **lead times** (`working_min_*`, `days_*`) and **drop-reason analysis** (`funnel_step` + `funnel_step_drop_reason`).
- JOIN `dw_public.dim_date` on `sk_*_date = sk_date` whenever you need a calendar date or month from a `fact_listing_rent_flows` / `fact_rent_flows` stage anchor.
- Filter `funnel_step = 'contract_signed'` (or `dim_contract.closing_status = 'ContratoAssinado'`) for signed-deal counts; reserve `dim_contract.status = 'Ativo'` for *currently active* contracts only.
- For status-transition timing/reasons, join `contract_aud` to `user_revision_entity` on `ca.rev = ure.id` and read `ure.reason`.
- Defer to [`closing.md`](closing.md) for signatory counts, legal representatives, and CC→CS closing specifics.
- For the **sinal (advance payment)**, read `datalake_rental_transact_clean.advance_payment` and bridge to the rent flow via `event_log.id_event_domain = advance_payment.uuid_advance_payment`; dedup `event_log` to the latest event per `id_rent_flow` (`ROW_NUMBER() … ORDER BY ts_created DESC`) for the current journey state.
- Use `dw_rent.fact_rent_demand_events` + `dim_rent_event_type` (`stage = 'ADVANCE_PAYMENT'`) when you want sinal milestones inside the **DW funnel** at `sk_rent_flow` grain.

**Don't:**
- Don't confuse the For-Rent sinal (`datalake_rental_transact_clean.advance_payment`, a reservation deposit) with the For-Sale "Sinal / Earnest Payment" (~6% of the sale price) in [`fs-transact.md`](fs-transact.md) / [`bank_reconciliation.md`](bank_reconciliation.md) — different product, different schema.
- Don't expect a numeric `id_rent_flow` on `advance_payment` — it only carries `uuid_offer` (the rent-flow UUID); the numeric key lives on `event_log`.
- Don't treat `RETAINED` as a refund — it means the sinal was cancelled but QuintoAndar **kept** the amount (no money returned to the payer).
- Don't count raw `event_log` rows as sinais — `event_log` is event-grain (many rows per rent flow); count `DISTINCT uuid_advance_payment` on `advance_payment` instead.
- Don't subtract `sk_*_date` columns to compute durations — they are `yyyyMMdd` integers, not dates, and `-1` means missing. Convert via `dim_date` or use the pre-computed `days_*` / `working_min_*`.
- Don't treat `fact_listing_rent_flows` as one row per rent flow — it is event-grain; counting raw rows inflates volume. Use `COUNT(DISTINCT sk_rent_flow)` or switch to `fact_rent_flows`.
- Don't use the metadata's `offer_aproved` spelling in a `funnel_step` filter — the data value is `offer_approved`.
- Don't count `dim_contract` rows as signed deals — drafts (`Minuta`), pre-signature (`PreAssinaturas`), and cancelled (`Cancelado`) rows are all present.
- Don't run a window `LAG(status)` over the full `contract_aud` table to find transitions — it is very slow. Filter `mod_status = true` plus a `ts_database_transaction` date range first (use `mod_status` as the transition proxy).
- Don't recompute CA2CS / CC2CS by hand — use the `working_min_*` columns (they already exclude non-working hours).
- Don't confuse `ts_canceled` (cancelled before signing) with `dt_annulment` (annulled after signing) — the former is pre-contract, the latter post-signature.

## Golden Queries

> Validated against Trino (`hive` catalog) on the For Rent pre-contract tables. `SELECT *` is avoided; adapt date filters to your window. Partition filters (`year`/`month`/`day` on `fact_rent_demand_events`) are required to avoid full scans.

### Query 1 — Pre-contract funnel volume by stage (event-native)

Monthly count of distinct rent flows reaching each funnel stage. The cleanest source for funnel volume and conversion.

```sql
SELECT
    dd.year_month,
    det.abbreviation,
    det.event_name,
    COUNT(DISTINCT fde.sk_rent_flow) AS rent_flows
FROM dw_rent.fact_rent_demand_events AS fde
INNER JOIN dw_rent.dim_rent_event_type AS det
    ON fde.sk_event_type = det.sk_event_type
INNER JOIN dw_public.dim_date AS dd
    ON fde.sk_event_date = dd.sk_date
WHERE det.abbreviation IN ('VB', 'VC', 'OS', 'OA', 'ES', 'EP', 'DS', 'CA', 'CC', 'CS')
  AND fde.year = 2026
  AND fde.month = 5
GROUP BY dd.year_month, det.abbreviation, det.event_name
ORDER BY COUNT(DISTINCT fde.sk_rent_flow) DESC
```

### Query 2 — Lead times for signed contracts by month

Distinct signed-flow volume plus working-minute SLAs (CA2CS, CC2CS) and OS→CS calendar days, anchored to the contract-signed month via `dim_date`. Signed flows are deduped to one row per `sk_rent_flow` first (the SLA columns are flow-level) so the count and averages stay on the same grain on event-grain `fact_listing_rent_flows`. Signed flows are deduped to one row per sk_rent_flow first (the SLA columns are flow-level) so the count and averages stay on the same grain on event-grain fact_listing_rent_flows.

```sql
WITH signed_flows AS (
    SELECT DISTINCT
        flrf.sk_rent_flow,
        flrf.sk_contract_signed_date,
        flrf.working_min_credit_approved_to_contract_signed,
        flrf.working_min_contract_created_to_contract_signed,
        flrf.days_offer_submitted_to_contract_signed
    FROM dw_rent.fact_listing_rent_flows AS flrf
    WHERE flrf.funnel_step = 'contract_signed'
)
SELECT
    dd.year_month,
    COUNT(DISTINCT sf.sk_rent_flow) AS contracts_signed,
    ROUND(AVG(sf.working_min_credit_approved_to_contract_signed) / 60.0, 1) AS avg_ca2cs_hours,
    ROUND(AVG(sf.working_min_contract_created_to_contract_signed) / 60.0, 1) AS avg_cc2cs_hours,
    ROUND(AVG(sf.days_offer_submitted_to_contract_signed), 1) AS avg_days_os2cs
FROM signed_flows AS sf
INNER JOIN dw_public.dim_date AS dd
    ON sf.sk_contract_signed_date = dd.sk_date
WHERE dd.year = 2026
  AND dd.month = 5
GROUP BY dd.year_month
ORDER BY dd.year_month
```

### Query 3 — Drop reasons by funnel step

Where rent flows stop and why — ranks `(funnel_step, funnel_step_drop_reason)` pairs.

```sql
SELECT
    flrf.funnel_step,
    flrf.funnel_step_drop_reason,
    COUNT(DISTINCT flrf.sk_rent_flow) AS rent_flows
FROM dw_rent.fact_listing_rent_flows AS flrf
WHERE flrf.funnel_step IS NOT NULL
  AND flrf.funnel_step_drop_reason IS NOT NULL
  AND flrf.funnel_step <> 'contract_signed'
GROUP BY flrf.funnel_step, flrf.funnel_step_drop_reason
ORDER BY COUNT(DISTINCT flrf.sk_rent_flow) DESC
LIMIT 25
```

### Query 4 — Minuta → PreAssinaturas transition reasons (audit trail)

Reasons behind the draft-approval transition (auto Offer Express vs CRM vs other), from the contract audit trail. `mod_status = true` proxies the transition; `user_revision_entity.reason` gives the cause.

```sql
WITH transitions AS (
    SELECT
        DATE(ca.ts_database_transaction) AS dt_transition,
        COALESCE(ure.reason, '(null)') AS reason
    FROM datalake_ebdb_clean.contract_aud AS ca
    LEFT JOIN datalake_ebdb_clean.user_revision_entity AS ure
        ON ca.rev = ure.id
    WHERE ca.status = 'PreAssinaturas'
      AND ca.mod_status = true
      AND ca.ts_database_transaction >= TIMESTAMP '2026-05-01 00:00:00'
      AND ca.ts_database_transaction < TIMESTAMP '2026-06-01 00:00:00'
)
SELECT
    reason,
    COUNT(*) AS transitions
FROM transitions
GROUP BY reason
ORDER BY COUNT(*) DESC
```

### Query 5 — Advance payment (sinal) status mix and ticket

Volume, share, and average ticket of advance payments by status — the quickest read on sinal health.

```sql
SELECT
    ap.status,
    COUNT(DISTINCT ap.uuid_advance_payment) AS advance_payments,
    ROUND(AVG(ap.payment_amount), 2) AS avg_amount,
    ROUND(SUM(ap.payment_amount), 2) AS total_amount
FROM datalake_rental_transact_clean.advance_payment AS ap
WHERE ap.ts_created >= TIMESTAMP '2026-05-01 00:00:00'
  AND ap.ts_created < TIMESTAMP '2026-06-01 00:00:00'
GROUP BY ap.status
ORDER BY COUNT(DISTINCT ap.uuid_advance_payment) DESC
```

### Query 6 — Sinal journey snapshot (current event state + house/region)

For each advance payment, the latest event of its rent flow plus house city and region — the pattern for tracking the sinal product end to end. `event_log` is deduped to the most recent event per `id_rent_flow`.

```sql
WITH filtered_signals AS (
    SELECT DISTINCT
        ap.uuid_advance_payment,
        ap.status AS status_sinal,
        ap.payment_amount,
        ap.id_house_external,
        ap.uuid_offer,
        ap.rejection_reason,
        el.id_rent_flow
    FROM datalake_rental_transact_clean.advance_payment AS ap
    INNER JOIN datalake_rental_transact_clean.event_log AS el
        ON ap.uuid_advance_payment = el.id_event_domain
    WHERE ap.ts_created >= TIMESTAMP '2026-05-01 00:00:00'
      AND el.ts_created >= TIMESTAMP '2026-05-01 00:00:00'
),
last_flow_state AS (
    SELECT
        ranked.id_rent_flow,
        ranked.last_event_type,
        ranked.ts_last_event,
        ranked.actor_role,
        ranked.cancellation_reason
    FROM (
        SELECT
            el.id_rent_flow,
            el.type AS last_event_type,
            el.ts_created AS ts_last_event,
            el.actor_role,
            el.cancellation_reason,
            ROW_NUMBER() OVER (PARTITION BY el.id_rent_flow ORDER BY el.ts_created DESC) AS rni
        FROM datalake_rental_transact_clean.event_log AS el
        INNER JOIN filtered_signals AS fs
            ON el.id_rent_flow = fs.id_rent_flow
        WHERE el.ts_created >= TIMESTAMP '2026-05-01 00:00:00'
    ) AS ranked
    WHERE ranked.rni = 1
)
SELECT
    fs.uuid_advance_payment,
    fs.status_sinal,
    fs.payment_amount,
    fs.id_rent_flow,
    h.city,
    reg.city_group,
    lfs.last_event_type,
    lfs.actor_role,
    lfs.cancellation_reason
FROM filtered_signals AS fs
LEFT JOIN last_flow_state AS lfs
    ON fs.id_rent_flow = lfs.id_rent_flow
LEFT JOIN datalake_ebdb_clean.house AS h
    ON fs.id_house_external = h.id
LEFT JOIN dw_public.dim_region AS reg
    ON h.id_region = reg.id
```

### Query 7 — Advance payment funnel volume (DW-native)

Sinal milestones inside the rent-demand-events funnel, at `sk_rent_flow` grain. Use this when you want the sinal alongside the other funnel stages.

```sql
SELECT
    det.abbreviation,
    det.event_name,
    COUNT(DISTINCT fde.sk_rent_flow) AS rent_flows
FROM dw_rent.fact_rent_demand_events AS fde
INNER JOIN dw_rent.dim_rent_event_type AS det
    ON fde.sk_event_type = det.sk_event_type
WHERE det.stage = 'ADVANCE_PAYMENT'
  AND fde.year = 2026
  AND fde.month = 5
GROUP BY det.abbreviation, det.event_name
ORDER BY COUNT(DISTINCT fde.sk_rent_flow) DESC
```

### Query 8 — Coincident (in-period) funnel conversion rates

Stage-to-stage conversion rates computed as **in-period (coincident) ratios** — each numerator and denominator is counted within the same month bucket, **not** cohort-tracked (it does not follow the *same* rent flows from VB through CS). This is the pattern behind pivot-table funnel summaries that read like VB2VC, VC2OS, OS2OA, OA2CA, CA2CS (adjacent) plus OS2CS, OA2CS, VB2OS (cross-stage). Pairs with Query 1 (the volume side).

> **Coincident vs cohort — read before using.** Because each stage is counted independently in the period, a ratio can exceed 100% (e.g. more contracts signed this month than offers submitted this month, when the signed flows submitted their offer in a prior month). Use these for steady-state operational dashboards; for true funnel efficiency of a fixed set of flows, build a cohort conversion instead (track one `sk_rent_flow` set across stages). `NULLIF(..., 0)` guards against divide-by-zero on empty stages.

```sql
WITH stage_volume AS (
    SELECT
        dd.year_month,
        COUNT(DISTINCT fde.sk_rent_flow) FILTER (WHERE det.abbreviation = 'VB') AS vb,
        COUNT(DISTINCT fde.sk_rent_flow) FILTER (WHERE det.abbreviation = 'VC') AS vc,
        COUNT(DISTINCT fde.sk_rent_flow) FILTER (WHERE det.abbreviation = 'OS') AS os,
        COUNT(DISTINCT fde.sk_rent_flow) FILTER (WHERE det.abbreviation = 'OA') AS oa,
        COUNT(DISTINCT fde.sk_rent_flow) FILTER (WHERE det.abbreviation = 'CA') AS ca,
        COUNT(DISTINCT fde.sk_rent_flow) FILTER (WHERE det.abbreviation = 'CS') AS cs
    FROM dw_rent.fact_rent_demand_events AS fde
    INNER JOIN dw_rent.dim_rent_event_type AS det
        ON fde.sk_event_type = det.sk_event_type
    INNER JOIN dw_public.dim_date AS dd
        ON fde.sk_event_date = dd.sk_date
    WHERE fde.year = 2026
      AND fde.month = 5
    GROUP BY dd.year_month
)
SELECT
    year_month,
    vb, vc, os, oa, ca, cs,
    ROUND(100.0 * vc / CAST(NULLIF(vb, 0) AS DOUBLE), 1) AS vb2vc_pct,
    ROUND(100.0 * os / CAST(NULLIF(vc, 0) AS DOUBLE), 1) AS vc2os_pct,
    ROUND(100.0 * oa / CAST(NULLIF(os, 0) AS DOUBLE), 1) AS os2oa_pct,
    ROUND(100.0 * ca / CAST(NULLIF(oa, 0) AS DOUBLE), 1) AS oa2ca_pct,
    ROUND(100.0 * cs / CAST(NULLIF(ca, 0) AS DOUBLE), 1) AS ca2cs_pct,
    ROUND(100.0 * cs / CAST(NULLIF(os, 0) AS DOUBLE), 1) AS os2cs_pct,
    ROUND(100.0 * cs / CAST(NULLIF(oa, 0) AS DOUBLE), 1) AS oa2cs_pct,
    ROUND(100.0 * os / CAST(NULLIF(vb, 0) AS DOUBLE), 1) AS vb2os_pct
FROM stage_volume
ORDER BY year_month
```

> Grain note: this counts **distinct rent flows** per stage (the doc's convention). The source pivot this pattern came from counts **distinct events** (`sk_event`) instead — swap `COUNT(DISTINCT fde.sk_rent_flow)` for the event key if you need event-level volumes.

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
