WITH bank_statement AS (
    SELECT 
        CASE 
            WHEN LENGTH(TRIM(ext.origin_complement)) > 26 THEN ext.origin_complement 
            ELSE LPAD(REGEXP_REPLACE(ext.origin_complement, '^0+', ''), 8, '0') 
        END AS company_use, 
        CASE 
            WHEN LENGTH(TRIM(ext.origin_complement)) > 26 THEN 'PIX_ACTIVATION' 
            ELSE 'PIX_COLLECTION' 
        END AS type_transaction,
        ext.amount_value AS paid_amount,
        DATE(ext.date_accounting) as dt_paid
    FROM 
        datalake_itau_statements_clean.statement_879200494588 ext 
    WHERE 
        ext.operation IN ('C') 
        AND ext.origin_operation IN ('PIX_RECEPCAO')
), 

francesinha as (
  SELECT 
    CASE
      WHEN LENGTH(TRIM(ccrv2.document_number)) > 0 THEN TRIM(REPLACE(ccrv2.document_number, 'C!', '')) 
      ELSE ccrv2.our_number 
    END AS company_use, 
    CASE 
      WHEN LENGTH(TRIM(ccrv2.document_number)) > 0 THEN 'BOLETO_DIRECT_BILLING' 
      ELSE 'BOLETO_COLLECTION' 
    END AS type_transaction, 
    ccrv2.net_amount AS paid_amount, 
    ccrv2.dt_credit as dt_paid
  FROM 
    datalake_nexxera_clean.cnab_charges_recupera_velo_2 ccrv2 
  WHERE 
    ccrv2.occurrence_code IN ('06') 
    AND ccrv2.bank_account IN ('04945')
),

bank_union AS (  
  SELECT *
  FROM 
    bank_statement

  UNION ALL 

  SELECT * 
  FROM 
    francesinha
),

payment_systems AS (
    SELECT 
        c.id_transaction AS our_number,
        substr(c.id_transaction, 1, 30) AS company_use,
        c.amount AS paid_amount,
        DATE(c.ts_updated) AS dt_paid
    FROM 
        datalake_pixar_clean.charge c
    WHERE 
        c.status IN ('paid')


    UNION ALL

    SELECT
        i.id_external AS our_number,
        SUBSTR(n.id, 1, 30) AS company_use,
        i.total_amount AS pix_amount,
        DATE(p.dt_paid) AS dt_paid
    FROM
        datalake_trato_feito_clean.installment i 
    LEFT JOIN
        datalake_trato_feito_clean.negotiation n 
            ON n.id = i.id_negotiation 
    LEFT JOIN
        datalake_trato_feito_clean.payment p
            ON p.id_installment = i.id

    UNION ALL 

    SELECT
        CAST(br.id AS STRING) AS our_number,
        CAST(br.id AS STRING) AS company_use,
        br.total_amount AS paid_amount,
        DATE(b.ts_paid) AS dt_paid
    FROM
        datalake_rental_guarantee_platform_clean.billing_report br 
    LEFT JOIN 
        datalake_rental_guarantee_platform_clean.bill b 
            ON b.id = br.id_bill
),

sap AS (
    SELECT
        id_transaction,
        CASE
            WHEN regexp_like(replace(accounting_rule , '+','-'), 'baixa-contas-receber:conta-banco-cash-in|baixa-conta-receber:valores-receber-imobiliaria-conta-banco-cash-in')
            THEN id_finance_entity 
            ELSE id_external_payment 
        END AS company_use, 
        account_number, 
        ROUND(SUM(debit_credit), 2) AS paid_amount,
        dt_reference AS dt_paid
    FROM
        datalake_pas.ledger 
    WHERE
        account_number IN ('11035X')
        AND source_client IN ('rental-guarantee-pla')
    GROUP BY
        1,2,3,5
)

SELECT 
    bu.company_use,
    s.id_transaction AS id_sap_transaction,
    bu.type_transaction,
    '49458-8' AS bank_account,
    bu.paid_amount AS bank_paid_amount,
    p.paid_amount AS charge_amount,
    s.paid_amount AS sap_paid_amount,
    IF(p.our_number IS NOT NULL AND p.paid_amount = bu.paid_amount AND p.dt_paid = bu.dt_paid, TRUE, FALSE) AS is_charge_concilied,
    IF(s.company_use IS NOT NULL AND s.paid_amount = bu.paid_amount AND s.dt_paid = bu.dt_paid, TRUE, FALSE) AS is_sap_concilied,
    bu.dt_paid AS dt_bank_paid,
    p.dt_paid AS dt_charge_paid,
    s.dt_paid AS dt_sap_paid
FROM 
    bank_union AS bu
LEFT JOIN 
    payment_systems AS p
        ON p.our_number = bu.company_use
LEFT JOIN 
    sap AS s 
        ON s.company_use = p.company_use
WHERE 
    bu.dt_paid >= CURRENT_DATE - 120