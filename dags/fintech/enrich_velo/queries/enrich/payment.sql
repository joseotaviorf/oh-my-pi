
WITH cte_prop_values AS (
    SELECT
        p.id AS id_propose,
        CONCAT(p.id, cp.id, pl.id) AS id_propose_values
    FROM
        datalake_rental_guarantee_platform_clean.propose AS p
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.company_plan AS cp
            ON p.id_company_plan = cp.id
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.plan AS pl
            ON cp.id_plan = pl.id
)
SELECT DISTINCT
    p.id AS id_payment,
    p.id_propose,
    NULL AS id_occurrence,
    pv.id_propose_values AS id_propose_values,
    jk1.id_junk AS id_billing_type, -- p.billing_type
    jk2.id_junk AS id_payment_type,
    jk3.id_junk AS id_status, -- p.status
    jk4.id_junk AS id_payment_gateway, -- p.gateway
    p.customer AS id_customer,
    p.unicid AS id_unicid,
    p.id_subscription,
    p.invoice_url,
    p.description,
    p.value AS due_amount,
    CAST(NULL AS DOUBLE) AS net_amount,
    p.ts_client_payment > p.ts_due AS is_paid_late,
    p.ts_due_original IS NOT NULL AND p.ts_due_original <> p.ts_due AS is_due_modified,
    FALSE AS is_occurrence,
    p.id <= 5000000 AS is_legacy,
    DATE(p.ts_created) AS dt_created,
    DATE(p.ts_due) AS dt_due,
    CAST(NULL AS STRING) AS dt_due_original,
    p.ts_client_payment AS dt_paid,
    CAST(NULL AS STRING) as dt_payment_confirmed,
    p.ts_updated
FROM
    datalake_rental_guarantee_platform_clean.payment AS p
LEFT JOIN
    datalake_rental_guarantee_platform_clean.propose AS pp
    ON p.id_propose = pp.id
LEFT JOIN
    datalake_velo.junk AS jk1
    ON jk1.desc_lvl_1 = p.billing_type
        AND jk1.desc_master_type = 'Billing Type'
LEFT JOIN
    datalake_velo.junk AS jk2
    ON jk2.desc_lvl_1 = CASE
                            WHEN p.billing_type = 'PIX' THEN 'annual'
                            WHEN p.billing_type = 'CREDIT_CARD' THEN 'monthly'
                            WHEN pp.billing_model = 'BROKER' THEN 'billing'
                        END
        AND jk2.desc_master_type = 'Payment Type'
LEFT JOIN
    datalake_velo.junk AS jk3
    ON jk3.desc_lvl_1 = p.status
        AND jk3.desc_master_type = 'Payment Status'
LEFT JOIN
    datalake_velo.junk AS jk4
    ON jk4.desc_lvl_1 = p.gateway
        AND jk4.desc_master_type = 'Payment Gateway'
LEFT JOIN
    cte_prop_values AS pv
    ON pv.id_propose = p.id_propose
UNION ALL

SELECT DISTINCT
    (ap.id + 5000000) * -1 AS id_payment,
    d.id_propose,
    d.id AS id_occurrence,
    pv.id_propose_values AS id_propose_values,
    jk1.id_junk AS id_billing_type,
    jk2.id_junk AS id_payment_type,
    jk3.id_junk AS id_status,
    NULL AS id_payment_gateway,
    NULL AS id_customer,
    NULL AS id_unicid,
    NULL AS id_subscription,
    NULL AS invoice_url,
    NULL AS description,
    ap.value AS due_amount,
    CAST(NULL AS DOUBLE) AS net_amount,
    ap.dt_paid > ap.dt_due AS is_paid_late,
    NULL AS is_due_modified,
    TRUE AS is_occurrence,
    FALSE AS is_legacy,
    DATE(ap.ts_created) AS dt_created,
    ap.dt_due AS dt_due,
    CAST(NULL AS STRING) AS dt_due_original,
    ap.dt_paid AS dt_paid,
    CAST(NULL AS STRING) AS dt_payment_confirmed,
    ap.ts_updated

FROM
    datalake_rental_guarantee_platform_clean.agreement_payment AS ap
LEFT JOIN
    datalake_rental_guarantee_platform_clean.delinquency_has_agreement AS dha
    ON ap.id_agreement = dha.id_agreement
LEFT JOIN
    datalake_rental_guarantee_platform_clean.delinquency AS d
    ON dha.id_delinquency = d.id
LEFT JOIN
    datalake_velo.junk AS jk1
    ON jk1.desc_lvl_1 = ap.billing_type
        AND jk1.desc_master_type = 'Billing Type'
LEFT JOIN
    datalake_velo.junk AS jk2
    ON jk2.desc_lvl_1 = 'collection/no info'
        AND jk2.desc_master_type = 'Payment Type'
LEFT JOIN
    datalake_velo.junk AS jk3
    ON jk3.desc_lvl_1 = ap.status
        AND jk3.desc_master_type = 'Payment Status'
LEFT JOIN
    cte_prop_values AS pv
    ON pv.id_propose = d.id_propose
