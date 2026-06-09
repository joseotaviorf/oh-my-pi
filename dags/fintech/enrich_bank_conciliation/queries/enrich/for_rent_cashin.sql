WITH 
sap_entity AS (
    SELECT
        id_finance_entity,
        e.event,
        e.status,
        e.failed_reason,
        e.ts_created,
        e.id_sap_gateway_feature
    FROM  datalake_retsuko_clean.sap_entity e
    WHERE event = 'payment-accounting-entries'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity ORDER BY ts_created DESC) = 1
),
sap_gateway AS (
    SELECT
        f.id_finance_entity,
        s.id_feature,
        s.hash,
        s.type,
        s.status as sync_sap_job_status,
        w.status as sap_send_status,
        w.webhook_status as sap_processed_status,
        w.errors AS webhook_error
    FROM
        datalake_sap_gateway_clean.feature f
    LEFT JOIN
        datalake_sap_gateway_clean.sync_sap_job s
          ON f.id_feature = s.id_feature
    LEFT JOIN
        datalake_sap_gateway_clean.webhook_log w
          ON s.idoc = w.idoc
    WHERE
        s.erp_solution IN ('S4')
        AND s.type IN ('LCM')
        AND s.status NOT IN ('ignore', 'ignored')
        AND DATE(f.ts_created) >= DATE('2025-01-01')
),
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
    -- Source 1: Checkout boleto — CK/*C## use your_number; otherwise our_number (original behavior)
    SELECT
        COALESCE(
            CASE
                WHEN UPPER(TRIM(b.your_number)) LIKE 'CK%' THEN NULLIF(TRIM(b.your_number), '')
                WHEN TRIM(b.your_number) RLIKE '^[0-9]+C[0-9]+$' THEN NULLIF(TRIM(b.your_number), '')
                ELSE NULL
            END,
            NULLIF(TRIM(b.our_number), ''),
            NULLIF(REGEXP_REPLACE(SUBSTRING(TRIM(b.your_number), 20, 20), '^0+', ''), '')
        ) AS company_use,
        b.id_finance_entity AS id_invoice,
        DATE(b.ts_paid) AS ts_paid,
        'BOLETO' AS payment_method,
        b.status AS payment_status,
        b.paid_amount,
        COALESCE(
            NULLIF(CAST(TRIM(b.our_number) AS INTEGER), ''),
            NULLIF(CAST(REGEXP_REPLACE(SUBSTRING(TRIM(b.your_number), 20, 20), '^0+', '') AS INTEGER), '')
        ) AS our_number,
        'checkout_boleto' AS payment_source
    FROM
        datalake_checkout_clean.boleto b
    WHERE
        b.requester_name = 'seubarriga'
        AND b.id NOT IN (5855, 5856, 5857)
        AND b.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
        AND (b.beneficiary_account = '39221' OR b.beneficiary_account IS NULL)
        -- Bolecode supersedes boleto for the same our_number (avoids BOLETO row with due_amount vs PIX paid_amount)
        AND NOT EXISTS (
            SELECT 1
            FROM datalake_checkout_clean.bolecode bc
            WHERE
                bc.requester_name = b.requester_name
                AND bc.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
                AND NULLIF(TRIM(bc.our_number), '') IS NOT NULL
                AND NULLIF(TRIM(bc.our_number), '') = NULLIF(TRIM(b.our_number), '')
        )
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY b.your_number ORDER BY b.ts_paid DESC) = 1

    UNION ALL

    -- Source 2: Vans boleto — resolve BL barcodes with same substring rule as francesinha
    SELECT
        CASE
            WHEN UPPER(COALESCE(NULLIF(b.company_use, ''), NULLIF(b.document_number, ''))) LIKE 'CK%'
                OR COALESCE(NULLIF(b.company_use, ''), NULLIF(b.document_number, '')) RLIKE '^[0-9]+C[0-9]+$'
                THEN COALESCE(NULLIF(b.company_use, ''), NULLIF(b.document_number, ''))
            WHEN COALESCE(NULLIF(b.company_use, ''), NULLIF(b.document_number, '')) RLIKE '^[0-9]+$'
                THEN COALESCE(NULLIF(b.company_use, ''), NULLIF(b.document_number, ''))
            WHEN UPPER(COALESCE(NULLIF(b.company_use, ''), NULLIF(b.document_number, ''))) LIKE '%BL%'
                THEN NULLIF(
                    REGEXP_REPLACE(
                        SUBSTRING(TRIM(COALESCE(NULLIF(b.company_use, ''), NULLIF(b.document_number, ''))), 20, 20),
                        '^0+',
                        ''
                    ),
                    ''
                )
            ELSE COALESCE(NULLIF(b.company_use, ''), NULLIF(b.document_number, ''))
        END AS company_use,
        b.id_related_document AS id_invoice,
        DATE(b.dt_paid) AS ts_paid,
        'BOLETO' AS payment_method,
        UPPER(regexp_extract(b.status, '/(.*)', 1)) AS payment_status,
        b.paid_amount AS paid_amount,
        NULLIF(CAST(b.our_number AS INTEGER), '') AS our_number,
        'vans_boleto' AS payment_source
    FROM
        datalake_vans_clean.boleto b
    WHERE
        b.status in (':boleto.status/paid', ':boleto.status/write-down-paid-requested')
        AND (b.id_bank_boleto = 1 OR b.id_bank_boleto IS NULL)
        AND (NULLIF(b.company_use, '') IS NOT NULL OR NULLIF(b.document_number, '') IS NOT NULL)
        AND LOWER(b.document_number) NOT LIKE 'f%'
        AND SUBSTRING(b.original_response, 24, 4) = 3922
    
    UNION ALL 

    -- Source 3: Checkout bolecode — CK/*C## use your_number; else our_number (matches pre-fix behavior for BL cases)
    SELECT
        COALESCE(
            CASE
                WHEN UPPER(TRIM(b.your_number)) LIKE 'CK%' THEN NULLIF(TRIM(b.your_number), '')
                WHEN TRIM(b.your_number) RLIKE '^[0-9]+C[0-9]+$' THEN NULLIF(TRIM(b.your_number), '')
                ELSE NULL
            END,
            NULLIF(TRIM(b.our_number), ''),
            NULLIF(
                REGEXP_REPLACE(
                    SUBSTRING(TRIM(COALESCE(b.your_number, b.id_transaction)), 20, 20),
                    '^0+',
                    ''
                ),
                ''
            )
        ) AS company_use,
        o.id_finance_entity AS id_invoice,
        DATE(b.ts_paid) AS ts_paid,
        CASE
          WHEN c.paid_via = 'BARCODE' THEN 'BOLETO'
          WHEN c.paid_via = 'QRCODE' THEN 'PIX'
        END AS payment_method,
        b.status AS payment_status,
        b.paid_amount,
        COALESCE(
            NULLIF(CAST(TRIM(b.our_number) AS INTEGER), ''),
            NULLIF(
                CAST(
                    REGEXP_REPLACE(
                        SUBSTRING(TRIM(COALESCE(b.your_number, b.id_transaction)), 20, 20),
                        '^0+',
                        ''
                    ) AS INTEGER
                ),
                ''
            )
        ) AS our_number,
        'checkout_bolecode' AS payment_source
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
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(
                NULLIF(TRIM(b.our_number), ''),
                REGEXP_REPLACE(SUBSTRING(TRIM(COALESCE(b.your_number, b.id_transaction)), 20, 20), '^0+', '')
            )
            ORDER BY b.ts_paid DESC
        ) = 1
),

pre_vans_checkout_raw AS (
    SELECT
        REPLACE(REPLACE(UPPER(REGEXP_REPLACE(vc.company_use, '^0000', '')), 'C!', ''), 'C]', '') AS company_use,
        vc.id_invoice,
        vc.payment_method,
        vc.payment_status,
        vc.payment_source,
        vc.our_number,
        vc.ts_paid,
        IF(vc.payment_method = 'PIX' AND dd.is_brz_fintech_business_day = TRUE, vc.ts_paid, dd.next_brz_fintech_business_day) AS dt_paid,
        vc.paid_amount
    FROM
        vans_checkout_union vc
    LEFT JOIN
        dw_public.dim_date dd
            ON vc.ts_paid = dd.date
    WHERE
        -- Drop only unresolved BL barcodes; old B% filter removed (it dropped valid BL→our_number rows)
        vc.company_use IS NOT NULL
        AND TRIM(vc.company_use) != ''
        AND UPPER(vc.company_use) NOT LIKE 'BL%'
),

pre_vans_checkout AS (
    -- One row per company_use + dt_paid; prefer bolecode PIX over boleto duplicate
    SELECT
        company_use,
        id_invoice,
        payment_method,
        payment_status,
        dt_paid,
        paid_amount,
        our_number
    FROM
        pre_vans_checkout_raw
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY company_use, dt_paid
            ORDER BY
                CASE payment_source
                    WHEN 'checkout_bolecode' THEN 1
                    WHEN 'checkout_boleto' THEN 2
                    WHEN 'vans_boleto' THEN 3
                END,
                CASE
                    WHEN payment_method = 'PIX' THEN 0
                    WHEN payment_method = 'BOLETO' THEN 1
                    ELSE 2
                END,
                ts_paid DESC
        ) = 1
),

vans_checkout_base AS (
    SELECT
        company_use,
        id_invoice,
        payment_method,
        payment_status,
        dt_paid,
        our_number,
        paid_amount AS amount
    FROM
        pre_vans_checkout
),

vans_checkout AS (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY company_use ORDER BY dt_paid) AS rn
    FROM vans_checkout_base
),

-- Join keys: company_use and our_number (covers BL bank rows keyed by numeric our_number)
vans_checkout_for_join AS (
    SELECT
        company_use AS join_key,
        company_use,
        id_invoice,
        payment_method,
        payment_status,
        dt_paid,
        amount,
        rn
    FROM
        vans_checkout

    UNION ALL

    SELECT
        CAST(our_number AS STRING) AS join_key,
        company_use,
        id_invoice,
        payment_method,
        payment_status,
        dt_paid,
        amount,
        rn
    FROM
        vans_checkout
    WHERE
        our_number IS NOT NULL
        AND CAST(our_number AS STRING) != company_use
),

vans_checkout_matched AS (
    SELECT
        join_key,
        company_use,
        id_invoice,
        payment_method,
        payment_status,
        dt_paid,
        amount,
        rn
    FROM
        vans_checkout_for_join
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY join_key, rn
            ORDER BY
                CASE WHEN payment_method = 'PIX' THEN 0 WHEN payment_method = 'BOLETO' THEN 1 ELSE 2 END,
                company_use
        ) = 1
),

known_company_use AS (
    SELECT company_use FROM seu_barriga
    UNION
    SELECT company_use FROM francesinha
    UNION
    SELECT company_use FROM sap
),

df_all AS (
    SELECT company_use, rn FROM seu_barriga
    UNION DISTINCT
    SELECT company_use, rn FROM francesinha
    UNION DISTINCT
    SELECT company_use, rn FROM sap
    UNION DISTINCT
    -- FIX: drop checkout-only orphan keys (e.g. our_number 483365 with no bank/retsuko match)
    SELECT vc.company_use, vc.rn
    FROM vans_checkout vc
    INNER JOIN known_company_use kcu
        ON kcu.company_use = vc.company_use
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
            WHEN vc.join_key IS NULL THEN 'not recorded'
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
        vans_checkout_matched vc
            ON vc.join_key = cs.company_use AND vc.rn = cs.rn
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
    df.id_company_use,
    df.id_invoice,
    df.hash,
    df.bank_number,
    df.bank_account_number,
    df.sap_account_number,
    df.payment_method,
    df.payment_status,
    df.bank_amount,
    df.retsuko_amount,
    df.vans_checkout_amount,
    df.sap_amount,
    df.status_bank,
    df.status_retsuko,
    df.status_vans_checkout,
    df.status_sap,
    IF(status_bank = 'ok' AND status_vans_checkout = 'ok' AND status_retsuko = 'ok' AND status_sap = 'ok', TRUE, FALSE) AS is_reconciled,
    CASE 
        WHEN status_bank = 'ok' AND status_vans_checkout = 'ok' AND status_retsuko = 'ok' AND status_sap = 'ok' THEN 'Concilied'
        WHEN status_sap = 'not recorded' AND status_bank = 'not recorded' THEN 'Not Concilied - SAP & Bank missing'
        WHEN status_sap = 'not recorded' THEN 'Not Concilied - SAP missing'
        WHEN status_bank = 'not recorded' THEN 'Not Concilied - Bank missing'
        WHEN sap_amount/bank_amount = 2 THEN 'Not Concilied - SAP duplicated'
        WHEN status_vans_checkout = 'not recorded' THEN 'Not Concilied - Payment source missing'
        WHEN status_retsuko = 'not recorded' THEN 'Not Concilied - Retsuko missing'
        WHEN dt_sap_paid < dt_bank_paid OR dt_sap_paid > dt_bank_paid THEN 'Not Concilied - SAP and Bank with divergent date'
        WHEN status_vans_checkout IN ('recorded with a divergent date and value','recorded with a divergent value','recorded with a divergent date') THEN 'Not Concilied - Payment source divergent'
        WHEN status_retsuko IN ('recorded with a divergent date and value','recorded with a divergent value','recorded with a divergent date') THEN 'Not Concilied - Billing divergent'
        ELSE 'Not Concilied - other'
    END AS is_bank_concilied_detail,
    CASE 
        WHEN status_sap = 'not recorded' AND id_invoice IS NULL THEN 'retsuko not found'
        WHEN status_sap = 'not recorded' AND e.id_finance_entity IS NULL THEN 'sap entity not found'
        WHEN status_sap = 'not recorded' AND e.status = 'failed' THEN CONCAT('sap_entity failed:',e.failed_reason)
        WHEN status_sap = 'not recorded' AND sg.id_feature IS NULL THEN 'gateway not found'
        WHEN status_sap = 'not recorded' AND sg.sync_sap_job_status = 'error' THEN sg.webhook_error
        WHEN status_sap = 'not recorded' AND e.id_finance_entity IS NOT NULL AND sg.id_feature IS NOT NULL THEN 'sap not found'
    END AS sap_error_detail,
    df.dt_bank_paid,
    df.dt_retsuko_paid,
    df.dt_vans_checkout_paid,
    df.dt_sap_paid,
    coalesce(dt_bank_paid, dt_sap_paid,dt_retsuko_paid, dt_vans_checkout_paid) as dt_paid
FROM
    df
LEFT JOIN 
        sap_entity e
            ON df.id_invoice = e.id_finance_entity
LEFT JOIN 
        sap_gateway sg
            ON e.id_sap_gateway_feature = sg.id_feature