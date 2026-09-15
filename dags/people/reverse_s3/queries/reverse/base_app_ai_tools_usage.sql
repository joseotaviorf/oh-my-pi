-- Monthly AI Tools Usage export for the AI Adoption Portal.
-- Spend and engagement are sourced from the conformed Claude facts and joined
-- at the normalized email/month grain. People attributes use current dw_people
-- dimensions for every reference month; Claude group membership is the latest
-- available snapshot. The current budget version is reused for every reference month.
-- load_start_date controls current-month status calculations and forecast; the
-- final projection stamps ts_load with the current query timestamp.
-- forecast_usd is a consumption-pace estimate for the current month and equals
-- closed-month consumption for historical months.
WITH spend_monthly AS (
    SELECT
        dau.email_user AS email,
        DATE_FORMAT(CAST(fas.dt_started AS DATE), 'yyyy-MM') AS month,
        SUM(fas.sum_discounted_cost_amount) AS consumption_usd
    FROM
        dw_ai_usage.fact_ai_spend_daily AS fas
    INNER JOIN
        dw_ai_usage.dim_ai_user AS dau
            ON dau.sk_ai_user = fas.sk_ai_user
    WHERE
        dau.email_user IS NOT NULL
        AND dau.tool = 'claude'
    GROUP BY
        dau.email_user,
        DATE_FORMAT(CAST(fas.dt_started AS DATE), 'yyyy-MM')
),
engagement_monthly AS (
    SELECT
        dau.email_user AS email,
        DATE_FORMAT(CAST(fae.dt_last_activity AS DATE), 'yyyy-MM') AS month,
        SUM(fae.count_chat_distinct_conversations) AS chat_conversations,
        SUM(fae.count_chat_messages) AS chat_messages,
        SUM(fae.count_claude_code_commits) AS code_commits,
        SUM(fae.count_claude_code_pull_requests) AS code_prs,
        SUM(fae.count_claude_code_lines_added) AS code_lines_added,
        SUM(fae.count_claude_code_lines_removed) AS code_lines_removed,
        SUM(fae.count_cowork_messages) AS cowork_messages,
        SUM(fae.count_cowork_actions) AS cowork_actions,
        SUM(fae.count_cowork_dispatch_turns) AS cowork_dispatch_turns,
        SUM(
            CASE
                WHEN fae.is_active_day = TRUE THEN 1
                ELSE 0
            END
        ) AS active_days
    FROM
        dw_ai_usage.fact_ai_engagement_daily AS fae
    INNER JOIN
        dw_ai_usage.dim_ai_user AS dau
            ON dau.sk_ai_user = fae.sk_ai_user
    WHERE
        dau.email_user IS NOT NULL
        AND dau.tool = 'claude'
    GROUP BY
        dau.email_user,
        DATE_FORMAT(CAST(fae.dt_last_activity AS DATE), 'yyyy-MM')
),
usage_monthly AS (
    SELECT
        COALESCE(spend.email, engagement.email) AS email,
        COALESCE(spend.month, engagement.month) AS month,
        spend.consumption_usd,
        engagement.chat_conversations,
        engagement.chat_messages,
        engagement.code_commits,
        engagement.code_prs,
        engagement.code_lines_added,
        engagement.code_lines_removed,
        engagement.cowork_messages,
        engagement.cowork_actions,
        engagement.cowork_dispatch_turns,
        engagement.active_days
    FROM
        spend_monthly AS spend
    FULL OUTER JOIN
        engagement_monthly AS engagement
            ON spend.email = engagement.email
            AND spend.month = engagement.month
),
current_budget_by_email AS (
    SELECT
        budget_user.email_user AS email,
        SUM(budget.sum_spend_limit_amount) AS total_limit_usd
    FROM
        dw_ai_usage.dim_ai_user AS budget_user
    INNER JOIN
        dw_ai_usage.dim_ai_budget AS budget
            ON budget.sk_ai_user = budget_user.sk_ai_user
            AND budget.tool = 'claude'
            AND budget.period_type = 'monthly'
            AND budget.currency = 'USD'
            AND budget.is_actor_deleted = FALSE
            AND budget.is_current = TRUE
    WHERE
        budget_user.tool = 'claude'
        AND budget_user.email_user IS NOT NULL
    GROUP BY
        budget_user.email_user
),
claude_groups AS (
    SELECT
        COALESCE(group_members.email, dau.email_user) AS email,
        CONCAT_WS(
            ' | ',
            SORT_ARRAY(COLLECT_SET(groups.name_group))
        ) AS group_name
    FROM
        datalake_claude_usage_clean.group_members AS group_members
    LEFT JOIN
        dw_ai_usage.dim_ai_user AS dau
            ON dau.tool = 'claude'
            AND dau.id_user = group_members.id_user
    INNER JOIN
        datalake_claude_usage_clean.groups AS groups
            ON groups.id = group_members.id_group
    WHERE
        COALESCE(group_members.email, dau.email_user) IS NOT NULL
        AND groups.name_group IS NOT NULL
        AND TRIM(groups.name_group) <> ''
    GROUP BY
        COALESCE(group_members.email, dau.email_user)
),
calculated_usage AS (
    SELECT
        usage.month,
        usage.email,
        groups.group_name,
        budget.total_limit_usd,
        usage.consumption_usd,
        CASE
            WHEN usage.consumption_usd IS NULL THEN NULL
            WHEN usage.month
                = DATE_FORMAT(DATE('{load_start_date}'), 'yyyy-MM')
                THEN usage.consumption_usd
                    * DAY(LAST_DAY(DATE('{load_start_date}')))
                    / DAY(DATE('{load_start_date}'))
            ELSE usage.consumption_usd
        END AS forecast_usd,
        CASE
            WHEN budget.total_limit_usd > 0
                THEN ROUND(
                    COALESCE(usage.consumption_usd, 0)
                    / budget.total_limit_usd
                    * 100,
                    1
                )
            ELSE 0
        END AS percent_used,
        CASE
            WHEN usage.month
                = DATE_FORMAT(DATE('{load_start_date}'), 'yyyy-MM')
                THEN DAY(DATE('{load_start_date}'))
                    * 100.0
                    / DAY(LAST_DAY(DATE('{load_start_date}')))
            ELSE 100.0
        END AS pct_month_elapsed,
        usage.chat_conversations,
        usage.chat_messages,
        usage.code_commits,
        usage.code_prs,
        usage.code_lines_added,
        usage.code_lines_removed,
        usage.cowork_messages,
        usage.cowork_actions,
        usage.cowork_dispatch_turns,
        usage.active_days
    FROM
        usage_monthly AS usage
    LEFT JOIN
        current_budget_by_email AS budget
            ON budget.email = usage.email
    LEFT JOIN
        claude_groups AS groups
            ON groups.email = usage.email
)
SELECT
    calculated.month,
    calculated.email,
    employee.name,
    calculated.group_name AS `group`,
    NULLIF(NULLIF(TRIM(hierarchy.email_l1), '-1'), '') AS l1_email,
    NULLIF(NULLIF(TRIM(hierarchy.email_l2), '-1'), '') AS l2_email,
    calculated.total_limit_usd,
    calculated.consumption_usd,
    calculated.forecast_usd,
    calculated.percent_used,
    CASE
        WHEN calculated.total_limit_usd IS NULL
            OR calculated.total_limit_usd = 0 THEN 'No limit'
        WHEN calculated.percent_used > 100 THEN 'Exceeded'
        WHEN calculated.percent_used
            > calculated.pct_month_elapsed * 1.1 THEN 'Warning'
        ELSE 'On track'
    END AS status,
    calculated.chat_conversations,
    calculated.chat_messages,
    calculated.code_commits,
    calculated.code_prs,
    calculated.code_lines_added,
    calculated.code_lines_removed,
    calculated.cowork_messages,
    calculated.cowork_actions,
    calculated.cowork_dispatch_turns,
    calculated.active_days,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    calculated_usage AS calculated
LEFT JOIN
    dw_people.dim_employee AS employee
        ON employee.work_email = calculated.email
LEFT JOIN
    dw_people.dim_management_hierarchy AS hierarchy
        ON hierarchy.person_number = employee.person_number
