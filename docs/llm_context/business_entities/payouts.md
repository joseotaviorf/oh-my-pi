# Payouts


## Ownership


**Data Owner:**
- guilherme.vancine@quintoandar.com


**Data Steward:**
- thiago.villani@quintoandar.com.br


## Overview


Payouts is the **cash-out domain**: every flow of money leaving QuintoAndar toward an external
beneficiary. Its flagship case is the For Rent promise to the landlord — the rent is paid
whatever happens to the tenant, and it lands in the landlord's account until the 12th of each
month. The Payouts team owns the fulfillment of that promise, and its headline indicator is the
share of monthly landlord payouts completed by the due date. Beyond rent, the same rails carry
agent commissions, condominium bills, and ad-hoc payments originated in For Sale or Classifieds.


A rental payout travels three hops, and each hop answers a different question:


1. **Formation** — the payout is an invoice in Retsuko / SeuBarriga (`datalake_retsuko_clean.invoice`),
  with `ts_due` and `ts_paid`. This is the *what*: was it paid, and when.
2. **Remittance** — the payment request is handed to the VAN middleman
  (`datalake_vans_clean.payment`), which builds the bank file and carries `style` (rail) and
  `occurrence_code`. This is the *how*.
3. **Bank return** — the bank answers with a CNAB return processed by Nexxera
  (`datalake_nexxera.cnab_payments`), carrying the attempt number and the occurrence code. This
  is the *why*: invalid account, insufficient balance, wrong holder, scheduled, settled.


Two systems are being built and change the picture going forward. **`payout_system`**
(`datalake_payout_system_clean`) is the orchestrator replacing the Vans-plus-spreadsheet flow; it
is already live for auxiliary flows such as condominium bills but **does not yet carry rental
landlord payouts**. **`banking-data`** will own cataloging, validating, and refreshing landlord
bank accounts — today the weakest link, since bank details are collected during contract closing
and rarely revalidated, which is why early-cohort contracts show a worse payout rate than mature
ones. `banking-data` has **no lake tables yet**; until it ships, the landlord's bank details live
in the `dadosbancarios_*` columns of `dw_public.dim_user` and in `datalake_retsuko_clean.account`.


Reference dashboards: [Payouts overview](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1361/)
and [payout deep dive](https://superset.apps.data-prd.habitat.zone/superset/dashboard/3682/).


## Related Metric Entities

- [% Monthly Payouts Successfully Completed Until Due Date](../metric_entities/monthly_payouts_successfully_completed_until_due_date.md) — the official on-time landlord payout rate.


## Glossary and Synonyms


- **repasse**, **repasse de aluguel**, **payout**, **cash-out** → a payment leaving QuintoAndar to
 a landlord or other beneficiary; an invoice with `account.type = 'landlord'`
- **sign convention** → landlord (payout) invoices have `invoice.due_amount > 0`; tenant
 (collections) invoices have `due_amount < 0`. The deterministic test is still
 `account.type = 'landlord'`, not the sign
- **SeuBarriga**, **Retsuko** → the billing system where every invoice is formed, payouts included
 (`datalake_retsuko_clean.*`)
- **VAN**, **Vans** → Value Added Network middleman that batches payment requests into bank files
 and returns the bank's answer (`datalake_vans_clean.payment`)
- **CNAB**, **francesinha** → the bank return file layout; payment returns land in
 `datalake_nexxera.cnab_payments`
- **SISPAG** → Itaú's payment-return code standard; the `source_file_type` of most payout
 occurrence codes in `dw_payment.dim_occurrence_code`
- **ocorrência**, **occurrence** → the bank's coded answer to a payment attempt. Anything other
 than `PAGAMENTO EFETUADO` or `PAGAMENTO AGENDADO` is a failure
- **estorno** → a payout that left and came back (rejected or returned by the beneficiary bank);
 detected through a failure occurrence rather than through invoice status
- **MOB**, **mob de repasse** → months on book, the age of the contract in months at the payout's
 accrual month; `12 * (YEAR(ts_due) - YEAR(dt_start)) + (MONTH(ts_due) - MONTH(dt_start))`
- **on due**, **no prazo** → paid on or before day 11 of the month (see the metric entity for the
 exact official rule)
- **dados bancários** → the landlord's bank account details, the dominant root cause of payout
 failures (`dadosbancarios_*` in `dw_public.dim_user`)
- **accrual year month** → the month when the invoice is created and the rental is accounted, not the month the payment is made and the money actually moves (`accrual_month` in `datalake_retsuko_clean.invoice`)


## Tables


| You need... | Use this table |
|-------------|----------------|
| The payout invoice itself: due/paid timestamps, amount, accrual month, status | `datalake_retsuko_clean.invoice` — filter `purpose = 'monthly'` for rent payouts |
| To decide whether an invoice is a payout or a collection | `datalake_retsuko_clean.account` — `type = 'landlord'` is the deterministic test |
| Contract eligibility and the contractual payout day | `datalake_retsuko_clean.contract` — `country_code`, `status`, `landlord_transfer_funds_day` |
| The payment request sent to the bank: rail, payee bank details, occurrence | `datalake_vans_clean.payment` — `style`, `payee_*`, `occurrence_code`, `our_number` |
| The bank's return per attempt: was it settled, when, on which try | `datalake_nexxera.cnab_payments` — `our_number`, `payment_attempts`, `is_latest_attempt` |
| To translate an occurrence code into a human reason | `dw_payment.dim_occurrence_code` — `sk_occurrence_code`, `description` |
| A DW view of Vans transfers already typed by beneficiary | `dw_payment.fact_banking_file_payments` and `dw_payment.dim_banking_file_payment` — `user_type = 'landlord'`, `type = 'transfer'` |
| Contract age (MOB), annulment and intended end for cohort analysis | `dw_rent.dim_contract` — `dt_start`, `dt_annulment`, `dt_intended_end` |
| Who the landlord on a contract is | `dw_rent.fact_contract_people` — `contract_role = 'landlord'` |
| Landlord contact details and current bank account | `dw_public.dim_user` — `nome`, `email`, `telefone_principal`, `dadosbancarios_*` |
| Whether a payout was affected by a rent-anticipation product | `datalake_retsuko.bill_items` — `bill_item` in the `RENTAL-ANTICIPATION*` / `INSTALLMENT-LRA` family |
| Non-rental payouts orchestrated outside Retsuko | `datalake_robin_hood_clean.payment_request` joined through `datalake_robin_hood_clean.accounting_entry_balance`, `datalake_robin_hood_clean.accounting_entry`, `datalake_robin_hood_clean.accounting_entry_source` |
| The new orchestrator: requests, status history, failure reasons | `datalake_payout_system_clean.payment_request`, `datalake_payout_system_clean.payment_status_history`, `datalake_payout_system_clean.reason` |
| The new orchestrator: beneficiary and bank account registry | `datalake_payout_system_clean.payee`, `datalake_payout_system_clean.payee_account` |
| The new orchestrator: who requested and under which flow | `datalake_payout_system_clean.requester`, `datalake_payout_system_clean.flow` |
| Bank-file submission batches sent to the bank | `datalake_payout_system_clean.bank_submission`, `datalake_payout_system_clean.bank_submission_item` |
| Whether a payout reconciles across bank, billing and accounting | `datalake_bank_conciliation.for_rent_cashout` |


**Critical rules:**


- `account.type = 'landlord'` is the only reliable payout test. `due_amount > 0` correlates with it
 but is a consequence, not a definition.
- Join Vans to Retsuko with a cast: `CAST(p.id_related_document AS BIGINT) = i.id_external`.
 `id_related_document` is a VARCHAR. When joining Vans to Robin Hood instead, the key is
 `p.company_use = CAST(pr.id AS VARCHAR)`.
- Join Vans to Nexxera on `our_number`. One invoice can have several bank attempts, so deduplicate
 with `ROW_NUMBER() OVER (PARTITION BY p.id_related_document ORDER BY cp.dt_paid DESC, cp.payment_attempts DESC)`
 or filter `cp.is_latest_attempt`.
- `occurrence_code` may concatenate up to three 2-character occurrences. The **trailing pair is the
 highest-detail one** — that is exactly what `dim_occurrence_code.last_code` documents. Resolve a
 description by joining on `SUBSTR(occurrence_code, -2)`; `dim_occurrence_code.description` is
 populated only for single 2-character entries, so a NULL means a combined or unmapped code.
- `invoice.status` uses the **hyphenated** `'not-payable'`. `'not payable'` with a space matches
 nothing.
- `datalake_payout_system_clean` does **not** yet contain rental landlord payouts — only auxiliary
 flows such as condominium. Do not use it for the on-time rent payout rate.
- `dw_public.dim_user` carries raw PII and bank details. Query it for investigation, never export it
 to an external system without the `has_right_to_be_forgotten` guard on `dw_public.dim_person`.


## Key Metrics

Use [Related Metric Entities](#related-metric-entities) for the **official** on-time landlord payout rate. The bullets below are **component** payout operational metrics.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| % Monthly Payouts Successfully Completed Until Due Date | [% Monthly Payouts Successfully Completed Until Due Date](../metric_entities/monthly_payouts_successfully_completed_until_due_date.md) |

### Component / exploratory metrics

- **Monthly payout on-due rate** — component approximation; official definition in the metric entity above
- **Payout rate by MOB** — the same rate split by contract age, which isolates the bank-data
 maturation effect
- **Occurrence rate** — share of payouts whose latest bank return is neither `PAGAMENTO EFETUADO`
 nor `PAGAMENTO AGENDADO`
- **Failure mix** — payout count by `dim_occurrence_code.description`, the input for prioritizing
 bank-data fixes
- **Estorno rate** — share of payouts that were sent and returned
- **Attempts to settle** — `cnab_payments.payment_attempts` on the settling return
- **Rail mix** — payout count by `vans_clean.payment.style` (PIX, TED, TEF)
- **Payout volume** — `COUNT(*)` and `SUM(paid_amount)` by requester and purpose, across all
 business units
- **Days late** — `date_diff('day', DATE(ts_due), DATE(ts_paid))` for payouts that missed the date


## Relationships with Other Entities


### Contract (1:N — one contract, many monthly payouts)


- `datalake_retsuko_clean.contract.id_external = dw_rent.dim_contract.sk_contract`
- Within an accrual month the relationship to a rent payout invoice is effectively **1:1** — a
 contract is charged one monthly rent invoice per month. This is what allows the on-time rate to
 be counted at contract grain.


### Landlord / User (N:1 — many payouts to one landlord)


- `dw_rent.fact_contract_people.sk_contract = contract.id_external`, filtered on
 `contract_role = 'landlord'`, then `dw_public.dim_user.sk_user = fact_contract_people.sk_user`.
- A contract can have more than one landlord; deduplicate before counting payouts per person.


### Payments (disjoint — cash-in vs cash-out)


- [Payments](payments.md) models money coming **in** and uses `datalake_vans_clean.boleto`. Payouts
 models money going **out** and uses `datalake_vans_clean.payment`. Different tables, no overlap;
 do not union them.


### Bank Reconciliation (N:1 — many payouts to one reconciliation row)


- `datalake_bank_conciliation.for_rent_cashout` reconciles the same payouts against bank statements
 and SAP. Use it to answer "did the money truly leave and get booked", not "was the landlord paid
 on time".


### Collections (mirror image on the same invoice table)


- [Collections](collections.md) works the tenant side of `datalake_retsuko_clean.invoice`
 (`account.type = 'tenant'`, negative `due_amount`). A tenant default does not excuse a late
 payout — that is the whole point of the product promise.


## Dos and Don'ts


**Do:**


- Filter `account.type = 'landlord'` plus `invoice.purpose = 'monthly'` to isolate rent payouts.
- Restrict to `contract.country_code = 'BR'` and `contract.status <> 'canceled'` for any payout
 performance number.
- Deduplicate Nexxera returns per invoice before joining, otherwise one payout with three attempts
 triples in a `COUNT`.
- Resolve occurrence descriptions through `dw_payment.dim_occurrence_code` on
 `SUBSTR(occurrence_code, -2)` instead of writing a `CASE` over a hundred codes.
- Treat `PAGAMENTO EFETUADO` and `PAGAMENTO AGENDADO` as the only non-failure occurrences.
- Use `dw_rent.dim_contract.dt_start` for MOB, and expect early MOB cohorts to underperform because
 of unvalidated bank data.
- Prefer `dw_public.dim_person` when you need only contact PII; reach for `dw_public.dim_user` when
 you specifically need the `dadosbancarios_*` bank details.


**Don't:**


- Don't use `datalake_vans_clean.boleto` for payouts — that is the cash-in table. Payouts live in
 `datalake_vans_clean.payment`.
- Don't join `id_related_document` to `id_external` without `CAST(... AS BIGINT)`; the types differ
 and the join silently returns nothing.
- Don't write `'not payable'` with a space in a `status` filter — the real value is `'not-payable'`.
- Don't read `datalake_payout_system_clean.payment_request` expecting rent payouts; rental volume
 has not migrated there yet.
- Don't infer payout success from `invoice.status = 'paid'` alone. An estorno can leave the invoice
 looking paid while the money bounced back; check the latest bank occurrence.
- Don't count payouts per contract without scoping to one `accrual_year_month` — the 1:1 contract
 to rent invoice relationship only holds inside a single month.
- Don't reference a `banking_data` table; the application has no lake tables yet.


## Golden Queries


### Query 1 — Landlord monthly payout base


The canonical starting point: one row per landlord monthly rent payout, with the on-due flag and
the validity classification that every payout metric builds on.


```sql
SELECT
   c.id_external AS sk_contract,
   i.id_external AS sk_invoice,
   i.accrual_year_month AS invoice_accrual_year_month,
   i.status AS invoice_payment_status,
   i.due_amount AS invoice_due_amount,
   i.paid_amount AS invoice_paid_amount,
   DATE(i.ts_due) AS dt_invoice_due,
   DATE(i.ts_paid) AS dt_invoice_paid,
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
```


### Query 2 — Why payouts failed, by bank occurrence reason


Answers "why couldn't we pay" by attaching the latest bank return to each payout and resolving the
occurrence code through the existing dimension.


```sql
WITH landlord_payouts AS (
   SELECT
       i.id_external AS sk_invoice,
       i.accrual_year_month AS invoice_accrual_year_month
   FROM datalake_retsuko_clean.invoice AS i
   INNER JOIN datalake_retsuko_clean.account AS a
       ON a.id = i.id_account
   WHERE a.type = 'landlord'
       AND i.purpose = 'monthly'
       AND i.accrual_year_month >= 202301
),
bank_returns AS (
   SELECT
       CAST(p.id_related_document AS BIGINT) AS sk_invoice,
       doc.description AS occurrence_reason,
       CASE
           WHEN p.style = '01' THEN 'TEF CHECKING SAME BANK'
           WHEN p.style = '05' THEN 'TEF SAVINGS SAME BANK'
           WHEN p.style = '41' THEN 'TED OTHER HOLDER'
           WHEN p.style = '45' THEN 'PIX TRANSFER'
       END AS payment_method,
       ROW_NUMBER() OVER (
           PARTITION BY p.id_related_document
           ORDER BY cp.dt_paid DESC, cp.payment_attempts DESC
       ) AS rn
   FROM datalake_vans_clean.payment AS p
   INNER JOIN datalake_nexxera.cnab_payments AS cp
       ON cp.our_number = p.our_number
   LEFT JOIN dw_payment.dim_occurrence_code AS doc
       ON doc.sk_occurrence_code = SUBSTR(cp.occurrence_code, -2)
   WHERE p.occurrence_code IS NOT NULL
)
SELECT
   lp.invoice_accrual_year_month,
   COALESCE(br.occurrence_reason, 'NO BANK RETURN') AS occurrence_reason,
   br.payment_method,
   COUNT(DISTINCT lp.sk_invoice) AS n_payouts
FROM landlord_payouts AS lp
LEFT JOIN bank_returns AS br
   ON br.sk_invoice = lp.sk_invoice
   AND br.rn = 1
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 4 DESC
```


### Query 3 — Payout rate by contract age (MOB cohort)


Isolates the bank-data maturation effect: young contracts pay worse because their bank details are
not yet validated. The denominator is **invoice grain** and will not tie out to the official
contract-grain number.


```sql
WITH landlord_invoices AS (
   SELECT
       c.id_external AS sk_contract,
       i.id_external AS sk_invoice,
       i.accrual_year_month AS invoice_accrual_year_month,
       12 * (YEAR(i.ts_due) - YEAR(dc.dt_start))
           + (MONTH(i.ts_due) - MONTH(dc.dt_start)) AS mob_payout,
       i.status NOT IN ('not-payable', 'canceled') AND i.due_amount > 0 AS is_valid_payout,
       i.ts_paid IS NOT NULL AND EXTRACT(DAY FROM i.ts_paid) <= 11 AS payment_on_due
   FROM datalake_retsuko_clean.contract AS c
   INNER JOIN datalake_retsuko_clean.invoice AS i
       ON i.id_contract = c.id
   INNER JOIN datalake_retsuko_clean.account AS a
       ON a.id = i.id_account
   LEFT JOIN dw_rent.dim_contract AS dc
       ON dc.sk_contract = c.id_external
   WHERE c.country_code = 'BR'
       AND c.status <> 'canceled'
       AND a.type = 'landlord'
       AND i.purpose = 'monthly'
       AND i.accrual_year_month >= 202301
),
contract_month AS (
   SELECT
       sk_contract,
       invoice_accrual_year_month,
       MIN(mob_payout) AS mob_payout,
       COUNT(DISTINCT sk_invoice) AS n_invoices,
       COUNT(DISTINCT CASE WHEN NOT is_valid_payout THEN sk_invoice END) AS n_occurrences,
       COUNT(DISTINCT CASE WHEN is_valid_payout AND payment_on_due THEN sk_invoice END) AS n_on_due
   FROM landlord_invoices
   GROUP BY 1, 2
)
SELECT
   invoice_accrual_year_month,
   CASE
       WHEN mob_payout <= 1 THEN '1.MOB 1-'
       WHEN mob_payout >= 7 THEN '7.MOB 7+'
       ELSE CONCAT(CAST(mob_payout AS VARCHAR), '.MOB ', CAST(mob_payout AS VARCHAR))
   END AS mob_class,
   CAST(SUM(n_on_due) AS DOUBLE)
       / NULLIF(SUM(n_invoices) - SUM(n_occurrences), 0) AS payout_rate_on_due
FROM contract_month
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```


### Query 4 — Landlords behind a missed payout, with their bank details


Who to contact and which bank data to fix after a payout misses the date. Investigation only —
never export these columns to an external system.


```sql
SELECT
   fcp.sk_contract,
   du.nome AS landlord_name,
   du.email AS landlord_email,
   du.telefone_principal AS landlord_phone,
   du.dadosbancarios_banco AS landlord_bank,
   du.dadosbancarios_agencia AS landlord_bank_agency,
   du.dadosbancarios_tipo_conta AS landlord_account_type,
   du.dadosbancarios_outro_titular AS is_third_party_account
FROM dw_rent.fact_contract_people AS fcp
INNER JOIN dw_public.dim_user AS du
   ON du.sk_user = fcp.sk_user
WHERE fcp.contract_role = 'landlord'
   AND fcp.country_code = 'BR'
   AND fcp.sk_contract IN (
       SELECT c.id_external
       FROM datalake_retsuko_clean.contract AS c
       INNER JOIN datalake_retsuko_clean.invoice AS i
           ON i.id_contract = c.id
       INNER JOIN datalake_retsuko_clean.account AS a
           ON a.id = i.id_account
       WHERE a.type = 'landlord'
           AND i.purpose = 'monthly'
           AND i.accrual_year_month = 202606
           AND i.due_amount > 0
           AND i.status NOT IN ('not-payable', 'canceled')
           AND (i.ts_paid IS NULL OR EXTRACT(DAY FROM i.ts_paid) > 11)
   )
```



