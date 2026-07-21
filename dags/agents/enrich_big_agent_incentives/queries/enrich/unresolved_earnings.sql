SELECT
    ue.id AS id_unresolved_earning,
    ne.id AS id_earning,
    ue.id_earning_source,
    ue.id_external_receiver,
    ue.external_receiver_type,
    ue.incentive_system,
    ue.reason,
    IF(ue.ts_solved IS NOT NULL, TRUE, FALSE) AS is_solved,
    IF(
        ue.ts_solved IS NOT NULL,
        ROW_NUMBER() OVER(PARTITION BY ne.id, (ue.ts_solved IS NOT NULL) ORDER BY ue.ts_solved ASC, ue.ts_created ASC) = 1,
        FALSE
    ) AS is_first_solved_by_earning,
    ue.ts_solved,
    ue.ts_created,
    ue.ts_updated,
    YEAR(ue.ts_created) AS year,
    MONTH(ue.ts_created) AS month,
    DAY(ue.ts_created) AS day
FROM
    datalake_big_agent_clean.unresolved_earnings AS ue
JOIN
    datalake_big_agent_clean.new_earnings AS ne
        ON ue.id_earning_source = ne.id_earning_source
        AND ue.id_external_receiver = ne.id_external_receiver
        AND ue.external_receiver_type = ne.external_receiver_type
        AND ue.incentive_system = ne.incentive_system
        AND ue.ts_created <= ne.ts_updated
WHERE
    DATE(ue.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
