SELECT
    ccp.id AS id_ccp,
    c.id_external AS id_contract_ebdb,
    ccp.status,
    ccp.brand_name,
    CASE
        WHEN ccp.installments = 1 THEN 'sight'
    	ELSE 'installments'
    END type_paid,
    ccp.installments,
    i.due_amount AS invoice_theorical_amount,
    i.paid_amount AS invoice_paid_amount,
    (paid_amount + due_amount) AS invoice_paid_fee,
    ROUND(charged_amount * (CASE
                        WHEN ccp.installments = 1 THEN 0.012
                        WHEN ccp.installments <= 6 THEN 0.016
                        WHEN ccp.installments <= 12 THEN 0.019
                        ELSE NULL END), 2) AS acquirer_cost,
    ROUND(charged_amount * (1- CASE
                            WHEN installments = 1 THEN 0.012
                            WHEN installments <= 6 THEN 0.016
                            WHEN installments <= 12 THEN 0.019
                            ELSE NULL END) * 0.006 * (installments+1)/2, 2) AS advance_cost,
    i.accrual_year_month,
    DATE(ccp.ts_created) AS dt_ccp_created,
    DATE(i.ts_due) AS dt_due,
    DATE(i.ts_paid) AS dt_paid
FROM
    datalake_retsuko_clean.credit_card_payment AS ccp
INNER JOIN
    datalake_retsuko.invoice AS i
        ON ccp.id_invoice = i.id
INNER JOIN
    datalake_retsuko_clean.contract AS c
        ON i.id_contract = c.id
