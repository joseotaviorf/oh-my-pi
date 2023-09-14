-- cte to get propose_values from propose_legacy proposes
WITH old_prop_values AS (
    SELECT
        p.id AS id_propose,
        CONCAT(p.id, COALESCE(cp.id, ''), pl.id) AS id_propose_values
    FROM
        datalake_rental_guarantee_platform_clean.fiancavelo_propose_legacy AS p
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.plan AS pl
            ON p.id_plan = pl.id_legacy
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.company_plan AS cp
            ON p.id_quintocred_company = cp.id_company
            AND pl.id = cp.id_plan
),

old_gateway AS (
    WITH cte_payment_gateway AS (
        SELECT
            DISTINCT gateway AS desc_lvl_1
        FROM
            datalake_rental_guarantee_platform_clean.payment

        UNION ALL

        SELECT
            name AS desc_lvl_1
        FROM
            VALUES ('IUGU') AS gateway(name))

    SELECT
        'Payment Gateway' AS desc_master_type,
        ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
        desc_lvl_1
    FROM
        cte_payment_gateway
    GROUP BY desc_lvl_1
)

SELECT DISTINCT
    p.id AS id_payment,
    p.id_propose,
    CAST(NULL AS BIGINT) AS id_occurrence,
    pv.id_propose_values AS id_propose_values,
    jk1.id_junk AS id_billing_type, -- p.billing_type
    jk2.id_junk AS id_payment_type,
    jk3.id_junk AS id_status, -- p.status
    jk4.id_lvl_1 AS id_payment_gateway,
    CAST(NULL AS STRING) AS id_customer, -- legacy customer id not matching correctly with 3.0 gateway
    p.unicid AS id_unicid,
    CAST(NULL AS INT) AS id_subscription, -- legacy subscription id not matching correctly with 3.0 gateway
    p.invoice_url,
    p.description,
    p.value AS due_amount,
    p.netvalue AS net_amount,
    DATE(p.ts_client_payment) > DATE(p.ts_due) AS is_paid_late,
    p.ts_due_original IS NOT NULL AND p.ts_due_original <> p.ts_due AS is_due_modified,
    TRUE AS is_legacy,
    o.id IS NOT NULL AS is_occurrence,
    p.id_subscription IS NOT NULL AS is_recurring_subscription,
    DATE(p.ts_created) AS dt_created,
    DATE(p.ts_due) AS dt_due,
    CAST(NULL AS STRING) AS dt_due_original,
    p.ts_client_payment AS dt_paid,
    CAST(NULL AS STRING) as dt_payment_confirmed,
    p.ts_updated
FROM
    datalake_rental_guarantee_platform_clean.fiancavelo_payment_legacy AS p
LEFT JOIN
    datalake_rental_guarantee_platform_clean.fiancavelo_propose_legacy AS pp
    ON p.id_propose = pp.id
LEFT JOIN
    datalake_velo_clean.fiancavelo_occurrence AS o
    ON TRIM(o.invoice_url) = TRIM(p.invoice_url)
        AND TRIM(o.unicid) = TRIM(p.unicid)
LEFT JOIN
    datalake_velo.junk AS jk1
    ON jk1.desc_lvl_1 = p.quintocred_billing_type
        AND jk1.desc_master_type = 'Billing Type'
LEFT JOIN
    datalake_velo.junk AS jk2
    ON jk2.desc_lvl_1 = CASE
                            WHEN p.quintocred_billing_type = 'PIX' THEN 'annual'
                            WHEN p.quintocred_billing_type = 'CREDIT_CARD' THEN 'monthly'
                            WHEN pp.billing = 1 THEN 'billing'
                        END
        AND jk2.desc_master_type = 'Payment Type'
LEFT JOIN
    datalake_velo.junk AS jk3
    ON jk3.desc_lvl_1 = p.quintocred_status
        AND jk3.desc_master_type = 'Payment Status'
LEFT JOIN
    old_prop_values AS pv
    ON pv.id_propose = p.id_propose
LEFT JOIN
    old_gateway AS jk4
    ON jk4.desc_lvl_1 = p.gateway
        AND jk4.desc_master_type = 'Payment Gateway'


WHERE p.id NOT IN (SELECT id FROM datalake_rental_guarantee_platform_clean.payment)

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY p.invoice_url, p.description ORDER BY p.status DESC, p.ts_updated DESC) = 1
