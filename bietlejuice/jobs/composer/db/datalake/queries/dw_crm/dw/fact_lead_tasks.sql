WITH task_metrics AS (
    SELECT
        sk_assignee,
        MIN(CASE WHEN action_type = 'CREATE' THEN sk_action_date ELSE NULL END) OVER (PARTITION BY sk_task ORDER BY ts_action ROWS UNBOUNDED PRECEDING) AS sk_created_date,
        MIN(CASE WHEN action_type = 'REALIZE' THEN sk_action_date ELSE NULL END) OVER (PARTITION BY sk_task ORDER BY ts_action ROWS UNBOUNDED PRECEDING) AS sk_first_realized_date,
        MIN(CASE WHEN action_type = 'RESOLVE' THEN sk_action_date ELSE NULL END) OVER (PARTITION BY sk_task ORDER BY ts_action ROWS UNBOUNDED PRECEDING) AS sk_first_resolved_date,
        sk_lead,
        sk_task,
        action_type,
        ROW_NUMBER() OVER(PARTITION BY sk_task ORDER BY ts_action) AS rn
    FROM 
        dw_crm_migration.fact_lead_task_actions AS flta
),
task_dates AS (
    SELECT
        tm.sk_lead,
        tm.sk_task,
        MIN(tm.sk_created_date) AS sk_created_date,
        MIN(tm.sk_first_realized_date) AS sk_first_realized_date,
        MIN(tm.sk_first_resolved_date) AS sk_first_resolved_date
    FROM 
        task_metrics AS tm
    GROUP BY 1,2
), 
first_assignee AS (
    SELECT 
        sk_task,
        MIN(rn) AS min_rn		
    FROM 
        task_metrics AS tm
    WHERE 
        sk_assignee <> -1
    GROUP BY 1
),
first_resolver AS (
    SELECT 
        sk_task,
        MIN(rn) AS min_rn		
    FROM 
        task_metrics AS tm
    WHERE 
        action_type = 'REALIZE' 
        AND sk_assignee <> -1
    GROUP BY 1
)
SELECT
    CAST(td.sk_lead AS INTEGER) AS sk_lead,
	td.sk_task,
    CAST(COALESCE(td.sk_created_date, -1) AS INTEGER) AS sk_created_date,
    CAST(COALESCE(td.sk_first_realized_date, -1) AS INTEGER) AS sk_first_realized_date,
    CAST(COALESCE(td.sk_first_resolved_date, -1) AS INTEGER) AS sk_first_resolved_date,
    CAST(COALESCE(tm.sk_assignee, -1) AS INTEGER) AS sk_user_first_assignee,
	CAST(COALESCE(tm_fr.sk_assignee, -1) AS INTEGER) AS sk_user_first_resolver,
	COALESCE(td.sk_first_realized_date, -1) + COALESCE(td.sk_first_resolved_date, -1) <> -2 AS is_closed,
    NOW() AS ts_load
FROM 
    task_dates AS td
JOIN 
    first_assignee AS fa
	    ON td.sk_task = fa.sk_task
JOIN 
    task_metrics AS tm 
	    ON tm.sk_task = fa.sk_task
	    AND tm.rn = fa.min_rn
LEFT JOIN 
    first_resolver AS fr
	    ON td.sk_task = fr.sk_task
LEFT JOIN 
    task_metrics AS tm_fr
	    ON tm_fr.sk_task = fr.sk_task
	    AND tm_fr.rn = fr.min_rn