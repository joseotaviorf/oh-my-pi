WITH secretariat_user_version AS (
    SELECT
        sah.id_secretariat_user_version,
        sah.id_secretariat_user,
        sah.version,
        ROW_NUMBER() OVER(PARTITION BY sah.id_secretariat_user, ad.date ORDER BY sah.ts_allocation_started DESC) = 1 AS is_last_version_by_date,
        ad.date AS dt_snapshot
    FROM
        datalake_secretariat.secretariat_allocation_history AS sah
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN DATE(sah.ts_allocation_started) AND DATE(COALESCE(sah.ts_allocation_ended, CURRENT_TIMESTAMP))
    WHERE
        ad.date BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT
    suv.id_secretariat_user_version,
    suv.id_secretariat_user,
    suv.version,
    suv.dt_snapshot
FROM
    secretariat_user_version AS suv
WHERE
    suv.is_last_version_by_date IS TRUE