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
de_para_company_use AS (
    SELECT DISTINCT  
          hash,
          id_external_payment
    FROM
            datalake_sap_gateway.sap_payload
),
sap AS (
    SELECT DISTINCT
        COALESCE(UPPER(l.id_external_payment), UPPER(dp.id_external_payment))  AS company_use,
        l.account_number,
        l.dt_reference AS dt_paid,
        l.dt_tax,
        COUNT(l.hash) AS num_entries_sap,
        ROUND(SUM(l.debit_credit), 2) AS paid_amount,
        CONCAT_WS(', ', COLLECT_LIST(l.hash)) AS hash
    FROM
        datalake_accounting_funnel.ledger AS l
    LEFT JOIN 
        de_para_company_use AS dp
            ON l.hash = dp.hash
    WHERE
        (
            dt_reference >= DATE('2024-01-01')
            AND account_number IN ('11010X', '11118X', '110350X', '11016X', '11057X')
        )
        OR
        (
            dt_reference < DATE('2024-01-01')
            AND account_number IN ('11102.01.04', '11102.02.01', '11102.01.08', '11102.01.07')
        )

    GROUP BY
        1, 2, 3, 4
),
francesinha AS (
    SELECT
        IF(
              LENGTH(company_use) IN (8,9,10,11,12,13,14,15,16,17) 
                  AND company_use NOT LIKE '%|%' 
                  AND dt_paid > '2025-06-23', 
              LEFT(REPLACE(company_use, '|', '!'), LENGTH(company_use) -2), 
              REPLACE(company_use, '|', '!')
          ) AS company_use,
        our_number,
        bank_account,
        CASE
            WHEN bank_account = 426887 THEN '11010X'
            WHEN bank_account = 79952 THEN '11118X'
            WHEN bank_account = 433065 THEN '11016X'
            WHEN bank_account = 502307 THEN '11035X'
            WHEN bank_account = 502331 THEN '11057X'
            ELSE 'unknown'
        END AS sap_account,
        dt_paid,
        occurrence_code AS last_occurrence_code,
        IF(occurrence_code = '00', paid_amount, 0.00) AS paid_amount
    FROM
        datalake_nexxera.cnab_payments
    WHERE
        occurrence_code IN ('00', 'DV')
    -- AND
    --     is_latest_attempt IS TRUE
    AND
        bank_account IN (426887, 79952, 433065, 502307, 502331)
),

cap AS (
    SELECT
        dt_paid,
        UPPER(REPLACE(reference_1, '|', '!')) AS company_use,
        payment_status,
        reference_3 AS payment_name,
        reference_4 AS payment_type,
        SPLIT(reference_5, ':') AS id_banking_payment,
        SUM(IF(payment_status = 'chargeback', 0, paid_amount)) AS paid_amount
    FROM
        datalake_accounting_funnel.payment_platforms
    WHERE
        payment_platform = 'vans_cap'
    AND
        payment_status IN ('paid', 'chargeback')
    AND
        (CAST(SPLIT(reference_5, ':')[0] AS INT) IN (1, 2, 7, 10, 13) OR reference_5 IS NULL)
    GROUP BY
        1, 2, 3, 4, 5, 6
),

seu_barriga AS (
    SELECT
        id_external AS id_invoice,
        id_original_invoice_external,
        id_contract_external,
        UPPER(REPLACE(payment_company_use_number, 'C!', '')) AS company_use, 
        paid_amount ,
        reason,
        status,
        date(ts_paid) AS dt_paid
    FROM
        datalake_retsuko.invoice
    WHERE 
        payment_company_use_number IS NOT NULL
        AND lower(paid_via) IN ('cnab')
        AND due_amount >= 0
        AND payment_status IN ('paid')
        AND status != 'canceled'
        AND country_code = 'BR'

),

cap_sap AS (
    SELECT DISTINCT
        company_use,
        dt_paid
    FROM
        cap
    UNION ALL
    SELECT DISTINCT
        company_use,
        dt_paid
    FROM
        sap
    UNION ALL
    SELECT DISTINCT
        company_use,
        dt_paid
    FROM
        francesinha
    UNION ALL
    SELECT DISTINCT
        company_use,
        dt_paid
    FROM
        seu_barriga
),

aux AS (
    SELECT DISTINCT
        cs.company_use AS id_company_use,
        sap.hash,
        r.id_invoice,
        f.bank_account AS bank_account_number,
        sap.account_number AS sap_account_number,
        sap.num_entries_sap,
        f.last_occurrence_code,
        f.paid_amount AS bank_paid_amount,
        cap.paid_amount AS cap_paid_amount,
        sap.paid_amount AS sap_paid_amount,
        r.paid_amount AS retsuko_paid_amount,
        CASE
            WHEN cap.payment_status = 'chargeback' AND sap.paid_amount = 0 THEN TRUE
            WHEN ABS(f.paid_amount) = ABS(cap.paid_amount) THEN TRUE
        ELSE FALSE
        END AS is_vans_compliance,
        CASE
            WHEN f.sap_account != sap.account_number THEN FALSE
            WHEN (ABS(f.paid_amount) = ABS(sap.paid_amount)) THEN TRUE
            WHEN last_occurrence_code = 'DV' AND (sap.paid_amount = 0 OR sap.paid_amount IS NULL) THEN TRUE
        ELSE FALSE
        END AS is_reconcilied,
        f.dt_paid AS dt_bank_paid,
        cap.dt_paid AS dt_cap_paid,
        sap.dt_paid AS dt_sap_paid,
        sap.dt_tax AS dt_sap_tax,
        cs.dt_paid,
        COALESCE(ABS(f.paid_amount), 0) as vf,
        COALESCE(ABS(cap.paid_amount), 0) as vc,
        COALESCE(ABS(sap.paid_amount), 0) as vs,
        COALESCE(ABS(r.paid_amount), 0) as vr
    FROM
        cap_sap cs
    LEFT JOIN
        francesinha f
            ON f.company_use = cs.company_use
            AND cs.dt_paid = f.dt_paid
    LEFT JOIN
        cap
            ON cs.company_use = cap.company_use
            AND cs.dt_paid = cap.dt_paid
    LEFT JOIN
        sap
            ON cs.company_use = sap.company_use
            AND cs.dt_paid = sap.dt_paid
    LEFT JOIN
        seu_barriga r
            ON cs.company_use = r.company_use
            AND cs.dt_paid = r.dt_paid
    WHERE cs.company_use IS NOT NULL
    AND NOT(cap.company_use IS NOT NULL AND f.company_use IS NULL AND sap.company_use IS NULL)
    AND cs.dt_paid >= CURRENT_DATE - 180
),

error_macro AS (
    SELECT
        id_company_use,
        hash,
        id_invoice,
        bank_account_number,
        sap_account_number,
        num_entries_sap,
        last_occurrence_code,
        bank_paid_amount,
        cap_paid_amount,
        sap_paid_amount,
        retsuko_paid_amount,
        is_vans_compliance,
        is_reconcilied,
        dt_bank_paid,
        dt_cap_paid,
        dt_sap_paid,
        dt_sap_tax,
        dt_paid,
        CASE
            WHEN vf = vs AND dt_bank_paid = dt_sap_paid THEN TRUE
            WHEN last_occurrence_code = 'DV' AND (sap_paid_amount = 0 OR sap_paid_amount IS NULL) THEN TRUE
            WHEN id_company_use LIKE '%MLRA%' THEN FALSE
            WHEN bank_paid_amount  IS NULL AND vs>=0 THEN FALSE
            WHEN vf>0 AND sap_paid_amount IS NULL THEN FALSE
            WHEN vf>0 AND sap_paid_amount = 0 AND num_entries_sap>0 THEN TRUE
            WHEN MOD(vs,vf) = 0 THEN TRUE
            WHEN vf <> vs THEN FALSE
            ELSE FALSE
        END is_bank_concilied,
        CASE
            WHEN vf = vs AND dt_bank_paid = dt_sap_paid THEN 'Concilied'
            WHEN last_occurrence_code = 'DV' AND (sap_paid_amount = 0 OR sap_paid_amount IS NULL) THEN 'Concilied - Refund'
            WHEN id_company_use LIKE '%MLRA%' THEN 'Not Concilied - LRA single entry'
            WHEN id_company_use like '%MIP%' THEN 'Not Concilied - MPI single entry'
            WHEN id_company_use like '%MCI%' THEN 'Not Concilied - MCI single entry'
            WHEN id_company_use like '%!%' AND hash like 'm%' THEN 'Not Concilied - manual accounting'
            WHEN dt_sap_tax IS NOT NULL AND dt_sap_tax < dt_sap_paid THEN 'Not Concilied - retroactive adjustment'
            WHEN bank_paid_amount  IS NULL AND vs>=0 THEN 'Not Concilied - Fracesinha missing'
            WHEN vf>0 AND sap_paid_amount IS NULL THEN 'Not Concilied - SAP missing'
            WHEN vf>0 AND sap_paid_amount = 0 AND num_entries_sap>0 THEN 'Concilied - SAP zeroed by chargeback'
            WHEN MOD(vs,vf) = 0 THEN 'Not Concilied - SAP duplicated'
            WHEN vf <> vs THEN 'Not Concilied - SAP <> Francesinha'
        END is_bank_concilied_detail
    FROM
        aux
)
SELECT
    id_company_use,
    aux.hash,
    id_invoice,
    CAST(bank_account_number AS VARCHAR(10)) AS account_number,
    bank_account_number,
    sap_account_number,
    num_entries_sap,
    last_occurrence_code,
    bank_paid_amount,
    cap_paid_amount,
    sap_paid_amount,
    retsuko_paid_amount,
    is_vans_compliance,
    is_reconcilied,
    is_bank_concilied,
    is_bank_concilied_detail,
    CASE 
        WHEN is_bank_concilied_detail = 'Not Concilied - SAP missing' AND aux.id_invoice IS NULL THEN 'retsuko not found'
        WHEN is_bank_concilied_detail = 'Not Concilied - SAP missing' AND e.id_finance_entity IS NULL THEN 'sap entity not found'
        WHEN is_bank_concilied_detail = 'Not Concilied - SAP missing' AND e.status = 'failed' THEN CONCAT('sap_entity failed:',e.failed_reason)
        WHEN is_bank_concilied_detail = 'Not Concilied - SAP missing' AND sg.id_feature IS NULL THEN 'gateway not found'
        WHEN is_bank_concilied_detail = 'Not Concilied - SAP missing' AND sg.sync_sap_job_status = 'error' THEN sg.webhook_error
        WHEN is_bank_concilied_detail = 'Not Concilied - SAP missing' AND e.id_finance_entity IS NOT NULL AND sg.id_feature IS NOT NULL THEN 'sap not found'
    END AS sap_error_detail,
    dt_bank_paid,
    dt_cap_paid,
    dt_sap_paid,
    dt_sap_tax,
    dt_paid
FROM
    error_macro aux
LEFT JOIN 
    sap_entity e
        ON aux.id_invoice = e.id_finance_entity
LEFT JOIN 
    sap_gateway sg
        ON e.id_sap_gateway_feature = sg.id_feature 