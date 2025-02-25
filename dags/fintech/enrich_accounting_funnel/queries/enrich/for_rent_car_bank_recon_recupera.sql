WITH francesinha AS (
    SELECT
        CAST(SUBSTRING(UPPER(our_number), 1, LENGTH(our_number) - 1) AS INTEGER) AS our_number,
        dt_credit AS dt_paid,
        SUM(net_amount) AS amount
    FROM
        datalake_nexxera.cnab_charges_recupera
    WHERE
        bank_account = '04526'
        AND occurrence_code = '06'
        AND our_number IS NOT NULL
        AND TRIM(our_number) != ''
        AND dt_credit >= current_date - 180
    GROUP BY
        1,2

    UNION

    SELECT 
      CASE WHEN ext.origin_complement like '%BL%' THEN regexp_replace(
        substring(ext.origin_complement, 20, 20), 
        '^0+', 
        ''
      ) ELSE regexp_replace(ext.origin_complement, '^0+', '') END AS our_number,
        DATE(ext.date_accounting) AS dt_paid,
        ext.amount_value AS amount
    FROM 
        datalake_itau_statements_clean.statement_879200452685 ext 
    WHERE 
        ext.operation in ('C') 
        AND ext.literal_code in ('9489')
),

sap AS (
    SELECT DISTINCT
        id_business_entity,
        COALESCE(CAST(SPLIT_PART(id_external_payment, '|', 2) AS INTEGER), id_external_payment) AS our_number,
        dt_tax AS dt_paid,
        SUM(debit_credit) AS amount
    FROM
        datalake_pas.ledger
    WHERE
        (
            (
                dt_reference >= DATE('2024-01-01')
                AND account_number IN ('11004X', '11036X')
            )
            OR
            (
                dt_reference < DATE('2024-01-01')
                AND account_number = '11102.01.11'
            )
        )
        AND id_finance_entity <> ''
        AND id_finance_entity IS NOT NULL
        AND id_external_payment IS NOT NULL
        AND TRIM(id_external_payment) != ''
        AND dt_tax >= current_date - 180
    GROUP BY
        1,2,3
    HAVING
        SUM(debit_credit) != 0
),

checkout AS (
    SELECT
        NULLIF(b.our_number, '') AS company_use,
        NULLIF(b.id_business_entity, '') AS id_contract,
        b.id_finance_entity AS id_invoice,
        DATE(b.ts_paid - interval '3' hour) AS ts_paid,
        b.paid_amount,
        b.payer_name,
        NULLIF(CAST(TRIM(b.our_number) AS INTEGER), '') AS our_number
    FROM
        datalake_checkout_clean.boleto b
    LEFT JOIN
        dw_public.dim_date dd
            ON b.ts_paid = dd.date
    WHERE
        b.requester_name = 'trato-feito'
        AND b.id NOT IN (5855, 5856, 5857)
        AND b.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
        AND (b.beneficiary_account = '45268' OR b.beneficiary_account IS NULL)
        AND b.ts_paid >= current_date - 180
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY b.your_number ORDER BY b.ts_paid DESC) = 1
),

checkout_union AS (
    SELECT
        CAST(UPPER(vc.our_number) AS INTEGER) AS our_number,
        vc.paid_amount AS amount,
        DATE(dd.next_brz_fintech_business_day) AS dt_paid
    FROM
        checkout vc
    LEFT JOIN
        dw_public.dim_date dd
            ON vc.ts_paid = dd.date
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY our_number, paid_amount ORDER BY CASE WHEN id_invoice IS NOT NULL THEN company_use ELSE our_number END DESC) = 1
    
    UNION 

    SELECT
      b.our_number, 
      b.paid_amount AS amount,
      COALESCE(dt_credit, DATE(ts_paid)) AS dt_paid
    FROM 
      datalake_checkout_clean.bolecode b
    WHERE
        b.requester_name = 'trato-feito'
        AND b.id NOT IN (5855, 5856, 5857)
        AND b.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
        AND (b.beneficiary_account = '45268' OR b.beneficiary_account IS NULL)
        AND COALESCE(dt_credit, DATE(ts_paid)) >= current_date - 180    
),

df_all AS (
    SELECT DISTINCT
        our_number
    FROM
        checkout_union
    UNION ALL
    SELECT DISTINCT
        our_number
    FROM
        sap
    UNION ALL
    SELECT DISTINCT
        our_number
    FROM
        francesinha
),

df AS (
    SELECT DISTINCT
        cs.our_number AS id_our_number,
        f.amount AS bank_amount,
        vc.amount AS checkout_amount,
        s.amount AS sap_amount,
        IF(f.our_number IS NULL, 'not recorded', 'ok') AS status_bank,
        CASE
            WHEN f.amount = vc.amount AND f.dt_paid = DATE(vc.dt_paid) THEN 'ok'
            WHEN f.amount != vc.amount AND f.dt_paid != DATE(vc.dt_paid) THEN 'recorded on the wrong date and value'
            WHEN f.amount != vc.amount AND f.dt_paid = DATE(vc.dt_paid) THEN 'recorded on the wrong value'
            WHEN f.amount = vc.amount AND f.dt_paid != DATE(vc.dt_paid) THEN 'recorded on the wrong date'
            WHEN vc.our_number IS NULL THEN 'not recorded'
            ELSE 'not ok'
        END AS status_checkout,
        CASE
            WHEN f.amount = s.amount AND f.dt_paid = DATE(s.dt_paid) THEN 'ok'
            WHEN f.amount != s.amount AND f.dt_paid != DATE(s.dt_paid) THEN 'recorded on the wrong date and value'
            WHEN f.amount != s.amount AND f.dt_paid = DATE(s.dt_paid) THEN 'recorded on the wrong value'
            WHEN f.amount = s.amount AND f.dt_paid != DATE(s.dt_paid) THEN 'recorded on the wrong date'
            WHEN s.our_number IS NULL THEN 'not recorded'
            ELSE 'not ok'
        END AS status_sap,
        f.dt_paid AS dt_bank_paid,
        vc.dt_paid AS dt_checkout_paid,
        s.dt_paid AS dt_sap_paid
    FROM
        df_all cs
    LEFT JOIN
        francesinha f
            on f.our_number = cs.our_number
    LEFT JOIN
        checkout_union vc
            ON vc.our_number = cs.our_number
    LEFT JOIN
        sap s
            on cs.our_number = s.our_number
    WHERE
        cs.our_number IS NOT NULL
    AND
        (
            DATE(f.dt_paid) >= '2024-01-01' OR
            DATE(vc.dt_paid) >= '2024-01-01' OR
            DATE(s.dt_paid) >= '2024-01-01'
    )
)

SELECT
    id_our_number,
    bank_amount,
    checkout_amount,
    sap_amount,
    status_bank,
    status_checkout,
    status_sap,
    IF(status_bank = 'ok' AND status_sap = 'ok', TRUE, FALSE) AS is_reconciled,
    dt_bank_paid,
    dt_checkout_paid,
    dt_sap_paid
FROM
    df