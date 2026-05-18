WITH 

francesinha_base AS (
    SELECT
        UPPER(REPLACE(REPLACE(REGEXP_REPLACE(document_number, '^0000', ''), 'C!', ''), 'C|', '')) AS company_use,
        document_number AS bank_number,
        bank_account,
        dt_credit AS dt_paid,
        SUM(net_amount) AS amount
    FROM
        datalake_nexxera.cnab_charges
    WHERE
        bank_account = '03922'
        AND occurrence_code = '06'
        AND document_number IS NOT NULL
        AND TRIM(document_number) != ''
    GROUP BY
        1,2,3,4
    
    UNION ALL 

    SELECT
        CASE
            WHEN ext.origin_complement like '%BL%' THEN regexp_replace(
            substring(ext.origin_complement, 20, 20),
            '^0+',
            '')
            ELSE regexp_replace(ext.origin_complement, '^0+', '')
        END AS company_use,
        ext.origin_complement AS bank_number,
        '03922' AS bank_account,
        DATE(ext.date_accounting) AS dt_paid,
        ext.amount_value AS amount
    FROM
        datalake_itau_statements_clean.statement_067000392216 ext
    WHERE
        ext.operation in ('C')
        AND ext.literal_code in ('9489')
),

francesinha AS (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY company_use ORDER BY dt_paid) AS rn
    FROM francesinha_base
),

seu_barriga_base AS (
    SELECT
        id_external AS id_invoice,
        id_original_invoice_external,
        UPPER(REPLACE(payment_company_use_number, 'C!', '')) AS company_use,
        payment_status,
        status,
        paid_via,
        reason,
        paid_amount AS amount,
        IF (LOWER(paid_via) = 'checkout-bolecode-qrcode', DATE(ts_paid), dd.next_brz_fintech_business_day) AS dt_paid
    FROM
        datalake_retsuko.invoice
    LEFT JOIN
        dw_public.dim_date dd
            ON invoice.ts_paid = dd.date
    WHERE
        payment_company_use_number IS NOT NULL
        AND TRIM(payment_company_use_number) != ''
        AND lower(reason) NOT IN ('negotiation-5a', 'negotiation-recupera')
        AND lower(paid_via) IN ('cnab', 'checkout-boleto', 'checkout-bolecode-qrcode', 'checkout-bolecode-barcode')
        AND due_amount <= 0
        AND payment_status != 'canceled'
        AND status != 'canceled'
        AND country_code = 'BR'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_invoice, payment_company_use_number ORDER BY ts_created DESC) = 1
),

seu_barriga AS (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY company_use ORDER BY dt_paid) AS rn
    FROM seu_barriga_base
),

seu_barriga_sap AS (
    SELECT
        id_external AS id_invoice,
        id_original_invoice_external,
        UPPER(payment_company_use_number) AS company_use,
        payment_status,
        status,
        paid_via,
        reason,
        paid_amount AS amount,
        IF (LOWER(paid_via) = 'checkout-bolecode-qrcode', DATE(ts_paid), dd.next_brz_fintech_business_day) AS dt_paid
    FROM
        datalake_retsuko.invoice
    LEFT JOIN
        dw_public.dim_date dd
            ON invoice.ts_paid = dd.date
    WHERE
        payment_company_use_number IS NOT NULL
        AND TRIM(payment_company_use_number) != ''
        AND lower(paid_via) IN ('cnab', 'checkout-boleto', 'checkout-bolecode-qrcode', 'checkout-bolecode-barcode')
        AND due_amount <= 0
        AND payment_status != 'canceled'
        AND status != 'canceled'
        AND country_code = 'BR'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_invoice, payment_company_use_number ORDER BY ts_created DESC) = 1
),

sap_base AS (
    SELECT DISTINCT
        id_business_entity,
        id_finance_entity AS id_invoice,
        COALESCE(UPPER(REPLACE(REPLACE(id_external_payment, 'C!', ''), 'C|', '')), 
        UPPER(REPLACE(REPLACE(sb.company_use, 'C!', ''), 'C|', ''))) AS company_use,
        account_number,
        dt_tax AS dt_paid,
        SUM(debit_credit) AS amount,
        CONCAT_WS(', ', COLLECT_LIST(hash)) AS hash
    FROM
        datalake_pas.ledger AS l
    LEFT JOIN
        seu_barriga_sap AS sb
            ON l.id_finance_entity = sb.id_invoice
    WHERE
        (
            (
                dt_reference >= DATE('2024-01-01')
                AND account_number = '11004X'
            )
            OR
            (
                dt_reference < DATE('2024-01-01')
                AND account_number = '11102.01.11'
            )
        )
        AND id_finance_entity <> ''
        AND id_finance_entity IS NOT NULL
        AND NOT(id_external_payment IS NULL AND sb.company_use IS NULL)
        AND NOT(TRIM(id_external_payment) = '' AND sb.company_use IS NULL)
    GROUP BY
        1,2,3,4,5
    HAVING
        SUM(debit_credit) != 0
),

sap AS (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY company_use ORDER BY dt_paid) AS rn
    FROM sap_base
),

vans_checkout_union AS (
    SELECT
        NULLIF(b.your_number, '') AS company_use,
        b.id_finance_entity AS id_invoice,
        DATE(b.ts_paid) AS ts_paid,
        'BOLETO' AS payment_method,
        b.status AS payment_status,
        b.paid_amount,
        NULLIF(CAST(TRIM(b.our_number) AS INTEGER), '') AS our_number
    FROM
        datalake_checkout_clean.boleto b
    WHERE
        b.requester_name = 'seubarriga'
        AND b.id NOT IN (5855, 5856, 5857)
        AND b.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
        AND (b.beneficiary_account = '39221' OR b.beneficiary_account IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY b.your_number ORDER BY b.ts_paid DESC) = 1

    UNION ALL

    SELECT
        COALESCE(NULLIF(b.company_use, ''), NULLIF(b.document_number, '')) AS company_use,
        b.id_related_document AS id_invoice,
        DATE(b.dt_paid) AS ts_paid,
        'BOLETO' AS payment_method,
        UPPER(regexp_extract(b.status, '/(.*)', 1)) AS payment_status,
        b.paid_amount AS paid_amount,
        NULLIF(CAST(b.our_number AS INTEGER), '') AS our_number
    FROM
        datalake_vans_clean.boleto b
    WHERE
        b.status in (':boleto.status/paid', ':boleto.status/write-down-paid-requested')
        AND (b.id_bank_boleto = 1 OR b.id_bank_boleto IS NULL)
        AND (NULLIF(b.company_use, '') IS NOT NULL OR NULLIF(b.document_number, '') IS NOT NULL)
        AND LOWER(b.document_number) NOT LIKE 'f%'
        AND SUBSTRING(b.original_response, 24, 4) = 3922
    
    UNION ALL 

    SELECT
        NULLIF(b.our_number, '') AS company_use,
        o.id_finance_entity AS id_invoice,
        DATE(b.ts_paid) AS ts_paid,
        CASE
          WHEN c.paid_via = 'BARCODE' THEN 'BOLETO'
          WHEN c.paid_via = 'QRCODE' THEN 'PIX'
        END AS payment_method,
        b.status AS payment_status,
        b.paid_amount,
        NULLIF(b.our_number, '') AS our_number
    FROM
      datalake_checkout_clean.bolecode b
    INNER JOIN datalake_checkout_clean.charge c 
      ON c.id = b.id_charge
    INNER JOIN datalake_checkout_clean.order o 
      ON o.id = c.id_order
    WHERE
        b.requester_name = 'seubarriga'
        AND b.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
        AND (b.beneficiary_account = '39221' OR b.beneficiary_account IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY b.our_number ORDER BY b.ts_paid DESC) = 1
),

pre_vans_checkout AS (
    SELECT
        REPLACE(REPLACE(UPPER(REGEXP_REPLACE(vc.company_use, '^0000', '')), 'C!', ''), 'C]', '') AS company_use,
        vc.id_invoice,
        vc.payment_method,
        vc.payment_status,
        IF(vc.payment_method = 'PIX' AND dd.is_brz_fintech_business_day = TRUE, ts_paid, dd.next_brz_fintech_business_day) AS dt_paid,
        vc.paid_amount
    FROM
        vans_checkout_union vc
    LEFT JOIN
        dw_public.dim_date dd
            ON vc.ts_paid = dd.date
    WHERE
        UPPER(vc.company_use) NOT LIKE 'B%'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY our_number, paid_amount ORDER BY CASE WHEN id_invoice IS NOT NULL THEN company_use ELSE our_number END DESC) = 1
),

vans_checkout_base AS (
    SELECT
        company_use,
        id_invoice,
        payment_method,
        payment_status,
        dt_paid,
        SUM(paid_amount) AS amount
    FROM
        pre_vans_checkout vc
    GROUP BY 1,2,3,4,5
),

vans_checkout AS (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY company_use ORDER BY dt_paid) AS rn
    FROM vans_checkout_base
),

df_all AS (
    SELECT company_use, rn FROM seu_barriga
    UNION DISTINCT
    SELECT company_use, rn FROM vans_checkout
    UNION DISTINCT
    SELECT company_use, rn FROM sap
    UNION DISTINCT
    SELECT company_use, rn FROM francesinha
),

df AS (
    SELECT DISTINCT
        cs.company_use AS id_company_use,
        sb.id_invoice,
        s.hash,
        f.bank_number,
        f.bank_account AS bank_account_number,
        s.account_number AS sap_account_number,
        vc.payment_method,
        vc.payment_status,
        f.amount AS bank_amount,
        sb.amount AS retsuko_amount,
        vc.amount AS vans_checkout_amount,
        s.amount AS sap_amount,
        IF(f.company_use IS NULL, 'not recorded', 'ok') AS status_bank,
        CASE
            WHEN f.amount = vc.amount AND f.dt_paid = DATE(vc.dt_paid) THEN 'ok'
            WHEN f.amount != vc.amount AND f.dt_paid != DATE(vc.dt_paid) THEN 'recorded with a divergent date and value'
            WHEN f.amount != vc.amount AND f.dt_paid = DATE(vc.dt_paid) THEN 'recorded with a divergent value'
            WHEN f.amount = vc.amount AND f.dt_paid != DATE(vc.dt_paid) THEN 'recorded with a divergent date'
            WHEN vc.company_use IS NULL THEN 'not recorded'
            ELSE 'not ok'
        END AS status_vans_checkout,
        CASE
            WHEN f.amount = sb.amount AND (f.dt_paid = DATE(sb.dt_paid) OR f.dt_paid = DATE(sb.dt_paid)) THEN 'ok'
            WHEN f.amount != sb.amount AND f.dt_paid != DATE(sb.dt_paid) AND f.dt_paid != DATE(sb.dt_paid) THEN 'recorded with a divergent date and value'
            WHEN f.amount != sb.amount AND (f.dt_paid = DATE(sb.dt_paid) OR f.dt_paid = DATE(sb.dt_paid)) THEN 'recorded with a divergent value'
            WHEN f.amount = sb.amount AND f.dt_paid != DATE(sb.dt_paid) AND f.dt_paid != DATE(sb.dt_paid) THEN 'recorded with a divergent date'
            WHEN sb.company_use IS NULL THEN 'not recorded'
            ELSE 'not ok'
        END AS status_retsuko,
        CASE
            WHEN f.amount = s.amount AND f.dt_paid = DATE(s.dt_paid) THEN 'ok'
            WHEN f.amount != s.amount AND f.dt_paid != DATE(s.dt_paid) THEN 'recorded with a divergent date and value'
            WHEN f.amount != s.amount AND f.dt_paid = DATE(s.dt_paid) THEN 'recorded with a divergent value'
            WHEN f.amount = s.amount AND f.dt_paid != DATE(s.dt_paid) THEN 'recorded with a divergent date'
            WHEN s.company_use IS NULL THEN 'not recorded'
            ELSE 'not ok'
        END AS status_sap,
        f.dt_paid AS dt_bank_paid,
        sb.dt_paid AS dt_retsuko_paid,
        vc.dt_paid AS dt_vans_checkout_paid,
        s.dt_paid AS dt_sap_paid
    FROM
        df_all cs
    LEFT JOIN
        francesinha f
            ON f.company_use = cs.company_use AND f.rn = cs.rn
    LEFT JOIN
        vans_checkout vc
            ON vc.company_use = cs.company_use AND vc.rn = cs.rn
    LEFT JOIN
        seu_barriga sb
            ON sb.company_use = cs.company_use AND sb.rn = cs.rn
    LEFT JOIN
        sap s
            ON s.company_use = cs.company_use AND s.rn = cs.rn
    WHERE
        cs.company_use IS NOT NULL
    AND
        (
            DATE(f.dt_paid) >= current_date - 120 OR
            DATE(vc.dt_paid) >= current_date - 120 OR
            DATE(sb.dt_paid) >= current_date - 120 OR
            DATE(s.dt_paid) >= current_date - 120
    )
)

SELECT
    id_company_use,
    id_invoice,
    hash,
    bank_number,
    bank_account_number,
    sap_account_number,
    payment_method,
    payment_status,
    bank_amount,
    retsuko_amount,
    vans_checkout_amount,
    sap_amount,
    status_bank,
    status_retsuko,
    status_vans_checkout,
    status_sap,
    IF(status_bank = 'ok' AND status_vans_checkout = 'ok' AND status_retsuko = 'ok' AND status_sap = 'ok', TRUE, FALSE) AS is_reconciled,
    dt_bank_paid,
    dt_retsuko_paid,
    dt_vans_checkout_paid,
    dt_sap_paid
FROM
    df
