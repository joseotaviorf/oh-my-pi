WITH recurrence_signed AS (
    SELECT
        id_contract,
        id,
        ts_created,
        row_number() OVER(PARTITION BY id_contract ORDER BY ts_created) AS nbr_transactions_signed
    FROM 
        datalake_fastforward_clean.long_term_anticipation 
    WHERE 
        ts_signed IS NOT NULL 
    ),
invoice_entries AS (
    SELECT
        ies.id_contract,
        ies.id_invoice,
        ri.accrual_year_month,
        dd_due.date AS dt_due,
        dd_paid.date AS dt_paid,
        MAX(ies.ts_created) AS ts_created,
        SUM(ies.brl_entry_due_amount) AS amount_brl_entry_due_amount,
        SUM(CASE
                WHEN i.payment_status = 'not payable' THEN ies.brl_entry_due_amount
                ELSE ies.brl_entry_paid_amount
            END) AS amount_brl_entry_paid_amount
    FROM 
        datalake_invoice.invoice_entries AS ies
    INNER JOIN 
        datalake_retsuko.invoice_entry AS ie
            ON ies.id = ie.id
    INNER JOIN 
        datalake_retsuko.invoice AS i
            ON ies.id_invoice = i.id_invoice
    LEFT JOIN
        datalake_retsuko_clean.invoice ri 
            ON i.id_invoice = ri.id_external
    LEFT JOIN
        datalake_quintoandar.aux_date AS dd_due
            ON dd_due.id_date = ies.id_due_date  
    LEFT JOIN
        datalake_quintoandar.aux_date AS dd_paid
            ON dd_paid.id_date = ies.id_paid_date  
    WHERE
        ie.from_account_type IN ('landlord','contract')
        AND ie.to_account_type IN ('contract','landlord')
        AND ie.entry_type IN ('installment lra')
    GROUP BY 1,2,3,4,5
    )
SELECT
    lra.id AS id_lra,
    c.id_external AS id_contract_ebdb,
    lio.months_anticipated,
    li.installment_number as installment,
    lio.installments AS total_installments,
    lra.total_rent,
    rs.nbr_transactions_signed,
    COALESCE((li.amount + li.interest_value),lra.installment_value) AS prod_theorical_amount, 
    li.interest_value AS prod_theorical_fee,
    ie.amount_brl_entry_due_amount AS invoice_theorical_amount,
    ie.amount_brl_entry_paid_amount AS invoice_paid_amount,
    DATE_FORMAT(ADD_MONTHS(DATE_TRUNC('month', li.ts_expected_due), -1), 'yyyyMM') AS accrual_year_month,
    CASE
        WHEN ie.amount_brl_entry_due_amount IS NOT NULL 
            THEN  li.interest_value 
    END AS invoice_theorical_fee,
    CASE
        WHEN ie.amount_brl_entry_paid_amount IS NOT NULL 
            THEN li.interest_value 
    END AS invoice_paid_fee,    
    ie.dt_due,
    ie.dt_paid,
    DATE(lra.ts_created) AS dt_created,
    DATE(lra.ts_signed) AS dt_signed
FROM 
    datalake_fastforward_clean.long_term_anticipation AS lra
INNER JOIN 
    datalake_fastforward_clean.contract AS c
        ON lra.id_contract = c.id
INNER JOIN
    datalake_fastforward_clean.lra_installment_option AS lio
        ON lra.id_installment_option = lio.id
INNER JOIN
    datalake_fastforward_clean.lra_installment AS li
        ON lra.id = li.id_long_term_anticipation
INNER JOIN 
    recurrence_signed AS rs
        ON lra.id = rs.id
LEFT JOIN
    invoice_entries ie
        ON ie.id_contract = c.id_external
        AND ie.accrual_year_month = DATE_FORMAT(ADD_MONTHS(DATE_TRUNC('month', li.ts_expected_due), -1), 'yyyyMM')