WITH pre_francesinha AS (
    SELECT
        CAST(SUBSTRING(UPPER(our_number), 1, LENGTH(our_number) - 1) AS INTEGER) AS our_number,
        bank_account,
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
        1,2,3

    UNION

    SELECT
        CASE
            WHEN ext.origin_complement like '%BL%' THEN regexp_replace(
            substring(ext.origin_complement, 20, 20),
            '^0+',
            '')
            ELSE regexp_replace(ext.origin_complement, '^0+', '')
        END AS our_number,
        '04526' AS bank_account,
        DATE(ext.date_accounting) AS dt_paid,
        ext.amount_value AS amount
    FROM
        datalake_itau_statements_clean.statement_879200452685 ext
    WHERE
        ext.operation in ('C')
        AND ext.literal_code in ('9489')
),

francesinha AS (
    SELECT
        IF(LENGTH(our_number) >= 30, LEFT(our_number, LENGTH(our_number)-2), our_number) AS our_number,
        bank_account,
        dt_paid,
        amount
    FROM
        pre_francesinha
),

pre_sap AS (
    SELECT DISTINCT
        id_business_entity,
        id_finance_entity,
        id_external_payment,
        COALESCE(CAST(SPLIT_PART(id_external_payment, '|', 2) AS INTEGER), id_external_payment) our_number,
        dt_tax AS dt_paid,
        account_number,
        SUM(debit_credit) AS amount,
        CONCAT_WS(', ', COLLECT_LIST(hash)) AS hash
    FROM
        datalake_pas.ledger
    WHERE
        (
            (
                dt_reference >= DATE('2024-01-01')
                AND account_number = '11036X'
            )
            OR
            (
                dt_reference < DATE('2024-01-01')
                AND account_number = '11102.01.11'
            )
        )
        AND id_finance_entity <> ''
        AND id_finance_entity IS NOT NULL
        AND dt_tax >= current_date - 180
    GROUP BY
        1,2,3,4,5, 6
    HAVING
        SUM(debit_credit) != 0
),

sap AS (
  SELECT
    id_business_entity,
    id_finance_entity,
    id_external_payment,
    IF(LENGTH(REGEXP_REPLACE(our_number, '^0+', '')) > 30, LEFT(REGEXP_REPLACE(our_number, '^0+', ''), LENGTH(REGEXP_REPLACE(our_number, '^0+', '')) - 2), REGEXP_REPLACE(our_number, '^0+', '')) AS our_number,
    dt_paid,
    account_number,
    amount,
    hash
  FROM
    pre_sap
),

checkout AS (
    SELECT
        NULLIF(b.our_number, '') AS company_use,
        NULLIF(b.id_business_entity, '') AS id_contract,
        b.id_finance_entity AS id_invoice,
        DATE(b.ts_paid) AS ts_paid,
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

    UNION ALL

    SELECT
      IF(LENGTH(REGEXP_REPLACE(b.id_transaction, '^0+', '')) >= 30, LEFT(REGEXP_REPLACE(b.id_transaction, '^0+', ''), LENGTH(REGEXP_REPLACE(b.id_transaction, '^0+', '')) - 2), REGEXP_REPLACE(b.id_transaction, '^0+', '')) AS our_number,
      b.due_amount AS amount,
      DATE(b.ts_paid) AS dt_paid
    FROM
        datalake_checkout_clean.pix b
    WHERE
        b.requester_name = 'trato-feito'
        AND b.id NOT IN (5855, 5856, 5857)
        AND b.status IN ('PAID', 'PAID_AFTER_DUE_DATE')
        AND DATE(ts_paid) >= current_date - 180
),

trato_feito AS (
    SELECT
        COALESCE(REGEXP_REPLACE(b.our_number , '^0+', '') , REGEXP_REPLACE(i.id_external, '^0+', '')) AS our_number,
        b.id_external AS id_invoice,
        i.total_amount AS amount,
        COALESCE(DATE(p.dt_credit), DATE(p.dt_paid)) AS dt_paid
    FROM
        datalake_trato_feito_clean.installment i
    LEFT JOIN
        datalake_trato_feito_clean.payment p
            ON p.id_installment = i.id
    LEFT JOIN
        datalake_trato_feito_clean.accounting_installment aci
            ON aci.id_installment = i.id
    LEFT JOIN
        datalake_trato_feito_clean.bill b
            ON b.id_external = aci.id_external

    UNION ALL

    SELECT
         IF(LENGTH(REGEXP_REPLACE(px.id_transaction, '^0+', '')) >= 30, LEFT(REGEXP_REPLACE(px.id_transaction, '^0+', ''), LENGTH(REGEXP_REPLACE(px.id_transaction, '^0+', '')) - 2), REGEXP_REPLACE(px.id_transaction, '^0+', '')) AS our_number,
        CAST(NULL AS STRING) AS id_invoice,
        ic.paid_amount AS amount,
        CASE WHEN dd.weekend <> 'Weekday' THEN dd.next_brz_fintech_business_day
        ELSE DATE(ic.ts_last_received - interval '3' hour) END AS dt_paid
    FROM
        datalake_trato_feito_clean.installment_charges AS ic
    LEFT JOIN
        datalake_checkout_clean.pix AS px
            ON ic.id_charge = px.id_charge
    LEFT JOIN
        dw_public.dim_date dd
            ON ic.dt_paid = dd.date
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
        dd.next_brz_fintech_business_day AS dt_paid
    FROM
        datalake_retsuko.invoice
    LEFT JOIN
        dw_public.dim_date dd
            ON invoice.ts_paid = dd.date
    WHERE
        payment_company_use_number IS NOT NULL
        AND TRIM(payment_company_use_number) != ''
        AND lower(paid_via) IN ('cnab', 'checkout-boleto', 'cyber-boleto')
        AND due_amount <= 0
        AND payment_status != 'canceled'
        AND status != 'canceled'
        AND country_code = 'BR'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_invoice, payment_company_use_number ORDER BY ts_created DESC) = 1
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
        s.hash,
        f.bank_account AS bank_account_number,
        s.account_number AS sap_account_number,
        f.amount AS bank_amount,
        COALESCE(sbs.amount, tf.amount) AS billing_amount,
        vc.amount AS checkout_amount,
        s.amount AS sap_amount,
        IF(f.our_number IS NULL, 'not recorded', 'ok') AS status_bank,
        CASE
            WHEN f.amount = COALESCE(tf.amount, sbs.amount) AND f.dt_paid = DATE(COALESCE(sbs.dt_paid, tf.dt_paid)) THEN 'ok'
            WHEN f.amount != COALESCE(tf.amount, sbs.amount) AND f.dt_paid != DATE(COALESCE(sbs.dt_paid, tf.dt_paid)) THEN 'recorded on the wrong date and value'
            WHEN f.amount != COALESCE(tf.amount, sbs.amount) AND f.dt_paid = DATE(COALESCE(sbs.dt_paid, tf.dt_paid)) THEN 'recorded on the wrong value'
            WHEN f.amount = COALESCE(tf.amount, sbs.amount) AND f.dt_paid != DATE(COALESCE(sbs.dt_paid, tf.dt_paid)) THEN 'recorded on the wrong date'
            WHEN vc.our_number IS NULL THEN 'not recorded'
            ELSE 'not ok'
        END AS status_billing,
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
        COALESCE(sbs.dt_paid, tf.dt_paid) AS dt_billing_paid,
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
        trato_feito tf
            ON tf.our_number = cs.our_number
    LEFT JOIN
        seu_barriga_sap sbs
            ON (sbs.company_use = cs.our_number) OR (sbs.id_invoice = tf.id_invoice)
    LEFT JOIN
        sap s
            ON (cs.our_number = s.our_number) OR (tf.id_invoice = s.id_finance_entity)
    WHERE
        cs.our_number IS NOT NULL
    AND
        (
            DATE(f.dt_paid) >= '2024-01-01' OR
            DATE(vc.dt_paid) >= '2024-01-01' OR
            DATE(s.dt_paid) >= '2024-01-01' OR
            DATE(sbs.dt_paid) >= '2024-01-01' OR
            DATE(tf.dt_paid) >= '2024-01-01'
    )
)

SELECT
    id_our_number,
    hash,
    bank_account_number,
    sap_account_number,
    bank_amount,
    billing_amount,
    checkout_amount,
    sap_amount,
    status_bank,
    status_billing,
    status_checkout,
    status_sap,
    IF(status_bank = 'ok' AND status_sap = 'ok' AND status_checkout = 'ok' AND status_billing = 'ok', TRUE, FALSE) AS is_reconciled,
    dt_bank_paid,
    dt_billing_paid,
    dt_checkout_paid,
    dt_sap_paid
FROM
    df
