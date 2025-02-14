WITH base_cte_status AS (
    WITH base_fix AS (
    SELECT
        a.id,
        a.id_propose,
        LAST_VALUE(a.id_status) AS id_status,
        r.ts_created,
        a.dt_payment_scheduled,
        DATEADD(HOUR, -3, r.ts_created) AS ts_created_local,
        a.dt_due,
        a.rev,
        a.rev_end,
        CASE
            WHEN a.id_type IN (0,4,5) AND DATE(a.ts_created) >= DATE("2024-02-01") THEN a.dt_due
            WHEN a.id < 15 OR a.id >= 5000000 THEN DATE(a.ts_created)
            ELSE a.dt_due
        END AS dt_fatura,
        re.ts_created AS ts_ended,
        IF(re.ts_created IS NULL AND a.id_status = 3, LAST_DAY(r.ts_created), re.ts_created) AS ts_ended_3
    FROM
        datalake_rental_guarantee_platform_clean.delinquency_aud a
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.rev_info r
        ON a.rev = r.rev
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.rev_info re
        ON a.rev_end = re.rev
        AND NOT a.mod_id_propose <=> TRUE
    GROUP BY 1,2,4,5,6,7,8,9,10,11,12
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY a.id, DATE(r.ts_created) ORDER BY r.ts_created DESC) = 1
    )
    SELECT
        *,
        IF(rev_end IS NOT NULL AND ts_ended IS NULL, LAG(ts_created_local) OVER (PARTITION BY id ORDER BY ts_created_local DESC),ts_ended) AS ts_ended_fixed
    FROM base_fix
)
SELECT
    s.id,
    s.id_status AS id_status,
    d.date AS dt_status_updated
FROM
    datalake_quintoandar.aux_date AS d
LEFT JOIN
    base_cte_status s
    ON IF(s.ts_ended_fixed IS NOT NULL OR s.ts_ended_3 IS NOT NULL, d.`date` >= s.dt_fatura AND IF(s.ts_ended_fixed IS NOT NULL, d.`date` <= LAST_DAY(s.ts_ended_fixed), d.`date` <= DATE(s.ts_ended_3)), d.`date` >= s.dt_fatura)
WHERE
    d.`date` > DATE('2020-01-01')
    AND d.`date` <= CURRENT_DATE()
