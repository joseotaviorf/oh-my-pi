WITH updated_earning_sources AS (
    SELECT
        es.id
    FROM 
        datalake_big_agent_clean.earning_sources AS es
    WHERE
        DATE(es.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
incentive_systems_calculation_status AS (
    SELECT
        es.id AS id_earning_source,
        FROM_JSON(
            es.incentive_systems_calculation_status,
            'MAP<STRING,STRING>'
        ) AS calculation_status,
        ROW_NUMBER() OVER(PARTITION BY es.id, DATE(es.ts_updated) ORDER BY es.ts_updated DESC) = 1 AS is_last_update_by_date,
        es.ts_updated
    FROM 
        updated_earning_sources AS updated
    JOIN 
        datalake_big_agent_clean.earning_sources_aud AS es
            ON updated.id = es.id
    WHERE
        es.mod_incentive_systems_calculation_status IS TRUE
)
SELECT
    XXHASH64(id_earning_source, key, ts_updated) AS sk_calculation_log,
    id_earning_source AS sk_earning_source,
    key AS incentive_system,
    value AS calculation_status,
    ROW_NUMBER() OVER(PARTITION BY id_earning_source, key ORDER BY ts_updated DESC) = 1 AS is_current_status,
    ts_updated AS ts_started,
    LEAD(ts_updated) OVER(PARTITION BY id_earning_source, key ORDER BY ts_updated) - INTERVAL 1 DAY AS ts_ended,
    NOW() AS ts_load,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM 
    incentive_systems_calculation_status
LATERAL VIEW EXPLODE(calculation_status) t AS key, value
WHERE
    is_last_update_by_date IS TRUE