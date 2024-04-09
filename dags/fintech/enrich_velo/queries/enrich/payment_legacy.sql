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
            pk.id_propose AS id_propose,
            SUM(COALESCE(pk.value,0)) AS total_package_amount
        FROM
            datalake_velo_clean.fiancavelo_packvalues AS pk
        WHERE
            pk.is_active
        GROUP BY
            1
    ),
    occurrence AS (
        SELECT DISTINCT
            o.id AS id_occurrence,
            p.id AS id_payment
        FROM
            datalake_velo_clean.fiancavelo_occurrence AS o
        LEFT JOIN
            datalake_velo_clean.fiancavelo_payment AS p
                ON TRIM(p.invoice_url) = TRIM(o.invoice_url)
                OR TRIM(p.unicid) = TRIM(o.unicid)
    ),
    migrated_ids AS (
        SELECT
            DISTINCT unicid AS id_unicid
        FROM
            datalake_rental_guarantee_platform_clean.payment
    ),
    old_status_to_quintocred AS (
        SELECT *
        FROM
        VALUES
            (0,'NULL'),
            (2,'SUCCESS'),
            (3,'PROCESSING'),
            (4,'REFUSED'),
            (5,'REFUNDED') AS t (old_id, new_status)
    )
    SELECT
        p.id_payment,
        p.id_propose,
        CAST(NULL AS BIGINT) AS id_occurrence,
        CAST(NULL AS BIGINT) AS id_propose_values,
        jk1.id_junk AS id_billing_type,
        jk2.id_junk AS id_payment_type,
        jk3.id_junk AS id_status,
        jk4.id_junk AS id_payment_gateway,
        jk5.id_junk AS id_payment_category,
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
        p.subscription IS NOT NULL AS is_recurring_subscription,
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
        datalake_velo_clean.fiancavelo_propose AS fp
            ON fp.id = p.id_propose
    LEFT JOIN
        datalake_velo_clean.fiancavelo_activator AS a
            ON a.id = fp.id_activator
    LEFT JOIN
        pack_values AS pk
            ON pk.id_propose = fp.id
    LEFT JOIN
        occurrence AS o
            ON o.id_occurrence = p.id_payment
    LEFT JOIN
        datalake_velo_clean.fiancavelo_plans AS pl
            ON pl.id = fp.id_plan
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
        old_status_to_quintocred AS ps
            ON ps.old_id = p.id_status
    LEFT JOIN
        datalake_velo.junk AS jk3
            ON jk3.desc_lvl_1 = ps.new_status
            AND jk3.desc_master_type = 'Payment Status'
    LEFT JOIN
        datalake_velo_clean.fiancavelo_gateway AS pg
            ON pg.id = p.id_gateway
    LEFT JOIN
        datalake_velo.junk AS jk4
            ON jk4.desc_lvl_1 = pg.name
            AND jk4.desc_master_type = 'Payment Gateway'
    LEFT JOIN
        datalake_velo.junk AS jk5
            ON jk5.desc_lvl_1 = (
                CASE
                  WHEN p.subscription IS NOT NULL THEN 'RECURRING_SUBSCRIPTION'
                  WHEN ISNOTNULL(o.id_occurrence) THEN 'AGREEMENT'
                  ELSE 'NO INFO'
                END
              )
            AND jk5.desc_master_type = 'Payment Category'
    LEFT JOIN
        migrated_ids AS mi
            ON mi.id_unicid = p.unicid
    WHERE
        p.rn = 1
        AND mi.id_unicid IS NULL
        AND p.id_status IN (0, 2, 3, 4, 5)
        AND CONCAT(p.id_propose,UNIX_TIMESTAMP(p.dt_due, 'yyyy-MM-dd')) NOT IN (SELECT
                                                                        CONCAT(np.id_propose,UNIX_TIMESTAMP(np.dt_due, 'yyyy-MM-dd'))
                                                                    FROM
                                                                        datalake_velo.payment np
                                                                    WHERE
                                                                        CONCAT(np.id_propose,UNIX_TIMESTAMP(np.dt_due, 'yyyy-MM-dd')) = CONCAT(p.id_propose,UNIX_TIMESTAMP(p.dt_due, 'yyyy-MM-dd')))
        AND CONCAT(p.id_propose,UNIX_TIMESTAMP(p.dt_due, 'yyyy-MM-dd')) NOT IN (SELECT
                                                                        CONCAT(ap.id_propose,UNIX_TIMESTAMP(ap.dt_due, 'yyyy-MM-dd'))
                                                                    FROM
                                                                        datalake_rental_guarantee_platform_clean.agreement_payment_legacy ap
                                                                    WHERE
                                                                        CONCAT(ap.id_propose,UNIX_TIMESTAMP(ap.dt_due, 'yyyy-MM-dd')) = CONCAT(p.id_propose,UNIX_TIMESTAMP(p.dt_due, 'yyyy-MM-dd')))

        AND p.dt_due < DATE('2023-07-01')
