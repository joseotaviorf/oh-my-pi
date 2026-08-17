WITH earning_source_updated AS (
    SELECT DISTINCT
        id_earning_source
    FROM
        datalake_big_agent_clean.new_earnings
    WHERE
        DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    ue.id AS id_unresolved_earning,
    ue.id_earning_source,
    ue.id_external_receiver,
    ue.external_receiver_type,
    ue.incentive_system,
    ue.reason,
    IF(ue.ts_solved IS NOT NULL, TRUE, FALSE) AS is_solved,
    IF(
        ue.ts_solved IS NOT NULL,
        ROW_NUMBER() OVER(
            PARTITION BY
                ue.id_earning_source,
                ue.id_external_receiver,
                ue.external_receiver_type,
                ue.incentive_system,
                (ue.ts_solved IS NOT NULL)
            ORDER BY
                ue.ts_solved ASC,
                ue.ts_created ASC
        ) = 1,
        FALSE
    ) AS is_first_solved_by_earning,
    ue.ts_solved,
    ue.ts_created,
    ue.ts_updated,
    YEAR(ue.ts_created) AS year,
    MONTH(ue.ts_created) AS month,
    DAY(ue.ts_created) AS day
FROM
    earning_source_updated AS esu
JOIN
    datalake_big_agent_clean.unresolved_earnings AS ue
        ON ue.id_earning_source = esu.id_earning_source
