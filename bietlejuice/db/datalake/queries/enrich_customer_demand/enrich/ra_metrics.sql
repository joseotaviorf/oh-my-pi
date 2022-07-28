WITH last_ticket_modified AS (
    SELECT
        rat.id,
        FIRST(COALESCE(rat.historical.user.email[ARRAY_POSITION(rat.historical.user.name, rat.user.name)])) AS email,
        MAX(ts_last_modification) AS ts_last_ticket_modified
    FROM
        datalake_reclameaqui_clean.tickets rat
    GROUP BY 
        1
),
distinct_ticket AS (
    SELECT DISTINCT
        rat.id,
        ac.id_assignee AS id_agent,
        rat.rating,
        rat.would_do_business_again,
        rat.is_resolved_issue,
        DATE(ts_rating) AS dt_metric_reference
    FROM
        datalake_reclameaqui_clean.tickets rat
    JOIN
        last_ticket_modified ltm
            ON rat.id = ltm.id
            AND rat.ts_last_modification = ltm.ts_last_ticket_modified
    JOIN
        datalake_gsheets_clean.agents_control ac
            ON ltm.email = ac.email
    WHERE
        ts_rating IS NOT NULL 
        AND NULLIF(moderation.status, 'Não Aceita') IS NULL 
        AND ac.id_assignee <> ''
)
SELECT
    id_agent,
    SUM(CASE WHEN rating <> -1 THEN rating ELSE 0 END) AS ra_score_sum,
    SUM(CASE WHEN would_do_business_again THEN 1 ELSE 0 END) AS ra_would_do_business_again,
    SUM(CASE WHEN is_resolved_issue THEN 1 ELSE 0 END) AS ra_solved_tickets,
    COUNT(1) AS ra_total_tickets_rated,
    dt_metric_reference
FROM
    distinct_ticket
GROUP BY
    1,6