WITH contract_last_updated AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_owner_fees_clean.contract
    GROUP BY 1
    ),
brokerage_last_updated AS (
    SELECT
        bf.id,
        MAX(bf.ts_updated) AS ts_last_updated
    FROM
        datalake_owner_fees_clean.contract_brokerage_fee bf
    INNER JOIN 
        datalake_owner_fees_clean.contract AS c
            ON c.id = bf.id_contract
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
        datalake_retsuko.invoice AS i
            ON ies.id_invoice = i.id_invoice
    LEFT JOIN
        datalake_retsuko_clean.invoice ri 
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
        AND entry_type IN ('brokerage installment', 'brokerage installment fee')
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
        entry_type = 'brokerage installment fee'
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
        entry_type = 'brokerage installment'
        AND payment_status IN ('open','paid','not payable') -- para não pegar os cancelados
    GROUP BY 1,2,3
    ), 
brokerage_finance AS (
    SELECT
        bfi.id AS id_bfi,
        c.id_external,
        bfi.installment_number,
        bfi.premium_fee,
        bfi.down_payment,
        c.real_state_agent_share,
        c.rent,
        ((c.rent*bfi.premium_fee)/bfi.installment_number) AS monthly_5a_revenue,
        DATE_TRUNC('month', c.dt_validity) AS month_validity_start,
        ADD_MONTHS(DATE_TRUNC('month', c.dt_validity), bfi.installment_number) AS month_validity_end,
        bfi.ts_created
    FROM 
        datalake_owner_fees_clean.contract_brokerage_fee AS bfi
    INNER JOIN 
        datalake_owner_fees_clean.contract AS c
            ON c.id = bfi.id_contract
    INNER JOIN
        contract_last_updated AS clu
            ON c.id = clu.id
    INNER JOIN
        brokerage_last_updated AS blu
            ON bfi.id = blu.id
    WHERE
        c.ts_updated = clu.ts_last_updated
        AND bfi.ts_updated = blu.ts_last_updated
        AND installment_number > 0
    )
SELECT 
DISTINCT
    bf.id_bfi,   
    bf.id_external AS id_contract_ebdb,
    (bf.rent * (1 - COALESCE(c.agent_brokerage_share, bf.real_state_agent_share)) / bf.installment_number) AS prod_theorical_amount,
    (bf.rent * bf.premium_fee / bf.installment_number) AS prod_theorical_fee,
    ABS(aa.amount_brl_entry_due_amount) AS invoice_theorical_amount,
    ABS(aa.amount_brl_entry_paid_amount) AS invoice_paid_amount,
    af.fee_brl_entry_due_amount AS invoice_theorical_fee,
    af.fee_brl_entry_paid_amount AS invoice_paid_fee,
    MONTHS_BETWEEN(dd.month_start, bf.month_validity_start, TRUE) AS installment,
    bf.installment_number AS total_installments,
    bf.premium_fee,
    COALESCE(c.agent_brokerage_share, bf.real_state_agent_share) AS real_state_agent_share,
    af.accrual_year_month,
    DATE(bf.ts_created) AS dt_bf_created,
    af.dt_due_fee,
    af.dt_paid_fee
FROM
    brokerage_finance AS bf
INNER JOIN
    dw_public.dim_date AS dd
        ON dd.month_start BETWEEN bf.month_validity_start AND bf.month_validity_end
LEFT JOIN
    anticipation_fee AS af
        ON af.id_contract = bf.id_external 
        AND DATE_FORMAT(dd.month_start, 'yyyyMM') = af.accrual_year_month
LEFT JOIN
    anticipation_amount AS aa
        ON aa.id_contract = bf.id_external 
        AND DATE_FORMAT(dd.month_start, 'yyyyMM') = aa.accrual_year_month
LEFT JOIN
    datalake_ebdb_clean.contract c
        ON c.id = bf.id_external
WHERE
    MONTHS_BETWEEN(dd.month_start, bf.month_validity_start, TRUE) > 0
    AND month_start <= DATE_TRUNC('month',current_date)