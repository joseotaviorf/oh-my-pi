# Listing Demand Funnel Conversions (L2VB, L2VC, L2OS, L2TP, L2CCV)

## Overview

These metrics measure **listing cohort conversion** through the **demand funnel** — from publication to downstream events (visit booked, visit completed, offer submitted, tenant prospect, sale agreement signed).

**RENT and SALE use different fact models.** Never join `fact_visits` by `sk_house` alone for **For Rent listing cohorts** — one house can have **N listing versions** (`sk_house_listing`). For RENT, prefer **`dw_rent.fact_listing_rent_flows`** keyed on **`sk_house_listing`**.

| Metric | Meaning | RENT | SALE |
|--------|---------|------|------|
| **L2VB** | Listing → Visit Booked | ✅ | ✅ |
| **L2VC** | Listing → Visit Completed | ✅ | ✅ |
| **L2OS** | Listing → Offer Submitted | ✅ | ✅ |
| **L2TP** | Listing → **Tenant Prospect** | ✅ **RENT only** | ❌ different demand model |
| **L2CCV** | Listing → CCV / Sale Agreement Signed | ❌ use **L2R** / `listing_to_rental` | ✅ |

**Contract signed (RENT)** is **L2R** — not L2CCV. See `metric_entities/listing_to_rental.md`.

## Related Business Entities

- House and Listing
- FR Transact
- FS Transact
- Visits

## Glossary and Synonyms

- **L2VB**, **Listing to Visit Booked** → first visit booked within cohort window
- **L2VC**, **Listing to Visit Completed** → visit completed within window
- **L2OS**, **Listing to Offer Submitted** → offer submitted within window
- **L2TP**, **Listing to Tenant Prospect** → **RENT only** — listing reached **VB and/or OS** within window
- **TP**, **Tenant Prospect** → demand actor in rent flow (`fact_listing_rent_flows.sk_client`); L2TP counts listings that generated TP activity (VB or OS)
- **L2CCV**, **Listing to CCV**, **Sale Agreement Signed** → **SALE only** — CCV signed within window
- **LVB2LVC**, **LVC2LOS**, **LOS2LOA**, **LOA2LCCV** → step-to-step conversion rates between funnel stages (numerator/denominator of adjacent steps)
- **M0+M1** (**SALE**) → conversion from **publication date** through end of the **following calendar month** — additional horizon beside 8W/12W

## Scope (shared)

**Cohort denominator:** listing versions published in the reference period (typically **`DATE_TRUNC('month', ts_publication)`**).

| Context | Cohort table | Publication anchor | Listing key |
|---------|--------------|-------------------|-------------|
| **RENT** | `dw_rent.dim_house_listing` | `ts_publication` | `sk_house_listing` |
| **SALE** | `dw_sale.dim_listing` / `dw_sale.fact_listings` | `ts_first_publication` or first publication date | `sk_sale_listing` |

**Rate formula (all metrics):**

```
L2X (window W) = COUNT(DISTINCT listings with event X within W days/weeks of publication)
                 / COUNT(DISTINCT listings in cohort)
```

Cohorts whose conversion window has not ended are **incomplete** — still valid to report; state that explicitly (rates will keep updating).

---

## For Rent (RENT)

### Source of truth

**`dw_rent.fact_listing_rent_flows`** — event-grain rent-flow fact keyed on **`sk_house_listing`**. Use **`sk_*_date`** columns (join `dw_public.dim_date`) or pre-computed day fields; `-1` / `≤ 0` = event not reached.

| Metric | Event signal on `fact_listing_rent_flows` |
|--------|-------------------------------------------|
| **L2VB** | `sk_booking_created_date > 0` within window |
| **L2VC** | `flg_visit_completed = TRUE` and visit date within window (or `sk_visit_date` + completion flag) |
| **L2OS** | `sk_offer_submitted_date > 0` within window |
| **L2TP** | **`sk_booking_created_date > 0` OR `sk_offer_submitted_date > 0`** within window |

**Do not use** `dw_rent.fact_visits` / `fact_visits.sk_house` for listing-level RENT cohorts — misattributes demand across listing versions on the same house.

### L2TP (RENT)

**L2TP = Listing to Tenant Prospect** — a listing converts when it receives **at least one Visit Booked (VB) or Offer Submitted (OS)** within the cohort window (at least one tenant prospect entered the rent flow on that listing version).

Direct offers (OS without prior VB) **count** toward L2TP.

### Canonical filter (RENT cohort)

```sql
dhl.ts_publication IS NOT NULL
-- AND dhl.country_code = 'BR'   -- when country-specific
```

Windows: **1W / 2W / 4W** from `CAST(dhl.ts_publication AS DATE)` (common for L2VB, L2VC, L2OS, L2TP).

### Golden Query — RENT listing cohort + demand flags (pattern)

Adapt window (`INTERVAL '1' WEEK`, `'2' WEEK`, `'4' WEEK`) and which flag defines the metric.

```sql
WITH listing_pub AS (
    SELECT
        dhl.sk_house_listing,
        dhl.id_house,
        CAST(dhl.ts_publication AS DATE) AS publication_date,
        DATE_TRUNC('month', dhl.ts_publication) AS cohort_month,
        publication_date + INTERVAL '4' WEEK AS window_end_4w
    FROM dw_rent.dim_house_listing AS dhl
    WHERE dhl.ts_publication IS NOT NULL
),
listing_demand AS (
    SELECT
        lp.sk_house_listing,
        lp.cohort_month,
        MAX(CASE
            WHEN rf.sk_booking_created_date > 0
             AND dd_vb.date BETWEEN lp.publication_date AND lp.window_end_4w
            THEN 1 ELSE 0
        END) AS has_vb_4w,
        MAX(CASE
            WHEN rf.flg_visit_completed = TRUE
             AND rf.sk_visit_date > 0
             AND dd_vc.date BETWEEN lp.publication_date AND lp.window_end_4w
            THEN 1 ELSE 0
        END) AS has_vc_4w,
        MAX(CASE
            WHEN rf.sk_offer_submitted_date > 0
             AND dd_os.date BETWEEN lp.publication_date AND lp.window_end_4w
            THEN 1 ELSE 0
        END) AS has_os_4w,
        MAX(CASE
            WHEN (
                (rf.sk_booking_created_date > 0 AND dd_vb.date BETWEEN lp.publication_date AND lp.window_end_4w)
                OR (rf.sk_offer_submitted_date > 0 AND dd_os.date BETWEEN lp.publication_date AND lp.window_end_4w)
            ) THEN 1 ELSE 0
        END) AS has_tp_4w
    FROM listing_pub AS lp
    LEFT JOIN dw_rent.fact_listing_rent_flows AS rf
        ON rf.sk_house_listing = lp.sk_house_listing
    LEFT JOIN dw_public.dim_date AS dd_vb
        ON dd_vb.sk_date = rf.sk_booking_created_date
    LEFT JOIN dw_public.dim_date AS dd_vc
        ON dd_vc.sk_date = rf.sk_visit_date
    LEFT JOIN dw_public.dim_date AS dd_os
        ON dd_os.sk_date = rf.sk_offer_submitted_date
    GROUP BY lp.sk_house_listing, lp.cohort_month
)
SELECT
    cohort_month,
    COUNT(DISTINCT sk_house_listing) AS cohort_size,
    1.000 * SUM(has_vb_4w) / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS l2vb_4w,
    1.000 * SUM(has_vc_4w) / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS l2vc_4w,
    1.000 * SUM(has_os_4w) / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS l2os_4w,
    1.000 * SUM(has_tp_4w) / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS l2tp_4w
FROM listing_demand
GROUP BY 1
ORDER BY 1 DESC
```

**L2R** in a 4W window — ad-hoc slice only; same cohort base; join `dim_contract` on `rf.sk_contract` with `ts_signature` between publication and window end (reference pattern):

```sql
-- L2R 4W slice (RENT) — not L2CCV; not the official monthly L2R
MIN(c.ts_signature) FILTER (
    WHERE c.ts_signature BETWEEN lp.publication_date AND lp.publication_date + INTERVAL '4' WEEK
) IS NOT NULL
-- via fact_listing_rent_flows rf + dim_contract c on rf.sk_contract
```

Official **L2R** (monthly, no fixed window) → `metric_entities/listing_to_rental.md`.

---

## For Sale (SALE)

### Source of truth

SALE listing demand uses **house-keyed** visit/offer/CCV facts (one active sale listing per house in typical funnel joins):

| Metric | Primary tables |
|--------|----------------|
| **L2VB** | `dw_sale.fact_visits` — `ts_booking_created` |
| **L2VC** | `dw_sale.fact_visits` — `ts_visit_completed` |
| **L2OS** | `dw_sale.fact_offers` + `dw_sale.dim_offer` — `ts_offer_submitted` |
| **L2CCV** | `dw_sale.dim_sale_agreement` — `ts_sale_agreement_signed` |

Entry point for offer funnel: **`dw_sale.fact_offers`** (EoF). Join **`dim_offer`**, **`dim_sale_agreement`** for timestamps and status.

**L2TP does not apply to SALE** the same way — buyers can submit **direct offers** without a visit; do not reuse the RENT L2TP definition.

### L2CCV windows (SALE)

Report **8W** and **12W** from publication date, plus **M0+M1**:

- **8W / 12W:** `ts_sale_agreement_signed` within 8 / 12 weeks of listing publication
- **M0+M1:** CCV signed from **`publication_date`** through the **last day of the calendar month after publication** (remainder of publication month + full next month — not from month start, which would count pre-publication events)

### Canonical filter (SALE cohort)

```sql
dl.ts_first_publication IS NOT NULL
-- cohort month: DATE_TRUNC('month', dl.ts_first_publication)
```

Use `sk_sale_listing` as listing grain; join demand on **`sk_house`** (validated FS demand pattern).

### Golden Query — SALE listing cohort + demand (pattern)

Reference demand join pattern — adapt anchor from `ts_first_publication` instead of `ts_first_message` when building listing cohorts.

```sql
WITH listing_pub AS (
    SELECT
        dl.sk_sale_listing,
        dl.sk_house,
        CAST(dl.ts_first_publication AS DATE) AS publication_date,
        DATE_TRUNC('month', dl.ts_first_publication) AS cohort_month,
        publication_date + INTERVAL '8' WEEK AS window_end_8w,
        publication_date + INTERVAL '12' WEEK AS window_end_12w,
        DATE_TRUNC('month', dl.ts_first_publication) + INTERVAL '2' MONTH - INTERVAL '1' DAY AS m0_m1_end
    FROM dw_sale.dim_listing AS dl
    WHERE dl.ts_first_publication IS NOT NULL
),
listing_demand AS (
    SELECT
        lp.sk_sale_listing,
        lp.cohort_month,
        MIN(fv.ts_booking_created) FILTER (
            WHERE fv.ts_booking_created BETWEEN lp.publication_date AND lp.window_end_8w
        ) AS ts_vb_8w,
        MIN(fv.ts_visit_completed) FILTER (
            WHERE fv.ts_visit_completed BETWEEN lp.publication_date AND lp.window_end_8w
        ) AS ts_vc_8w,
        MIN(do.ts_offer_submitted) FILTER (
            WHERE do.ts_offer_submitted BETWEEN lp.publication_date AND lp.window_end_8w
        ) AS ts_os_8w,
        MIN(sa.ts_sale_agreement_signed) FILTER (
            WHERE sa.ts_sale_agreement_signed BETWEEN lp.publication_date AND lp.window_end_8w
        ) AS ts_ccv_8w,
        MIN(sa.ts_sale_agreement_signed) FILTER (
            WHERE sa.ts_sale_agreement_signed BETWEEN lp.publication_date AND lp.window_end_12w
        ) AS ts_ccv_12w,
        MIN(sa.ts_sale_agreement_signed) FILTER (
            WHERE sa.ts_sale_agreement_signed BETWEEN lp.publication_date AND lp.m0_m1_end
        ) AS ts_ccv_m0_m1
    FROM listing_pub AS lp
    LEFT JOIN dw_sale.fact_visits AS fv
        ON fv.sk_house = lp.sk_house
    LEFT JOIN dw_sale.fact_offers AS fo
        ON fo.sk_house = lp.sk_house
    LEFT JOIN dw_sale.dim_offer AS do
        ON fo.sk_offer = do.sk_offer
    LEFT JOIN dw_sale.dim_sale_agreement AS sa
        ON fo.sk_offer = sa.sk_offer
    GROUP BY lp.sk_sale_listing, lp.cohort_month, lp.publication_date
)
SELECT
    cohort_month,
    COUNT(DISTINCT sk_sale_listing) AS cohort_size,
    1.000 * COUNT(DISTINCT CASE WHEN ts_vb_8w IS NOT NULL THEN sk_sale_listing END)
        / NULLIF(COUNT(DISTINCT sk_sale_listing), 0) AS l2vb_8w,
    1.000 * COUNT(DISTINCT CASE WHEN ts_vc_8w IS NOT NULL THEN sk_sale_listing END)
        / NULLIF(COUNT(DISTINCT sk_sale_listing), 0) AS l2vc_8w,
    1.000 * COUNT(DISTINCT CASE WHEN ts_os_8w IS NOT NULL THEN sk_sale_listing END)
        / NULLIF(COUNT(DISTINCT sk_sale_listing), 0) AS l2os_8w,
    1.000 * COUNT(DISTINCT CASE WHEN ts_ccv_8w IS NOT NULL THEN sk_sale_listing END)
        / NULLIF(COUNT(DISTINCT sk_sale_listing), 0) AS l2ccv_8w,
    1.000 * COUNT(DISTINCT CASE WHEN ts_ccv_12w IS NOT NULL THEN sk_sale_listing END)
        / NULLIF(COUNT(DISTINCT sk_sale_listing), 0) AS l2ccv_12w,
    1.000 * COUNT(DISTINCT CASE WHEN ts_ccv_m0_m1 IS NOT NULL THEN sk_sale_listing END)
        / NULLIF(COUNT(DISTINCT sk_sale_listing), 0) AS l2ccv_m0_m1
FROM listing_demand
GROUP BY 1
ORDER BY 1 DESC
```

Use **1W / 2W / 4W / 8W** for L2VB/L2VC/L2OS on SALE by shortening the interval on the demand joins.

---

## Dos and Don'ts

**Do:**

- Confirm **RENT vs SALE** and the **metric code** (L2VB, L2VC, L2OS, L2TP, L2CCV) before writing SQL
- **RENT:** anchor on **`sk_house_listing`** via **`fact_listing_rent_flows`**
- **SALE:** anchor listing cohort on **`sk_sale_listing`**, join demand on **`sk_house`**
- Call out **incomplete** cohorts when the conversion window has not yet closed (8W, 12W, M0+M1, 4W, …)
- Report **cohort size** with rates

**Don't:**

- Don't apply **L2TP** to SALE
- Don't use **`fact_visits.sk_house`** alone for **RENT listing cohort** metrics
- Don't defer to Looker or “confirm with owner” — run the golden query pattern
- Don't confuse **L2CCV** (SALE) with **L2R** (RENT) — same as Listing to Contract Signed
- Don't mix RENT and SALE in one query without normalizing keys and tables
