# Condo Garantido (CG)

## Ownership

**Data Owner:**
- carolina.ellwanger@quintoandar.com.br

**Data Steward:**
- carolina.ellwanger@quintoandar.com.br

## Overview

**Condo Garantido (CG)** is a For Rent product that monitors condominium (condomínio) bills of
ongoing contracts via **DDA** (Débito Direto Autorizado) so QuintoAndar can detect and settle a
tenant's condo default **proactively**, before the landlord (LL / proprietário) has to report it.
This document defines the **two official metrics** used to steer the product, both derived from
the same contract-×-month monitoring base (see Golden Queries):

1. **% Adoption of CG within eligibility base** — penetration: of the contracts where DDA
   monitoring is technically possible (the *eligible* base), how many currently have CG active.
2. **% Payment Default Identified Automatically** — operational effectiveness: of the condo
   defaults observed in the base, what share fell on contracts with CG active (the reproducible
   proxy for "captured automatically" rather than reported manually by the LL).

These are **distinct** metrics and must never be conflated: adoption measures *product coverage*;
automatic identification measures *how much of the actual default volume the product caught*. A
contract can be CG-active (counts in adoption) yet still have a default that surfaces via a manual
LL report.

**Exists exclusively for For Rent — there is no equivalent product for FS or other products.**

## Related Business Entities

- Collections

## MBR

- Post Contract

## Glossary and Synonyms

- **Condo Garantido**, **CG**, **condomínio garantido**, **monitoramento de condomínio**, **condo monitoring** → this product / metric family
- **DDA**, **Débito Direto Autorizado**, **monitoramento DDA** → the bank-authorization mechanism CG uses to read condo bills
- **% Adoption of CG within eligibility base**, **adoção do CG**, **% adoção CG**, **penetração do CG**, **cobertura do CG** → Metric 1
- **% Payment Default Identified Automatically**, **% identificação automática**, **% inadimplência identificada automaticamente**, **identificação proativa de inadimplência** → Metric 2
- **base elegível**, **eligible base**, **contratos elegíveis para CG** → the denominator of Metric 1 (`is_eligible`)
- **alto risco / baixo risco**, **high-risk / low-risk segment**, **delinquent base** → risk segmentation by condo-default history (`has_nprs_l12m`); "delinquent base" specifically refers to the high-risk segment
- **NPR / NPRS** (Non Payment Report) → strictly, a report opened about a default. In the current base, `nprs_current_month` counts **every** condo-payment invoice (`'condominium 5A paid'` + `account_type = 'tenant'`) in the month, regardless of whether it originated from an NPR or from DDA monitoring — so treat `nprs_current_month` as "condo-default invoices in the month", not literally "reports"

## Scope

**Included**: For Rent ongoing contracts, **Brazil** (`country_code <> 'MX'`), contracts that are
active or already ended (`status IN ('Ativo', 'Finalizado')`), excluding `type = 'DealOnly'`,
observed on a **monthly grain** over a rolling ~12-month window (`DATE_ADD('MONTH', -11, DATE_TRUNC('MONTH', CURRENT_DATE))`
onward). Each contract contributes one row per month it was live.

**Eligible universe (Metric 1 denominator)** — the subset of ongoing contracts where DDA
monitoring is technically possible. Business rationale: DDA regulation requires that the CPF
authorizing the monitoring be the LL's own and that the LL have app access to authorize it. The
**reproducible `is_eligible` flag** in the base approximates this with:

- at least one non-null owner user on the contract (LL has an app/user account), **and**
- at least one owner that is **not** merely a legal representative, **and**
- the contract has condo (`condo > 0`), **and**
- the contract has already started (`dt_start < CURRENT_DATE`).

**Excluded (from the eligible base)**: contracts with only legal representatives as owner,
contracts with no owner user (no app access), and contracts without condo. Structural DDA
restrictions (condo bill registered under a third party's CPF — PP Multi, inherited/co-owned
property) leave a contract inelegible by regulation, not by product failure. This is a structural
ceiling on adoption that product improvements cannot overcome.

**Excluded (from Metric 2)**: defaults of other expense types (rent, IPTU, utilities) — Metric 2
counts only condo-default invoices (`'condominium 5A paid'` + `account_type = 'tenant'`).

## Calculation

Both metrics are computed from the contract-×-month monitoring base (Golden Query 1). The base
exposes, per contract per month, the booleans and counters the formulas need: `is_eligible`,
`is_activated`, `has_nprs_l12m` (risk segment), and `nprs_current_month` (condo defaults in the
month).

### Metric 1 — % Adoption of CG within eligibility base

```
% Adoption = COUNT(DISTINCT sk_contract WHERE is_activated = TRUE)
           / COUNT(DISTINCT sk_contract WHERE is_eligible  = TRUE)
```

- **Numerator**: distinct contracts with CG **currently active** in the period (`is_activated`),
  not merely ever-activated. `is_activated` is derived from `invoice_user_issuer` monitoring
  windows (`request_status = 'ACTIVE'`, plus `CANCELED` windows closed at `ts_updated`), so a
  contract only counts in a month while monitoring was actually on — activation churn from
  cancellations is respected.
- **Denominator**: distinct contracts in the eligible base (`is_eligible`, defined in Scope).
- **Report the delinquent base separately** (contracts with condo-default history,
  `has_nprs_l12m = TRUE`) — adoption there differs substantially from the top-line eligible base.
  This risk cut applies to **adoption only**, and the delinquent-base denominator differs from the
  top-line one (see the Nuances note "Delinquent-base adoption uses a different denominator").

> In the base, `is_activated` is derived **only** from the `invoice_user_issuer` monitoring
> windows and carries no eligibility precondition, while `is_eligible` is the separate derived
> owner/condo/start-date rule. The official formula counts every activated contract in the
> numerator **without** intersecting `is_eligible`, so activation is not, by construction, a strict
> subset of the eligible base. Keep the formula as written; if you need adoption to be a clean
> subset (numerator ⊆ denominator), add `is_eligible = TRUE` to the numerator and state that you
> changed the definition.

### Metric 2 — % Payment Default Identified Automatically

```
% Identified Automatically = SUM(nprs_current_month WHERE is_activated = TRUE)
                           / SUM(nprs_current_month)
```

- **Numerator**: condo defaults (`nprs_current_month`) that occurred in the month on contracts
  with CG active — the reproducible proxy for "identified automatically".
- **Denominator**: all condo defaults observed in the base for the month (CG-active or not).
- This is a **proxy**, not a direct read of payment origin. It equates "default happened on a
  CG-active contract" with "captured automatically". It does **not** currently distinguish, at the
  invoice level, a default the DDA algorithm actually matched from one that still needed a manual
  LL report on an otherwise-monitored contract. There is no invoice-level origin field in the base
  to split automatic vs. manual, so `is_activated` is the proxy — do not assume a `payment_source` /
  `settlement_origin` column exists.
- **Do not segment this metric by risk.** It is already confined to the delinquent base by
  construction: it counts paid condo defaults, and any contract with at least one default is
  "high-risk" (`has_nprs_l12m = TRUE`). A high/low-risk split here is meaningless — there is no
  low-risk volume to compare against.

> **Do not read Metric 2 from a partial current month.** Condo bills come due throughout the month
> and are only internalized by the automatic flows **after** their due date, so early in a month a
> large share of not-yet-due bills is still missing from the denominator. This biases the ratio and
> makes the current-month figure unreliable until the month has (largely) closed. Only interpret
> Metric 2 on completed months; treat the running current month as incomplete.

### Canonical Filter

The condo-default event that feeds `nprs_current_month` (and the high-risk history) is identified
on `datalake_accounting_funnel.invoice_all` with **both** predicates:

```sql
bill_item    = 'condominium 5A paid'
AND account_type = 'tenant'
```

**Warning**: filtering on `bill_item = 'condominium 5A paid'` **without** `account_type = 'tenant'`
pulls in other account types and inflates the default counts. Both predicates are mandatory. For
the high-risk history flag, the same filter is applied cumulatively from `DATE '2025-01-01'`.

### Nuances

Concept → column in the monitoring base (Golden Query 1):

| Concept | Base column | Source |
| :---- | :---- | :---- |
| Eligible base (Metric 1 denominator) | `is_eligible` | derived: owner-user + not-only-legal-rep + `condo > 0` + started |
| Product-computed eligibility (alternative) | `is_computed_as_eligible` | `datalake_rental_management_clean.condo_monitoring_eligibility` |
| CG currently active in the month | `is_activated` | `datalake_rental_management_clean.invoice_user_issuer` |
| Condo defaults in the reference month | `nprs_current_month` | `datalake_accounting_funnel.invoice_all` (canonical filter) |
| Has condo-default history since 2025 (risk segment) | `has_nprs_l12m` | `invoice_all`, cumulative from 2025-01-01 |
| PP Multi classification | `pp_multi_classification` | `datalake_pp_multi.pp_multi_classification_history` |
| Owner property-count band | `property_range` | `dw_rent.fact_house_listings` / `dim_house_listing` |

**Two eligibility signals — do not confuse them.** `is_eligible` is the reproducible flag the
official Metric 1 uses. `is_computed_as_eligible` comes from the product's own eligibility table
(`condo_monitoring_eligibility`) and encodes the fuller DDA rules (e.g. CPF match). They can
disagree; use `is_eligible` for the official number and `is_computed_as_eligible` only for
reconciliation / auxiliary analysis (state which you used).

**Delinquent-base breakdown (adoption only).** The one meaningful risk cut is the **delinquent
base** — contracts with condo-default history (`has_nprs_l12m = TRUE`). Report **adoption
(Metric 1)** for the delinquent base separately, since it differs substantially from the top-line
eligible base. This breakdown does **not** apply to **Metric 2**: that metric is already confined
to the delinquent base by construction (it only counts paid condo defaults), so a high/low-risk
split is meaningless there.

**Delinquent-base adoption uses a different denominator.** For the top-line adoption, the
denominator is the eligible base (`is_eligible = TRUE`). For the delinquent-base cut, the official
dashboard divides by the **whole** delinquent base (`has_nprs_l12m = TRUE`), **without** requiring
`is_eligible` — same numerator, different denominator. Computing it as `activated / (is_eligible ∩
delinquent)` gives a materially higher (wrong) number that does not match the dashboard. Always use
the whole delinquent base as the denominator for the delinquent-base adoption number (see Golden
Query 2).

The denominators are not static (contracts start and end), so always compare within the same period
and re-derive the numbers rather than reusing a prior figure.

**Currently-active vs ever-activated.** Metric 1's numerator uses the per-month active window, so
contract cancellations and CG deactivations correctly drop out. Do not substitute a "contract was
ever activated" count.

**Re-listing gap.** When a CG-active contract ends and the same property is re-let, the new
contract does not inherit CG automatically (manual reactivation) — an H2 '26 initiative addresses
this. This depresses adoption on churned properties.

**PP Multi.** Adoption is markedly lower in PP Multi due to more frequent divergent-CPF cases
(condo bill registered under a third party). Segment on `pp_multi_classification` to isolate it.

## Dos and Don'ts

**Do:**

- For **adoption (Metric 1)**, report the **delinquent base** (`has_nprs_l12m = TRUE`) separately —
  adoption there differs substantially. For that cut, divide by the **whole** delinquent base
  (not `is_eligible ∩ delinquent`), to match the official dashboard.
- Use `is_eligible` as Metric 1's **top-line** denominator — the eligible base, never the total ongoing base.
- Use the **per-month active** flag (`is_activated`) for the numerator, not "ever activated".
- Apply **both** canonical-filter predicates (`bill_item` **and** `account_type`) for any condo-default count.
- Monitor the two metrics together: if adoption rises but automatic identification does not, the
  gap is in the match algorithm, not activation.
- Re-derive percentages within the same period; the eligible base and default volume both move.

**Don't:**

- Don't use total ongoing contracts as Metric 1's denominator — it understates real penetration in the target base.
- Don't conflate adoption (Metric 1) with automatic identification (Metric 2) — they answer different questions.
- Don't treat Metric 2 as a direct read of payment origin — it is a proxy based on `is_activated`;
  do not invent a `payment_source` / `settlement_origin` split that is not in the base.
- Don't filter condo defaults on `bill_item` alone (missing `account_type = 'tenant'`).
- Don't compare baselines across periods without checking whether the eligible base changed size.
- Don't segment Metric 2 by risk (high/low) — it lives entirely in the delinquent base by construction.
- Don't draw conclusions about Metric 2 from a partial current month — bills that have not yet come
  due are missing from the denominator until they are internalized after their due date; use completed months.
- Don't compute delinquent-base adoption as `activated / (is_eligible ∩ delinquent)` — the official
  denominator is the **whole** delinquent base (`has_nprs_l12m = TRUE`).
- Don't read low adoption outside the delinquent base as a product failure — letting that segment grow organically is the strategy.

## Golden Queries

Trino dialect. **Query 1** builds the shared contract-×-month monitoring base — the single
foundation for both official metrics **and** for auxiliary variations. **Query 2** wraps that base
and produces the official metrics by month: top-line adoption, delinquent-base adoption, and
automatic identification.

### Query 1 — Condo Garantido monitoring base (one row per contract × month)

Selecting from this base gives the flexible foundation for auxiliary analyses (swap the
eligibility signal, segment by `pp_multi_classification` / `property_range` / `city_group` /
`rental_administrator`, restrict Metric 2 to the eligible base, etc.).

```sql
WITH contract_month AS (
    WITH aux_contract_info AS (
        SELECT DISTINCT
            fhl.sk_contract,
            fhl.sk_house_listing / 1000 AS id_house,
            fhl.sk_owner,
            dr.city_group
        FROM dw_rent.fact_house_listings AS fhl
        JOIN dw_public.dim_region AS dr
            ON fhl.sk_region = dr.sk_region
    )
    SELECT DISTINCT
        dd.month_start AS month,
        dc.sk_contract,
        dc.status,
        ci.id_house,
        ci.sk_owner,
        ci.city_group,
        dc.condo,
        dc.condo_payer,
        dc.dt_start,
        dc.pp_multi_classification,
        dc.rental_administrator
    FROM dw_rent.dim_contract AS dc
    JOIN aux_contract_info AS ci
        ON dc.sk_contract = ci.sk_contract
    JOIN dw_public.dim_date AS dd
        ON dd.date BETWEEN DATE(COALESCE(COALESCE(dc.ts_signature, dc.dt_start), dc.dt_entrance)) AND COALESCE(dc.dt_annulment, CURRENT_DATE)
    LEFT JOIN datalake_pp_multi.pp_multi_classification_history AS ppm
        ON ppm.id_owner = ci.sk_owner
        AND ppm.pp_multi_classification = 'ACTIVE'
        AND dd.date = CAST(CAST(ppm.year AS VARCHAR) || '-' || LPAD(CAST(ppm.month AS VARCHAR), 2, '0') || '-' || LPAD(CAST(ppm.day AS VARCHAR), 2, '0') AS DATE)
    WHERE dd.date <= CURRENT_DATE
        AND dc.status IN ('Ativo', 'Finalizado')
        AND dc.type <> 'DealOnly'
        AND dc.country_code <> 'MX'
        AND dd.date = dd.month_start
        AND dd.date >= DATE_ADD('MONTH', -11, DATE_TRUNC('MONTH', CURRENT_DATE))
),
id_null AS (
    SELECT
        id_contract,
        COUNT(CASE WHEN id_user IS NOT NULL AND type = 'Proprietario' THEN id_contract END) AS not_null_users
    FROM datalake_ebdb_clean.contract_person
    GROUP BY 1
),
legal_representative AS (
    SELECT
        id_contract,
        COUNT(CASE WHEN type = 'Proprietario' AND is_with_representative = FALSE THEN id_contract END) AS owners_not_legal_representatives
    FROM datalake_ebdb_clean.contract_person
    GROUP BY 1
),
contract_termination_status_month AS (
    SELECT DISTINCT
        dd.month_start AS month,
        ft.sk_contract
    FROM dw_offboarding.fact_terminations AS ft
    JOIN dw_offboarding.dim_termination AS dt
        ON ft.sk_termination = dt.sk_termination
    JOIN dw_public.dim_date AS dd
        ON dd.date BETWEEN DATE(ft.ts_termination_request) AND COALESCE(DATE(ft.ts_termination_finished), CURRENT_DATE)
    WHERE dd.date <= CURRENT_DATE
        AND dt.status <> 'CANCELED'
        AND dd.date >= DATE_ADD('MONTH', -11, DATE_TRUNC('MONTH', CURRENT_DATE))
),
owner_properties AS (
    WITH raw AS (
        SELECT DISTINCT
            fhl.sk_owner,
            dhl.id_house,
            DATE(DATE_TRUNC('MONTH', dhl.ts_house_first_publication)) AS first_house_publication_month
        FROM dw_rent.fact_house_listings AS fhl
        LEFT JOIN dw_rent.dim_house_listing AS dhl
            ON fhl.sk_house_listing = dhl.sk_house_listing
        WHERE dhl.ts_house_first_publication IS NOT NULL
    )
    SELECT
        cm.month,
        cm.sk_owner,
        COUNT(DISTINCT r.id_house) AS properties_up_to_month
    FROM contract_month AS cm
    LEFT JOIN raw AS r
        ON cm.sk_owner = r.sk_owner
        AND r.first_house_publication_month <= cm.month
    GROUP BY 1, 2
),
activations_status_month AS (
    WITH aux_dates AS (
        SELECT
            fs1.id_contract AS sk_contract,
            DATE(fs1.dt_monitoring_started) AS activation_dt,
            CAST(NULL AS DATE) AS deactivation_dt
        FROM datalake_rental_management_clean.invoice_user_issuer AS fs1
        WHERE fs1.request_status = 'ACTIVE'
        UNION ALL
        SELECT
            fs2.id_contract AS sk_contract,
            DATE(fs2.dt_monitoring_started) AS activation_dt,
            DATE(fs2.ts_updated) AS deactivation_dt
        FROM datalake_rental_management_clean.invoice_user_issuer AS fs2
        WHERE fs2.request_status = 'CANCELED'
    )
    SELECT DISTINCT
        dd.month_start AS month,
        ae.sk_contract
    FROM aux_dates AS ae
    JOIN dw_public.dim_date AS dd
        ON dd.date BETWEEN ae.activation_dt AND COALESCE(ae.deactivation_dt, CURRENT_DATE)
    WHERE dd.date <= CURRENT_DATE
        AND dd.date >= DATE_ADD('MONTH', -11, DATE_TRUNC('MONTH', CURRENT_DATE))
),
has_condo_default_history AS (
    SELECT
        i.sk_contract,
        dd.month_start AS reference_month,
        COUNT_IF(DATE_TRUNC('MONTH', i.entry_created_date) = dd.month_start) AS nprs_count_month,
        TRUE AS has_default_history
    FROM datalake_accounting_funnel.invoice_all AS i
    CROSS JOIN (
        SELECT DISTINCT month_start
        FROM dw_public.dim_date
        WHERE date >= DATE '2025-01-01'
            AND date <= CURRENT_DATE
    ) AS dd
    WHERE i.bill_item = 'condominium 5A paid'
        AND i.account_type = 'tenant'
        AND i.entry_created_date >= DATE '2025-01-01'
        AND i.entry_created_date <= (dd.month_start + INTERVAL '1' MONTH - INTERVAL '1' DAY)
    GROUP BY 1, 2
),
base_tickets AS (
    WITH raw AS (
        SELECT
            ft.sk_ticket,
            ft.sk_user,
            ft.sk_contract,
            DATE(DATE_TRUNC('MONTH', ft.ts_solved)) AS month,
            1 AS pure_tickets,
            ft.total_tickets_proportional,
            dt.theme AS macro_taxonomy
        FROM dw_customer_support.fact_tickets AS ft
        LEFT JOIN dw_customer_support.dim_taxonomy AS dt
            ON ft.sk_taxonomy = dt.sk_taxonomy
        WHERE ft.is_ticket_rate = TRUE
            AND dt.theme IN ('rental_ongoing_condo')
            AND dt.customer_type_tag IN ('rent_owner', 'rent_owner_portability', 'proprietário_de_aluguel')
    )
    SELECT
        cm.month,
        cm.sk_contract,
        SUM(r.pure_tickets) AS pure_tickets,
        SUM(r.total_tickets_proportional) AS total_tickets_proportional
    FROM contract_month AS cm
    LEFT JOIN raw AS r
        ON cm.sk_contract = r.sk_contract
        AND cm.month = r.month
    GROUP BY 1, 2
),
final AS (
    SELECT
        cm.month,
        cm.sk_contract,
        cm.status,
        cm.id_house,
        cm.sk_owner,
        cm.city_group,
        cm.dt_start,
        IF(n.not_null_users = 0, TRUE, FALSE) AS has_only_null_users,
        IF(lr.owners_not_legal_representatives = 0, TRUE, FALSE) AS has_legal_representatives_only,
        IF(ctm.sk_contract IS NOT NULL, TRUE, FALSE) AS is_in_a_termination,
        IF(cm.condo_payer = 'Inquilino', TRUE, FALSE) AS iq_is_the_condo_payer,
        IF(cm.condo > 0, TRUE, FALSE) AS has_condo,
        CASE
            WHEN op.properties_up_to_month = 1 THEN '1_property'
            WHEN op.properties_up_to_month BETWEEN 2 AND 5 THEN '2_to_5_properties'
            WHEN op.properties_up_to_month BETWEEN 6 AND 10 THEN '6_to_10_properties'
            WHEN op.properties_up_to_month BETWEEN 11 AND 30 THEN '11_to_30_properties'
            WHEN op.properties_up_to_month > 30 THEN '30+_properties'
            ELSE NULL
        END AS property_range,
        IF(
            n.not_null_users > 0
            AND lr.owners_not_legal_representatives > 0
            AND cm.condo > 0
            AND cm.dt_start < CURRENT_DATE,
            TRUE,
            FALSE
        ) AS is_eligible,
        IF(cme.id_contract IS NOT NULL, TRUE, FALSE) AS is_computed_as_eligible,
        IF(asm.sk_contract IS NOT NULL, TRUE, FALSE) AS is_activated,
        COALESCE(h.has_default_history, FALSE) AS has_nprs_l12m,
        COALESCE(h.nprs_count_month, 0) AS nprs_current_month,
        COALESCE(bt.total_tickets_proportional, 0) AS ongoing_condo_proportional_tickets,
        cm.pp_multi_classification,
        cm.rental_administrator
    FROM contract_month AS cm
    LEFT JOIN id_null AS n
        ON cm.sk_contract = n.id_contract
    LEFT JOIN legal_representative AS lr
        ON cm.sk_contract = lr.id_contract
    LEFT JOIN contract_termination_status_month AS ctm
        ON cm.sk_contract = ctm.sk_contract
        AND cm.month = ctm.month
    LEFT JOIN owner_properties AS op
        ON cm.sk_owner = op.sk_owner
        AND cm.month = op.month
    LEFT JOIN activations_status_month AS asm
        ON cm.sk_contract = asm.sk_contract
        AND cm.month = asm.month
    LEFT JOIN has_condo_default_history AS h
        ON cm.sk_contract = h.sk_contract
        AND cm.month = h.reference_month
    LEFT JOIN base_tickets AS bt
        ON cm.sk_contract = bt.sk_contract
        AND cm.month = bt.month
    LEFT JOIN datalake_rental_management_clean.condo_monitoring_eligibility AS cme
        ON cm.sk_contract = cme.id_contract
        AND cme.eligibility = TRUE
)
SELECT
    month,
    sk_contract,
    status,
    id_house,
    sk_owner,
    city_group,
    dt_start,
    has_only_null_users,
    has_legal_representatives_only,
    is_in_a_termination,
    iq_is_the_condo_payer,
    has_condo,
    property_range,
    is_eligible,
    is_computed_as_eligible,
    is_activated,
    has_nprs_l12m,
    nprs_current_month,
    ongoing_condo_proportional_tickets,
    pp_multi_classification,
    rental_administrator
FROM final
```

### Query 2 — Official metrics by month

Wrap Query 1 as the CTE `condo_monitoring_base` (its full body above), then aggregate to one row
per month. There is **no** high/low risk split: adoption's only meaningful risk cut is the
delinquent base, and Metric 2 is already confined to it. Each metric is a single explicit
conditional aggregation — do **not** use `GROUPING SETS`/`GROUP BY` on the risk flag, because that
would silently restrict the delinquent-base denominator to `is_eligible ∩ delinquent` instead of
the whole delinquent base.

```sql
WITH condo_monitoring_base AS (
    -- full body of Query 1 (one row per contract × month)
    -- ... see Query 1 ...
    SELECT
        month,
        sk_contract,
        is_eligible,
        is_activated,
        has_nprs_l12m,
        nprs_current_month
    FROM final
)
SELECT
    month,
    -- Metric 1 (top-line): % Adoption of CG within the eligible base
    CAST(COUNT(DISTINCT CASE WHEN is_activated = TRUE THEN sk_contract END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT CASE WHEN is_eligible = TRUE THEN sk_contract END), 0) AS pct_adoption_cg,
    -- Metric 1 (delinquent base): denominator is the WHOLE delinquent base (has_nprs_l12m = TRUE),
    -- NOT is_eligible ∩ delinquent — this matches the official dashboard. Do not add is_eligible here.
    CAST(COUNT(DISTINCT CASE WHEN is_activated = TRUE AND has_nprs_l12m = TRUE THEN sk_contract END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT CASE WHEN has_nprs_l12m = TRUE THEN sk_contract END), 0) AS pct_adoption_cg_delinquent_base,
    -- Metric 2: % Payment Default Identified Automatically (not segmented by risk — see note above)
    CAST(SUM(CASE WHEN is_activated = TRUE THEN nprs_current_month END) AS DOUBLE)
        / NULLIF(SUM(nprs_current_month), 0) AS pct_default_identified_auto
FROM condo_monitoring_base
GROUP BY month
ORDER BY month
```

### Auxiliary variations

All of the following swap only the aggregation layer over the same `condo_monitoring_base`:

- **Eligibility source swap** — replace `is_eligible` with `is_computed_as_eligible` in Metric 1's
  denominator to reconcile against the product's own eligibility table.
- **Eligible-only Metric 2** — restrict automatic identification to the eligible universe by moving
  the eligibility predicate **inside** Metric 2's conditional aggregation, not into a `WHERE` on the
  base. A `WHERE is_eligible = TRUE` on `condo_monitoring_base` filters rows before aggregation, so
  in the combined Query 2 it would also drop activated-but-ineligible contracts from Metric 1's
  numerator (which the official formula keeps) and silently lower adoption. Keep it self-contained:

  ```sql
  CAST(SUM(CASE WHEN is_activated = TRUE AND is_eligible = TRUE THEN nprs_current_month END) AS DOUBLE)
      / NULLIF(SUM(CASE WHEN is_eligible = TRUE THEN nprs_current_month END), 0) AS pct_default_identified_auto_eligible
  ```

  Swap `is_eligible` for `is_computed_as_eligible` in both branches to reconcile against the
  product's own eligibility table. Only use a `WHERE is_eligible = TRUE` on the base for a
  **standalone Metric-2-only** query — never in the combined Query 2 that also computes Metric 1.
- **Extra segmentation** — add `pp_multi_classification`, `property_range`, `city_group`, or
  `rental_administrator` to the `SELECT` / `GROUP BY` (e.g. to see the lower PP Multi adoption).
- **Point-in-time snapshot** — filter `month = DATE_TRUNC('MONTH', CURRENT_DATE)` (or a chosen
  month) instead of trending, so denominators are a single consistent snapshot.

## Superset Golden Assets

- **Condo Garantido — Superset dashboard** — the dashboard the owner team uses to track these metrics. Reference only: surface it to the user if they ask about Superset assets for this metric; it is not used in the calculation. URN: `urn:li:dashboard:(superset,dashboard.2314)` ([link](https://datahub.apps.data-prd.habitat.zone/dashboard/urn:li:dashboard:(superset,dashboard.2314)/))
