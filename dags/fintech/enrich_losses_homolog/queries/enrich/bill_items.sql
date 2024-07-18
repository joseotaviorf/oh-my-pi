WITH
dim_invoice_entry_snapshot AS (
    SELECT DISTINCT
        sk_invoice_entry,
        entry_type,
        year,
        month,
        day
    FROM
        dw_payment_snapshot.dim_invoice_entry_snapshot
)
SELECT
    fies.sk_invoice AS id_invoice,
    fies.sk_contract AS id_contract,
    dies.entry_type AS bill_item_name,
    CASE
        WHEN dies.entry_type IN ('condominium defaulting','condominium 5A paid', 'condominium usage') THEN 'CONDOMINIUM_DELIQUENCY'
        WHEN dies.entry_type IN ('early termination fee', 'early termination fee non protection') THEN 'EARLY_TERMINATION_FEE'
        WHEN dies.entry_type IN ('debit negotiation', 'collections negotiation') THEN 'NEGOTIATION'
        WHEN dies.entry_type IN ('rental','iptu', 'iptu adjustment', 'ipca rental', 'home insurance','service fee','condominium') THEN 'RENTAL_CORE'
        WHEN dies.entry_type IN ('residential protection 5A acquittance','residential protection 5A fund transfer', 'repair offboarding', 'repair ongoing', 'non protection 5a', 'repair work') THEN 'REPAIR'
        WHEN dies.entry_type IN ('fine and interest','property damage fine') THEN 'FINE'
        WHEN dies.entry_type IN ('light water or gas','utilities defaulting') THEN 'UTILITY_DELIQUENCY'
        WHEN dies.entry_type IN ('rental guarantee fee', 'pro guarantor 5A installment') THEN 'GUARANTEE_RENOVATION'
        ELSE 'UNCLASSIFIED'
    END AS bill_item_cluster_name,
    SUM(fies.brl_entry_due_amount) AS bill_item_due_amount,
    dd.month_end AS dt_closing
FROM
    dw_payment_snapshot.fact_invoice_entries_snapshot AS fies
LEFT JOIN
      dim_invoice_entry_snapshot AS dies
          ON dies.sk_invoice_entry = fies.sk_invoice_entry
          AND dies.year = fies.year
          AND dies.month = fies.month
          AND dies.day = fies.day
LEFT JOIN
      dw_public.dim_date dd
          ON dd.sk_date = BIGINT(DATE_FORMAT(DATEADD(MONTH, -1, fies.ts_snapshot), "yyyyMMdd"))
WHERE
      fies.sk_invoice <> -1
GROUP BY
      1,2,3,4,6
