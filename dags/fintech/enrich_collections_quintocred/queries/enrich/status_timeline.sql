WITH base_cte_status AS (
    WITH fix_rev AS (
      SELECT
        a.id,
        a.id_propose,
        a.id_status,
        r.ts_created,
        a.dt_payment_scheduled,
        CASE
            WHEN DATE(r.ts_created) < DATE('2020-01-01') THEN FIRST(DATEADD(HOUR, -3, r.ts_created)) OVER (PARTITION BY id ORDER BY r.ts_created DESC)
            ELSE DATEADD(HOUR, -3, r.ts_created)
        END AS ts_created_local,
        a.dt_due,
        a.rev,
        a.rev_end,
        CASE
            WHEN a.id_type IN (0,4,5) AND DATE(a.ts_created) >= DATE("2024-02-01") THEN a.dt_due
            WHEN a.id < 15 OR a.id >= 5000000 THEN DATE(a.ts_created)
            ELSE a.dt_due
        END AS dt_fatura,
        IF(re.ts_created IS NOT NULL AND DATE(re.ts_created) < DATE('2020-01-01'), r.ts_created, re.ts_created) AS ts_ended
    FROM
        datalake_rental_guarantee_platform_clean.delinquency_aud a
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.rev_info r
        ON a.rev = r.rev
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.rev_info re
        ON a.rev_end = re.rev
        AND NOT a.mod_id_propose <=> TRUE
    ),
    base_fix AS (
    SELECT
        a.id,
        a.id_propose,
        LAST_VALUE(a.id_status) AS id_status,
        a.dt_payment_scheduled,
        a.ts_created_local,
        a.dt_due,
        a.rev,
        a.rev_end,
        a.dt_fatura,
        a.ts_ended,
        IF(ts_ended IS NULL AND a.id_status = 3, LAST_DAY(a.ts_created_local), ts_ended) AS ts_ended_3
    FROM
        fix_rev a
    GROUP BY 1,2,4,5,6,7,8,9,10,11
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY a.id, DATE(a.ts_created_local) ORDER BY a.ts_created_local DESC, CASE WHEN a.rev_end IS NULL THEN 0 ELSE 1 END, a.ts_created_local DESC) = 1
    )
    SELECT
        id,
        id_propose,
        id_status,
        ts_created_local,
        dt_due,
        dt_fatura,
        rev_end,
        rev,
        IF(rev_end IS NOT NULL AND ts_ended IS NULL, LAG(ts_created_local) OVER (PARTITION BY id ORDER BY ts_created_local DESC),ts_ended) AS ts_ended_fixed,
        ts_ended_3,
        ts_ended,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_created_local) AS order
    FROM base_fix
),
base_order AS (
    SELECT
        id,
        MAX(order) AS max
    FROM
        base_cte_status
    GROUP BY id
),
base_final AS (
    SELECT
        b.id,
        id_propose,
        id_status,
        rev_end,
        IF(order = 1, dt_fatura, ts_created_local) AS ts_created_local,
        dt_due,
        dt_fatura,
        IF(rev_end IS NOT NULL AND ts_ended IS NULL, LAG(ts_created_local) OVER (PARTITION BY b.id ORDER BY ts_created_local DESC),ts_ended) AS ts_ended_fixed,
        ts_ended_3,
        ts_ended,
        order,
        IF(order = o.max, TRUE, FALSE) AS is_last_register
    FROM
        base_cte_status b
    LEFT JOIN
        base_order o
        ON b.id = o.id
)

SELECT
    s.id,
    s.id_status AS id_status,
    d.date AS dt_status_updated
FROM
    datalake_quintoandar.aux_date AS d
LEFT JOIN
    base_final s
    ON IF(s.ts_ended_fixed IS NOT NULL OR s.ts_ended_3 IS NOT NULL,
                 DATE(d.`date`) >= DATE(s.ts_created_local) AND
                    IF(s.ts_ended_fixed IS NOT NULL AND is_last_register,
                        DATE(d.`date`) <= LAST_DAY(s.ts_ended_fixed),
                        DATE(d.`date`) <= DATE(s.ts_ended_3)),
                 DATE(d.`date`) >= DATE(s.ts_created_local))
WHERE
    d.`date` > DATE('2020-01-01')
    AND d.`date` <= CURRENT_DATE()
