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
),
cte_billing_type AS (
    WITH billing_type_windows AS (
        SELECT
            id AS id_propose,
            billing_model,
            MIN(rs.ts_created) AS ts_started,
            IFNULL(MAX(re.ts_created), NOW()) AS ts_ended
        FROM
            datalake_rental_guarantee_platform_clean.propose_aud AS p
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.rev_info AS rs
            ON rs.rev = p.rev
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.rev_info AS re
            ON re.rev = p.rev_end
        GROUP BY 1,2
    )
    SELECT
        p.id AS id_payment,
        IFNULL(b.billing_model, 'DEFAULT') AS billing_model -- p.ts_created is < b.ts_started
    FROM
        datalake_rental_guarantee_platform_clean.payment AS p
    LEFT JOIN
        billing_type_windows AS b
        ON p.id_propose = b.id_propose
        AND (p.ts_created BETWEEN b.ts_started AND b.ts_ended)
),
cte_pix_payment_date AS (
    SELECT
        id AS id_payment,
        FIRST_VALUE(ts_client_payment) OVER (PARTITION BY payment_link ORDER BY ts_client_payment) AS ts_pix_payment
    FROM
        datalake_rental_guarantee_platform_clean.payment
    WHERE
        billing_type = 'PIX'
        AND gateway = 'PIXAR'
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
    jk5.id_junk AS id_payment_category, -- p.product_type
    p.customer AS id_customer,
    p.unicid AS id_unicid,
    p.id_subscription,
    p.billing_type AS billing_type,
    CASE
        WHEN p.billing_type = 'PIX' AND p.gateway = 'PIXAR' THEN 'annual'
        WHEN p.billing_type = 'ANNUAL_CREDIT_CARD' THEN 'annual'
        WHEN p.billing_type = 'CREDIT_CARD' THEN 'monthly'
        ELSE NULL
    END AS payment_type,
    p.status AS status,
    p.gateway AS payment_gateway,
    IF(p.product_type = 'GUARANTEE', 'RECURRING_SUBSCRIPTION', p.product_type) AS payment_category,
    p.invoice_url,
    p.description,
    p.value AS due_amount,
    CAST(NULL AS DOUBLE) AS net_amount,
    DATE(p.ts_client_payment) > DATE(p.ts_due) AS is_paid_late,
    p.ts_due_original IS NOT NULL AND p.ts_due_original <> p.ts_due AS is_due_modified,
    FALSE AS is_occurrence,
    IF(bt.billing_model = 'BROKER', TRUE, FALSE) AS is_direct_billing,
    p.id <= 5000000 AS is_legacy,
    DATE(p.ts_created) AS dt_created,
    DATE(p.ts_due) AS dt_due,
    CAST(NULL AS STRING) AS dt_due_original,
    IFNULL(ppd.ts_pix_payment, p.ts_client_payment) AS dt_paid,
    CAST(NULL AS STRING) as dt_payment_confirmed,
    p.ts_updated
FROM
    datalake_rental_guarantee_platform_clean.payment AS p
LEFT JOIN
    datalake_velo.junk AS jk1
    ON jk1.desc_lvl_1 = p.billing_type
        AND jk1.desc_master_type = 'Billing Type'
LEFT JOIN
    datalake_velo.junk AS jk2
    ON jk2.desc_lvl_1 = CASE
                            WHEN p.billing_type = 'PIX' AND p.gateway = 'PIXAR' THEN 'annual'
                            WHEN p.billing_type = 'ANNUAL_CREDIT_CARD' THEN 'annual'
                            WHEN p.billing_type = 'CREDIT_CARD' THEN 'monthly'
                            ELSE NULL
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
    datalake_velo.junk AS jk5
    ON jk5.desc_lvl_1 = IF(p.product_type = 'GUARANTEE', 'RECURRING_SUBSCRIPTION', p.product_type)
        AND jk5.desc_master_type = 'Payment Category'
LEFT JOIN
    cte_prop_values AS pv
    ON pv.id_propose = p.id_propose
LEFT JOIN
    cte_billing_type AS bt
    ON p.id = bt.id_payment
LEFT JOIN
    cte_pix_payment_date AS ppd
    ON ppd.id_payment = p.id
    AND p.billing_type = 'PIX'
    AND p.gateway = 'PIXAR'


UNION ALL

SELECT DISTINCT
    (ap.id + 5000000) * -1 AS id_payment,
    d.id_propose,
    collect_list(d.id) AS id_occurrence,
    pv.id_propose_values AS id_propose_values,
    jk1.id_junk AS id_billing_type,
    jk2.id_junk AS id_payment_type,
    jk3.id_junk AS id_status,
    NULL AS id_payment_gateway,
    jk4.id_junk AS id_payment_category,
    NULL AS id_customer,
    NULL AS id_unicid,
    NULL AS id_subscription,
    ap.billing_type AS billing_type,
    'collection/no info' AS payment_type,
    ap.status AS status,
    NULL AS payment_gateway,
    'AGREEMENT' AS payment_category,
    NULL AS invoice_url,
    NULL AS description,
    ap.value AS due_amount,
    CAST(NULL AS DOUBLE) AS net_amount,
    DATE(ap.dt_paid) > DATE(ap.dt_due) AS is_paid_late,
    NULL AS is_due_modified,
    TRUE AS is_occurrence,
    FALSE AS is_direct_billing,
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
    datalake_velo.junk AS jk4
    ON jk4.desc_lvl_1 = 'AGREEMENT'
        AND jk4.desc_master_type = 'Payment Category'
LEFT JOIN
    cte_prop_values AS pv
    ON pv.id_propose = d.id_propose
GROUP BY 1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32
