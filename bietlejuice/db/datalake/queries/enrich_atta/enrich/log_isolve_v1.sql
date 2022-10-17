WITH cte_most_recent AS (
    SELECT
        id,
        MAX(ts_current_log) AS ts_current_log
    FROM
        datalake_atta_clean.log_isolve_v1
    GROUP BY 1
)
SELECT
    li.id,
    li.id_proposal,
    li.id_current_status,
    li.id_previous_proposal_situation,
    li.id_current_proposal_situation,
    li.id_user,
    li.control,
    li.ts_current_log,
    li.year,
    li.month,
    li.day
FROM
    datalake_atta_clean.log_isolve_v1 AS li
RIGHT JOIN
    cte_most_recent AS cte
        ON cte.id = li.id
        AND cte.ts_current_log = li.ts_current_log
