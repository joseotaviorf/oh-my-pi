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
    i.accrual_year_month,
    DATE(ccp.ts_created) AS dt_ccp_created,
    DATE(i.ts_due) AS dt_due,
    DATE(i.ts_paid) AS dt_paid
FROM
    datalake_retsuko_clean.credit_card_payment AS ccp
INNER JOIN
    datalake_retsuko_clean.invoice AS i
        ON ccp.id_invoice = i.id
INNER JOIN 
    datalake_retsuko_clean.contract AS c
        ON i.id_contract = c.id