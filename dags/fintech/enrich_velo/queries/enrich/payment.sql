WITH old_system AS (
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
    ),
    occurrence AS (
        SELECT DISTINCT
            id_occurrence,
            id_payment
        FROM
            datalake_velo.occurrence
    )
    SELECT
        p.id_payment,
        p.id_propose,
        pv.id_propose_values AS id_propose_values,
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
        p.dt_paid > p.dt_due AS is_paid_late,
        p.dt_due_original IS NOT NULL AND p.dt_due_original <> p.dt_due AS is_due_modified,
        ISNOTNULL(o.id_occurrence) AS is_occurrence,
        TRUE is_legacy,
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
        occurrence AS o
            ON o.id_occurrence = p.id_payment
    LEFT JOIN
        datalake_velo_raw.fiancavelo_plans AS pl
            ON pl.id = fp.plan
    LEFT JOIN
        datalake_velo_clean.fiancavelo_billingtype AS bt
            ON bt.id = p.id_billing_type
    LEFT JOIN
        datalake_velo.junk AS jk1
            ON jk1.desc_lvl_1 = bt.name
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
        datalake_velo_clean.fiancavelo_paymentstatus AS ps
            ON ps.id = p.id_status
    LEFT JOIN
        datalake_velo.junk AS jk3
            ON jk3.desc_lvl_1 = ps.name
            AND jk3.desc_master_type = 'Payment Status'
    LEFT JOIN
        datalake_velo_clean.fiancavelo_gateway AS pg
            ON pg.id = p.id_gateway
    LEFT JOIN
        datalake_velo.junk AS jk4
            ON jk4.desc_lvl_1 = pg.name
            AND jk4.desc_master_type = 'Payment Gateway'
    WHERE
        p.rn = 1
),
new_system AS (
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
        NULL AS net_amount,
        p.ts_client_payment > p.ts_due AS is_paid_late,
        p.ts_due_original IS NOT NULL AND p.ts_due_original <> p.ts_due AS is_due_modified,
        FALSE AS is_occurrence,
        FALSE AS is_legacy,
        DATE(p.ts_created) AS dt_created,
        DATE(p.ts_due) AS dt_due,
        NULL AS dt_due_original,
        p.ts_client_payment AS dt_paid,
        NULL as dt_payment_confirmed,
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
    WHERE
        p.id >= 5000000
    UNION ALL

    SELECT DISTINCT
        (ap.id + 5000000) * -1 AS id_payment,
        d.id_propose,
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
        NULL AS net_amount,
        ap.dt_paid > ap.dt_due AS is_paid_late,
        NULL AS is_due_modified,
        TRUE AS is_occurrence,
        FALSE AS is_legacy,
        DATE(ap.ts_created) AS dt_created,
        ap.dt_due AS dt_due,
        NULL AS dt_due_original,
        ap.dt_paid AS dt_paid,
        NULL as dt_payment_confirmed,
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

),


cte_union AS (
(
SELECT *
FROM
    old_system
)
UNION ALL
(
SELECT *
FROM
    new_system
)
ORDER BY 1
)
SELECT
    id_payment,
    id_propose_values,
    id_propose,
    id_billing_type,
    id_payment_type,
    id_status,
    id_payment_gateway,
    id_customer,
    id_unicid,
    id_subscription,
    invoice_url,
    description,
    due_amount,
    net_amount,
    is_paid_late,
    is_due_modified,
    is_occurrence,
    is_legacy,
    dt_created,
    dt_due,
    dt_due_original,
    dt_paid,
    dt_payment_confirmed,
    ts_updated
FROM
    cte_union
