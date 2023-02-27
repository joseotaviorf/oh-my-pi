WITH payment AS (
    SELECT
        p.id AS id_payment,
        NULLIF(p.id_propose,0) AS id_propose,
        p.customer AS id_customer,
        p.id_billing_type,
        p.id_status,
        p.id_gateway,
        p.unicid,
        p.subscription,
        p.invoice_url,
        p.description,
        p.value AS due_amount,
        p.netvalue AS net_amount,
        p.dt_created,
        p.dt_due,
        p.dt_original_due AS dt_due_original,
        p.dt_client_payment AS dt_paid,
        p.dt_confirmed AS dt_payment_confirmed,
        p.is_active,
        p.ts_updated,
        ROW_NUMBER() OVER(PARTITION BY p.invoice_url, p.description ORDER BY p.id_status DESC, p.ts_updated DESC) AS rn
    FROM
        datalake_velo_clean.fiancavelo_payment AS p
), pack_values AS (
    SELECT
        pk.propose AS id_propose,
        SUM(COALESCE(pk.value,0)) AS total_package_amount
    FROM
        datalake_velo_raw.fiancavelo_packvalues AS pk
    WHERE
        pk.active
    GROUP BY
        1
),
propose_values AS (
    SELECT
        CONCAT(p.id, a.id, pl.id) AS id_propose_values,
        p.id AS id_propose,
        pl.percent AS plan_percent
    FROM
        datalake_velo_clean.fiancavelo_propose AS p
    LEFT JOIN
        datalake_velo_clean.fiancavelo_activator AS a
        ON a.id = p.id_activator
    LEFT JOIN
        datalake_velo_clean.fiancavelo_plans AS pl
        ON pl.id = p.id_plan
)
SELECT
    p.id_payment,
    pv.id_propose_values AS id_propose_values,
    p.id_propose,
    jk1.id_junk AS id_billing_type,
    jk2.id_junk AS id_payment_type,
    jk3.id_junk AS id_status,
    jk4.id_junk AS id_payment_gateway,
    p.id_customer,
    p.unicid AS id_unicid,
    p.subscription AS id_subscription,
    p.invoice_url,
    p.description,
    p.due_amount,
    p.net_amount,
    p.net_amount * (pv.plan_percent/100) AS takerate_amount,
    p.dt_paid > p.dt_due AS is_paid_late,
    p.dt_due_original IS NOT NULL AND p.dt_due_original <> p.dt_due AS is_due_modified,
    p.dt_created,
    p.dt_due,
    p.dt_due_original,
    p.dt_paid,
    p.dt_payment_confirmed,
    p.ts_updated
FROM
    payment AS p
LEFT JOIN
    propose_values AS pv
        ON pv.id_propose = p.id_propose
LEFT JOIN
    datalake_velo_raw.fiancavelo_propose AS fp
        ON fp.id = p.id_propose
LEFT JOIN
    datalake_velo_raw.fiancavelo_activator AS a
        ON a.id = fp.activator
LEFT JOIN
    pack_values AS pk
        ON pk.id_propose = fp.id
LEFT JOIN
    datalake_velo_raw.fiancavelo_plans AS pl
        ON pl.id = fp.plan
LEFT JOIN
    datalake_velo.junk AS jk1
        ON jk1.id_lvl_1 = p.id_billing_type
        AND jk1.desc_master_type = 'Billing Type'
LEFT JOIN
    datalake_velo.junk AS jk2
        ON jk2.id_lvl_1 = CASE
                            WHEN (p.due_amount/COALESCE(pk.total_package_amount*pl.percent/100.00,0) BETWEEN 0.9 AND 1.1) OR (p.due_amount/(COALESCE(pk.total_package_amount*pl.percent/100.00,0) + COALESCE(a.value,0)) BETWEEN 0.9 AND 1.1) THEN 1
                            WHEN (p.due_amount/COALESCE(pk.total_package_amount*pl.percent*12.00/100.00,0) BETWEEN 0.9 AND 1.1) OR (p.due_amount/(COALESCE(pk.total_package_amount*pl.percent*12.00/100.00,0) + COALESCE(a.value,0)) BETWEEN 0.9 AND 1.1) THEN 2
                            WHEN p.due_amount/COALESCE(a.value,0) BETWEEN 0.9 AND 1.1 THEN 3
                        ELSE 4
                        END
        AND jk2.desc_master_type = 'Payment Type'
LEFT JOIN
    datalake_velo.junk AS jk3
        ON jk3.id_lvl_1 = p.id_status
        AND jk3.desc_master_type = 'Payment Status'
LEFT JOIN
    datalake_velo.junk AS jk4
        ON jk4.id_lvl_1 = p.id_gateway
        AND jk4.desc_master_type = 'Payment Gateway'
WHERE
    p.rn = 1
