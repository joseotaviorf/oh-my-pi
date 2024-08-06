WITH francesinha AS (
    SELECT
        UPPER(REPLACE(document_number, 'C!', '')) AS company_use,
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
        1,2
),

sap AS (
    SELECT DISTINCT
        id_business_entity,
        UPPER(id_external_payment) AS company_use,
        dt_tax AS dt_paid,
        SUM(debit_credit) AS amount
    FROM
        datalake_accounting_funnel.ledger
    WHERE
        account_number = '11102.01.01'
        AND id_finance_entity <> ''
        AND id_finance_entity IS NOT NULL
        AND id_external_payment IS NOT NULL
        AND TRIM(id_external_payment) != ''
    GROUP BY
        1,2,3
    HAVING
        SUM(debit_credit) != 0
),

vans_checkout_union AS (
    SELECT
        NULLIF(b.your_number, '') AS company_use,
        NULLIF(b.id_business_entity, '') AS id_contract,
        b.id_finance_entity AS id_invoice,
        DATE(b.ts_paid - interval '3' hour) AS ts_paid,
        b.paid_amount,
        b.payer_name,
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
        NULLIF(split_part(regexp_replace(b.company_use, '[A-Z]', '|'), '|', 1), '') AS id_contract,
        b.id_related_document AS id_invoice,
        DATE(b.dt_paid) AS ts_paid,
        b.paid_amount AS paid_amount,
        b.payer_name AS payer_name,
        NULLIF(CAST(b.our_number AS INTEGER), '') AS our_number
    FROM
        datalake_vans_clean.boleto b
    WHERE
        b.status in (':boleto.status/paid', ':boleto.status/write-down-paid-requested')
        AND (b.id_bank_boleto = 1 OR b.id_bank_boleto IS NULL)
        AND (NULLIF(b.company_use, '') IS NOT NULL OR NULLIF(b.document_number, '') IS NOT NULL)
        AND LOWER(b.document_number) NOT LIKE 'fs%'
),

vans_checkout AS (
    SELECT
        UPPER(vc.company_use) AS company_use,
        vc.our_number,
        vc.id_contract,
        vc.id_invoice,
        DATE(dd.next_brz_fintech_business_day) AS dt_paid,
        vc.paid_amount AS amount,
        vc.payer_name
    FROM
        vans_checkout_union vc
    LEFT JOIN
        dw_public.dim_date dd
            ON vc.ts_paid = dd.date
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY our_number, paid_amount ORDER BY CASE WHEN id_invoice IS NOT NULL THEN company_use ELSE our_number END DESC) = 1
),

seu_barriga AS (
    SELECT
        id_external AS id_invoice,
        id_original_invoice_external,
        UPPER(payment_company_use_number) AS company_use,
        payment_status,
        status,
        paid_via,
        reason,
        paid_amount AS amount,
        dd.next_brz_fintech_business_day AS dt_paid
    FROM
        datalake_retsuko.invoice
    LEFT JOIN
        dw_public.dim_date dd
            ON invoice.ts_paid = dd.date
    WHERE
        payment_company_use_number IS NOT NULL
        AND TRIM(payment_company_use_number) != ''
        AND lower(reason) NOT IN ('negotiation-5a', 'negotiation-recupera')
        AND paid_via NOT IN ('collector-5A', 'credit-card', 'unknown', 'paypal', 'bank-transfer')
        AND due_amount <= 0
        AND payment_status != 'canceled'
        AND status != 'canceled'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_invoice, payment_company_use_number ORDER BY ts_created DESC) = 1
),

df_all AS (
    SELECT DISTINCT
        company_use
    FROM
        seu_barriga
    UNION ALL
    SELECT DISTINCT
        company_use
    FROM
        vans_checkout
    UNION ALL
    SELECT DISTINCT
        company_use
    FROM
        sap
    UNION ALL
    SELECT DISTINCT
        company_use
    FROM
        francesinha
),

df AS (
    SELECT DISTINCT
        cs.company_use AS id_company_use,
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
            on f.company_use = cs.company_use
    LEFT JOIN
        vans_checkout vc
            ON vc.company_use = cs.company_use
    LEFT JOIN
        seu_barriga sb
            on cs.company_use = sb.company_use
    LEFT JOIN
        sap s
            on cs.company_use = s.company_use
    WHERE
        cs.company_use IS NOT NULL
    AND
        (
            DATE(f.dt_paid) >= '2024-01-01' OR
            DATE(vc.dt_paid) >= '2024-01-01' OR
            DATE(sb.dt_paid) >= '2024-01-01' OR
            DATE(s.dt_paid) >= '2024-01-01'
    )
)

SELECT
    id_company_use,
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
