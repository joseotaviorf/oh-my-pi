# % Monthly Payouts Successfully Completed Until Due Date

## Ownership

**Data Owner:**
- guilherme.vancine@quintoandar.com.br

**Data Steward:**
- thiago.villani@quintoandar.com.br

## Overview

**% Monthly Payouts Successfully Completed Until Due Date** is the share of For Rent landlord
monthly rent payouts that reached the landlord's account by the contractual due date. It is the
Payouts team's headline indicator and the direct measurement of QuintoAndar's core promise to the
landlord: the rent arrives whatever happens to the tenant.

The naive calculation goes wrong in two ways. It counts every landlord invoice, when the universe
is only **valid, payable** monthly invoices — canceled and not-payable rows are neither successes
nor failures and must leave the denominator entirely, not be counted as misses. And it reaches for
`ts_due`, when the official rule is a **fixed calendar cutoff of day 11** of the payment month,
independent of the invoice's own due timestamp and of the contract's `landlord_transfer_funds_day`.

**Exists exclusively for For Rent, Brazil, and monthly rent payouts to landlords.** Agent
commissions, condominium bills, and other outward flows are out of scope even though they share the
same payment rails.

## Related Business Entities

- Payouts

## Catalog

| Metric | Type |
| :---- | :---- |
| % Monthly Payouts Successfully Completed Until Due Date | OKR |

## MBR

**Name** Fintech MBR

## Glossary and Synonyms

- **% Monthly Payouts successfully completed until due date**, **monthly on-time payout rate**,
  **payout on-due rate**, **percentage payment on due** → this metric
- **repasse no prazo**, **% de repasse no prazo**, **repasse pago em dia** → this metric
- **on due**, **no prazo**, **em dia** → paid on or before day 11 of the payment month
- **payment_on_due** → the boolean column name this metric aggregates
- **MOB payout rate**, **repasse por MOB** → the contract-age breakdown, which is a *different*
  denominator; see Nuances

## Scope

**Included**: For Rent landlord monthly rent payouts on Brazilian contracts — invoices where
`account.type = 'landlord'` and `purpose = 'monthly'`, on contracts with `country_code = 'BR'` and
a non-canceled status, from accrual month 202301 onward. Both paid and unpaid invoices count, since
an unpaid payout is a miss.

**Excluded**:

- Non-Brazilian contracts (`country_code <> 'BR'`)
- Canceled contracts (`contract.status = 'canceled'`)
- Tenant and collections invoices (`account.type <> 'landlord'`) — the mirror side of the same
  invoice table
- Non-monthly purposes (`purpose <> 'monthly'`) — extra payouts, adjustments, terminations
- Canceled and not-payable invoices (`invoice.status IN ('not-payable', 'canceled')`), and any
  invoice with `due_amount <= 0`: these are occurrences, removed from both numerator and denominator
- Accrual months before 202301, which predate reliable payout instrumentation
- Every non-rent outward flow (agent commissions, condominium, For Sale, Classifieds)

## Calculation

The metric is counted at **contract grain within an accrual month**. This is valid because a
contract is charged exactly one monthly rent invoice per accrual month, making the
contract-to-payout relationship 1:1 inside the month. Counting distinct contracts and counting
distinct valid invoices therefore return the same number.

```
% Monthly Payouts Successfully Completed Until Due Date
    = COUNT(DISTINCT sk_contract WHERE contract_status = 'Invoice' AND payment_on_due)
    / COUNT(DISTINCT sk_contract WHERE contract_status = 'Invoice')
```

where:

- `contract_status = 'Invoice'` marks a **valid, payable** payout:
  `invoice.status NOT IN ('not-payable', 'canceled') AND invoice.due_amount > 0`.
  Everything else is an occurrence and is excluded from both sides of the ratio.
- `payment_on_due` is true when the payout was paid on or before day 11 of the month it was paid in:
  `ts_paid IS NOT NULL AND EXTRACT(DAY FROM ts_paid) <= 11`. An unpaid invoice is false, never NULL.
- Both counts must be `COUNT(DISTINCT ...)`. Mixing a non-distinct numerator with a distinct
  denominator happens to produce the same number today because of the 1:1 relationship, but it is
  not a definition anyone should copy.

### Canonical Filter

Apply on `datalake_retsuko_clean.contract` joined to `datalake_retsuko_clean.invoice` and
`datalake_retsuko_clean.account`:

```sql
c.country_code = 'BR'
AND c.status <> 'canceled'
AND a.type = 'landlord'
AND i.purpose = 'monthly'
AND i.accrual_year_month >= 202301
```

**Warning**: dropping `a.type = 'landlord'` is the costly mistake. Without it the query pulls in
tenant collections invoices from the same `invoice` table — a far larger population with negative
`due_amount` and completely different payment behavior — and the resulting rate describes tenant
punctuality, not the landlord promise. Dropping `i.purpose = 'monthly'` is the second trap: it adds
extra and termination payouts that have no day-11 commitment, which deflates the rate.

### Nuances

**The day-11 cutoff is a calendar rule, not a business-day rule.** The contractual promise is "around
the 12th, give or take business days", but the official metric hardcodes day 11 of the month in which
the payout was paid. It reads neither `invoice.ts_due` nor `contract.landlord_transfer_funds_day`.
When day 11 falls on a weekend or holiday, a payout that settled on the next business day counts as
late. This is a known and accepted limitation of the official definition — do not silently "improve"
it.

**`'not-payable'` is hyphenated.** Some legacy Superset queries filter `'not payable'` with a space,
which matches nothing. The bug is harmless there only because not-payable invoices always carry
`due_amount = 0` and are already removed by the `due_amount > 0` predicate. Write the hyphenated
value; do not re-introduce the space, and do not remove the `due_amount > 0` guard that covers for it.

**The MOB breakdown uses a different denominator and will not tie out.** The contract-age view in
[Payouts](../business_entities/payouts.md) Query 3 counts at invoice grain, with the denominator
`total invoices - canceled - not-payable`. That is a deliberate second view for cohort diagnosis,
not a competing version of the headline number. Never present the two side by side as if they should
match.

**Occurrence and estorno data are diagnosis, not inputs.** The Vans and Nexxera CTEs that resolve
bank occurrence reasons explain *why* a payout missed the date. They contribute nothing to the ratio
and joining them changes no count — they are 1:1 after deduplication. Leave them out of the
canonical query.

## Dos and Don'ts

**Do:**

- Use `COUNT(DISTINCT sk_contract)` on both numerator and denominator.
- Classify every invoice as `'Invoice'` or occurrence first, then aggregate. Occurrences leave the
  ratio; they are not failures.
- Apply the full canonical filter, all five predicates, every time.
- Keep `payment_on_due` as a three-branch `CASE` that returns `false` for `ts_paid IS NULL`, so
  unpaid payouts count as misses instead of vanishing into NULL.
- Group by `accrual_year_month` — this is a monthly metric, and the accrual month is the reporting
  period, not the payment date.

**Don't:**

- Don't substitute `ts_due` or `landlord_transfer_funds_day` for the day-11 cutoff.
- Don't count canceled or not-payable invoices as misses; they are excluded from both sides.
- Don't mix the invoice-grain MOB denominator with this contract-grain ratio.
- Don't add the Vans or Nexxera occurrence joins to the canonical query — they are for failure
  analysis and only make the query slower and harder to audit.
- Don't derive the numerator from `invoice.status = 'paid'` alone; an estorno can leave a bounced
  payout looking paid.
- Don't report the current accrual month before day 11 has passed — the rate is mechanically
  incomplete until the payment window closes.

## Golden Queries

The official number, monthly. The `landlord_payouts` CTE is the component pattern already documented
in [Payouts](../business_entities/payouts.md) Query 1; what is exclusive to this metric is the
contract-grain distinct-count ratio over the valid-payout universe.

```sql
WITH landlord_payouts AS (
    -- Component pattern: see ../business_entities/payouts.md, Query 1.
    SELECT
        c.id_external AS sk_contract,
        i.accrual_year_month AS invoice_accrual_year_month,
        CASE
            WHEN i.status NOT IN ('not-payable', 'canceled') AND i.due_amount > 0 THEN 'Invoice'
            WHEN i.status = 'canceled' THEN 'Occurrence'
        END AS contract_status,
        CASE
            WHEN i.ts_paid IS NULL THEN false
            WHEN EXTRACT(DAY FROM i.ts_paid) > 11 THEN false
            ELSE true
        END AS payment_on_due
    FROM datalake_retsuko_clean.contract AS c
    INNER JOIN datalake_retsuko_clean.invoice AS i
        ON i.id_contract = c.id
    INNER JOIN datalake_retsuko_clean.account AS a
        ON a.id = i.id_account
    WHERE c.country_code = 'BR'
        AND c.status <> 'canceled'
        AND a.type = 'landlord'
        AND i.purpose = 'monthly'
        AND i.accrual_year_month >= 202301
)
SELECT
    invoice_accrual_year_month,
    CAST(COUNT(DISTINCT CASE
        WHEN contract_status = 'Invoice' AND payment_on_due THEN sk_contract
    END) AS DECIMAL(38, 4))
    / NULLIF(CAST(COUNT(DISTINCT CASE
        WHEN contract_status = 'Invoice' THEN sk_contract
    END) AS DECIMAL(38, 4)), 0) AS percentage_payment_on_due
FROM landlord_payouts
GROUP BY 1
ORDER BY 1 DESC
```

