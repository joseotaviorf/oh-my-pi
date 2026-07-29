-- Number of monthly rental invoices per due date, used to elect the standard due date of each
-- month. Restricted to real charges (due_amount <= 0 is the billed side of the ledger) and to
-- the current and previous month, which is all the reminder rule can reach.
WITH monthly_invoice_by_due_date AS (
    SELECT
        DATE(DATE_TRUNC('MONTH', ts_due)) AS dt_month,
        DATE(ts_due) AS dt_due,
        COUNT(id_external) AS n_invoices
    FROM
        datalake_retsuko.invoice
    WHERE
        purpose = 'monthly'
        AND due_amount <= 0
        AND ts_due >= ADD_MONTHS(DATE_TRUNC('MONTH', CURRENT_DATE()), -6)
    GROUP BY 1, 2
),
-- Rank the due dates of each month by invoice volume; the dominant one is the standard due
-- date. Later dates win ties so a manual re-issue never outranks the contractual date.
monthly_due_date_ranked AS (
    SELECT
        dt_month,
        dt_due,
        n_invoices,
        ROW_NUMBER() OVER (
            PARTITION BY dt_month
            ORDER BY n_invoices DESC, dt_due DESC
        ) AS rn_due_date
    FROM
        monthly_invoice_by_due_date
),
-- The single standard due date per month. Invoices due on any other date were moved by manual
-- intervention and follow their own schedule, so they are out of the reminder rule.
standard_due_date AS (
    SELECT
        dt_month,
        dt_due
    FROM
        monthly_due_date_ranked
    WHERE
        rn_due_date = 1
),
/* Open monthly rental invoices that are not yet overdue on the snapshot date, enriched with
the contract-level delay and payment-history features that drive the segment allocation.
The join on datalake_retsuko_clean.invoice is deliberate: it re-checks the payment status
against the transactional source at run time, so a tenant who paid after the collections
timeline was built is not reminded. invoice_delay_t1 <= 0 keeps only invoices whose nominal
due date has not passed yet, which is the whole population this initiative addresses. */
open_monthly_invoice AS (
    SELECT
        fiwt.sk_contract,
        fiwt.sk_invoice,
        fiwt.due_amount,
        fiwt.dt_due,
        fiwt.has_bill_item_condominio,
        DATEDIFF(fiwt.dt_due, CURRENT_DATE()) AS days_to_due,
        fcwt.max_delay_contaminated_contract_t1,
        fcwt.max_delay_contaminated_contract_t2,
        fcft.n_days_over1_t2_l180
    FROM
        dw_collections_segmentation.fact_invoice_wallet_timeline AS fiwt
    INNER JOIN
        datalake_retsuko_clean.invoice AS ret
            ON ret.id_external = fiwt.sk_invoice
            AND ret.payment_status = 'open'
            AND ret.ts_due >= DATE_TRUNC('MONTH', CURRENT_DATE())
    LEFT JOIN
        dw_collections_segmentation.fact_contract_wallet_timeline AS fcwt
            ON fcwt.sk_contract = fiwt.sk_contract
            AND fcwt.dt_reference = fiwt.dt_reference
    LEFT JOIN
        dw_collections_segmentation.fact_contract_features_timeline AS fcft
            ON fcft.sk_contract = fiwt.sk_contract
            AND fcft.dt_reference = fiwt.dt_reference
    WHERE
        fiwt.dt_reference = CURRENT_DATE()
        AND fiwt.invoice_status = 'open'
        AND fiwt.invoice_type = 'monthly'
        AND fiwt.contract_status = 'Ativo'
        AND fiwt.invoice_delay_t1 <= 0
),
/* Communication segment of each eligible invoice. The A/B/T prefixes encode decreasing risk
and are load-bearing: the deduplication below sorts on this string to keep the riskiest
segment per person. A1 isolates contracts already in delay but under an ongoing deal (T1 on
time, T2 contaminated), which need a different tone from A2. B1 and B2 are contracts with no
delay but with a known friction (condominium items in the bill, or a repeated late-payment
history), and T is the clean payer who only needs a plain reminder. */
invoice_segment AS (
    SELECT
        omi.sk_contract,
        omi.sk_invoice,
        omi.due_amount,
        omi.dt_due,
        omi.days_to_due,
        CASE
            WHEN omi.max_delay_contaminated_contract_t1 <= 0
                AND omi.max_delay_contaminated_contract_t2 > 0
                THEN 'A1 - DELAY CONTRACT - ONGOING-DEAL'
            WHEN omi.max_delay_contaminated_contract_t2 > 0
                THEN 'A2 - DELAY CONTRACT OTHER SEGMENTS'
            WHEN omi.has_bill_item_condominio
                THEN 'B1 - CURRENT CONTRACT WITH CONDO'
            WHEN omi.n_days_over1_t2_l180 > 3
                THEN 'B2 - CURRENT CONTRACT NOT-GOOD-PAYER HISTORY'
            ELSE 'T - PERFECT CURRENT'
        END AS segment
    FROM
        open_monthly_invoice AS omi
),
-- Active contract portfolio of each user on the snapshot date, exploded to one row per
-- contract so every eligible invoice can be attributed back to the user who is billed for it.
user_contract AS (
    SELECT
        fuwt.sk_user,
        fuwt.dt_reference,
        fuwt.max_delay_contaminated_contract_t2 AS user_level_delay,
        contract_element AS sk_contract
    FROM
        dw_collection_ai_agents.fact_user_wallet_timeline AS fuwt
    LATERAL VIEW EXPLODE(fuwt.contracts) exploded_contracts AS contract_element
    WHERE
        fuwt.dt_reference = CURRENT_DATE()
        AND fuwt.active_contracts > 0
),
-- Resolve the person UUID, which is the key Salesforce Marketing Cloud addresses the message
-- to. Users without a UUID cannot be contacted, so they are dropped from the snapshot.
user_person AS (
    SELECT
        uc.sk_user,
        uc.sk_contract,
        uc.dt_reference,
        uc.user_level_delay,
        du.uuid_person
    FROM
        user_contract AS uc
    INNER JOIN
        dw_public.dim_user AS du
            ON du.sk_user = uc.sk_user
    WHERE
        du.uuid_person IS NOT NULL
),
/* Collapse to one row per person. A person can hold several eligible invoices across
contracts; the message must be single, so keep the invoice in the riskiest segment (the codes
sort A1 < A2 < B1 < B2 < T). Ties are broken by the latest due date and then by the highest
invoice id, which makes the snapshot reproducible instead of dependent on scan order. */
person_segment_ranked AS (
    SELECT
        up.sk_user,
        up.sk_contract,
        up.uuid_person,
        up.dt_reference,
        up.user_level_delay,
        seg.sk_invoice,
        seg.segment,
        seg.days_to_due,
        seg.due_amount,
        seg.dt_due,
        ROW_NUMBER() OVER (
            PARTITION BY up.uuid_person
            ORDER BY seg.segment ASC, seg.dt_due DESC, seg.sk_invoice DESC
        ) AS rn_person_segment
    FROM
        user_person AS up
    INNER JOIN
        invoice_segment AS seg
            ON seg.sk_contract = up.sk_contract
)
/* Final snapshot: the elected invoice of each person, restricted to invoices due on the
standard due date of their month. The restriction is applied after the deduplication on
purpose — a person whose riskiest invoice sits on a customised due date leaves the wave
entirely rather than being reminded about a lower-priority invoice. */
SELECT
    psr.sk_user,
    psr.sk_contract,
    psr.sk_invoice,
    psr.uuid_person,
    psr.segment,
    psr.user_level_delay,
    psr.days_to_due,
    ABS(psr.due_amount) AS due_amount,
    psr.dt_reference,
    psr.dt_due,
    sdd.dt_due AS dt_standard_due,
    NOW() AS ts_load
FROM
    person_segment_ranked AS psr
INNER JOIN
    standard_due_date AS sdd
        ON sdd.dt_month = DATE(DATE_TRUNC('MONTH', psr.dt_due))
        AND sdd.dt_due = psr.dt_due
WHERE
    psr.rn_person_segment = 1
