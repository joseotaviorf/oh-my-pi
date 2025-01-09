WITH satisfaction_balance_control AS (
    SELECT
        CURRENT_DATE AS reference_date,
        CASE
            WHEN da.agent_organization IN ('atento', 'atn') THEN 'Atento'
            WHEN da.agent_organization IN ('webhelp', 'webhelpbr') THEN 'Webhelp'
        END AS bpo_name,
        ft.channel AS channel_type,
        dd.department,

        COUNT(DISTINCT CASE WHEN DATE(ft.ts_csat_response) >= current_date - interval '7' day AND ft.csat_score IN (4,5) THEN ft.sk_ticket END) AS csat_7_day,
        COUNT(DISTINCT CASE WHEN DATE(ft.ts_csat_response) >= current_date - interval '7' day AND ft.csat_score IS NOT NULL THEN ft.sk_ticket END) AS csat_answers_7_day,

        COUNT(DISTINCT CASE WHEN DATE(ft.ts_csat_response) >= current_date - interval '30' day AND ft.csat_score IN (4,5) THEN ft.sk_ticket END) AS csat_30_day,
        COUNT(DISTINCT CASE WHEN DATE(ft.ts_csat_response) >= current_date - interval '30' day AND ft.csat_score IS NOT NULL THEN ft.sk_ticket END) AS csat_answers_30_day,

        COUNT(DISTINCT CASE WHEN DATE(ft.ts_csat_response) >= current_date - interval '7' day AND ft.resolution_survey = True THEN ft.sk_ticket END) AS resolution_7_day,
        COUNT(DISTINCT CASE WHEN DATE(ft.ts_csat_response) >= current_date - interval '7' day AND ft.resolution_survey IS NOT NULL THEN ft.sk_ticket END) AS resolution_answers_7_day,

        COUNT(DISTINCT CASE WHEN DATE(ft.ts_csat_response) >= current_date - interval '30' day AND ft.resolution_survey = True THEN ft.sk_ticket END) AS resolution_30_day,
        COUNT(DISTINCT CASE WHEN DATE(ft.ts_csat_response) >= current_date - interval '30' day AND ft.resolution_survey IS NOT NULL THEN ft.sk_ticket END) AS resolution_answers_30_day
    FROM
        dw_customer_support.fact_ticket AS ft
    LEFT JOIN
        dw_customer_support.dim_department  AS dd
            ON ft.sk_main_department = dd.sk_department
    LEFT JOIN
        dw_customer_support.dim_analyst AS da
            ON da.sk_analyst = ft.sk_last_agent
    WHERE
        ft.front_or_back = 'front'
        AND ft.channel IN ('chat', 'call')
        AND DATE(ft.ts_csat_response) BETWEEN current_date - interval '30' day AND current_date
        AND dd.team IS NOT NULL
        AND dd.area = 'CX'
        AND da.agent_organization IN ('webhelp', 'atento', 'webhelpbr', 'atn')
    GROUP BY
        1, 2, 3, 4
)
SELECT
    bpo_name || ':' || channel_type || ':' || department AS key_csat,
    reference_date,
    bpo_name,
    channel_type,
    department,
    csat_7_day / (1.00 * NULLIF(csat_answers_7_day, 0)) AS csat_rate_7_day,
    csat_30_day / (1.00 * NULLIF(csat_answers_30_day, 0)) AS csat_rate_30_day,
    resolution_7_day / (1.00 * NULLIF(resolution_answers_7_day,0)) AS resolution_rate_7_day,
    resolution_30_day / (1.00 * NULLIF(resolution_answers_30_day,0)) AS resolution_rate_30_day
FROM
    satisfaction_balance_control
