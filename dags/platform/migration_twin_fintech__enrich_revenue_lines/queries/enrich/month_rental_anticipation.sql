WITH recurrence_acceptance AS (
    SELECT
        id_contract,
        id,
        ts_created,
        ts_accepted,
        ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY ts_accepted) AS nbr_transactions_accepted
    FROM
        datalake_fastforward_clean.anticipation
    WHERE
        ts_accepted IS NOT NULL
    ),
contract_first_last_accepted AS (
    SELECT
        id_contract,
        MIN(ts_accepted) AS ts_first_accepted,
        MAX(ts_accepted) AS ts_last_accepted
    FROM
        datalake_fastforward_clean.anticipation
    WHERE
        ts_accepted IS NOT NULL
    GROUP BY 1
    ),
invoice_entries AS (
    SELECT
        ies.id_contract,
        ies.id_invoice,
        ri.accrual_year_month,
        dddue.date AS dt_due,
        ies.brl_entry_due_amount,
        ies.brl_entry_paid_amount,
        ies.ts_created,
        i.payment_status,
        ddpaid.date AS dt_paid,
        ie.from_account_type,
        ie.to_account_type,
        ie.entry_type
    FROM
        datalake_invoice.invoice_entries AS ies
    INNER JOIN
        datalake_retsuko.invoice_entry AS ie
            ON ies.id = ie.id
    INNER JOIN
        datalake_retsuko.invoice_info AS i
            ON ies.id_invoice = i.id_invoice
    LEFT JOIN
        datalake_retsuko.invoice ri
            ON i.id_invoice = ri.id_external
    LEFT JOIN
        datalake_quintoandar.aux_date AS dddue
            ON dddue.id_date = ies.id_due_date
    LEFT JOIN
        datalake_quintoandar.aux_date AS ddpaid
            ON ddpaid.id_date = ies.id_paid_date
    WHERE
        from_account_type IN ('landlord','contract')
        AND to_account_type IN ('contract','landlord')
        AND entry_type IN ('rental anticipation fee','rental anticipation')
        AND i.payment_status NOT IN ('canceled')
    ),
anticipation_fee AS (
  SELECT
        id_contract,
        id_invoice,
        accrual_year_month,
        MAX(dt_due) AS dt_due_fee,
        MAX(CASE
                WHEN payment_status = 'not payable' THEN dt_due
                ELSE dt_paid
            END) AS dt_paid_fee,
        MAX(ts_created) AS ts_created,
        SUM(brl_entry_due_amount) AS fee_brl_entry_due_amount,
        SUM(CASE
                WHEN payment_status = 'not payable' THEN brl_entry_due_amount
                ELSE brl_entry_paid_amount
            END) AS fee_brl_entry_paid_amount
    FROM
        invoice_entries
    WHERE
        entry_type = 'rental anticipation fee'
    GROUP BY 1,2,3
    ),
anticipation_amount AS (
    SELECT
        id_contract,
        id_invoice,
        accrual_year_month,
        MAX(ts_created) AS ts_created,
        SUM(brl_entry_due_amount) AS amount_brl_entry_due_amount,
        SUM(CASE
                WHEN payment_status = 'not payable' THEN brl_entry_due_amount
                ELSE brl_entry_paid_amount
            END) AS amount_brl_entry_paid_amount
    FROM
        invoice_entries
    WHERE
        entry_type = 'rental anticipation'
        AND payment_status IN ('open','paid','not payable') -- para não pegar os cancelados
    GROUP BY 1,2,3
    )
SELECT
DISTINCT
    a.id AS id_mra,
    c.id_external AS id_contract_ebdb,
    ra.nbr_transactions_accepted,
    a.amount AS prod_theorical_amount,
    a.fee AS prod_theorical_fee,
    ABS(aa.amount_brl_entry_due_amount) AS invoice_theorical_amount,
    af.fee_brl_entry_due_amount AS invoice_theorical_fee,
    ABS(aa.amount_brl_entry_paid_amount) AS invoice_paid_amount,
    af.fee_brl_entry_paid_amount AS invoice_paid_fee,
    af.accrual_year_month,
    DATE(a.ts_created) AS dt_created,
    DATE(a.ts_accepted) AS dt_accepted,
    DATE(fla.ts_first_accepted) AS dt_first_accepted,
    af.dt_due_fee,
    af.dt_paid_fee
FROM
    datalake_fastforward_clean.anticipation AS a
INNER JOIN
    datalake_fastforward_clean.contract AS c
        ON a.id_contract = c.id
INNER JOIN
    recurrence_acceptance AS ra
        ON a.id = ra.id
INNER JOIN
    contract_first_last_accepted AS fla
        ON a.id_contract = fla.id_contract
LEFT JOIN
    anticipation_fee AS af
        ON af.id_contract = c.id_external
        AND DATE_FORMAT(a.dt_reference, 'yyyyMM') = af.accrual_year_month
LEFT JOIN
    anticipation_amount AS aa
        ON aa.id_contract = c.id_external
        AND DATE(aa.ts_created) = DATE(a.ts_accepted)
