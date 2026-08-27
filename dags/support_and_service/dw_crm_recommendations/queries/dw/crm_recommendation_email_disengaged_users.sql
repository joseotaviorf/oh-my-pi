WITH recommendation_canvases AS (
    SELECT DISTINCT
        canvases.sk_canvas,
        canvases.canvas_name
    FROM
        dw_braze.dim_canvas AS canvases
    WHERE
        canvases.user_type = 'tenants'
        AND canvases.canvas_name IN (
            'Growth_Ret.D.GERAL.Rent.Recommendations',
            'ZEBRA.rent.eng.nonorg.na.d.email.braze.recommendations.diversas'
        )
),
recommendation_sends AS (
    SELECT
        dispatches.sk_user,
        dispatches.ts_email_sent,
        dispatches.ts_email_last_opened AS ts_email_opened
    FROM
        dw_braze.fact_canvas_user_dispatch AS dispatches
    INNER JOIN
        recommendation_canvases AS canvases
        ON dispatches.sk_canvas = canvases.sk_canvas
    WHERE
        dispatches.user_type = 'tenants'
        AND dispatches.event_channel = 'email'
        AND dispatches.ts_email_sent IS NOT NULL
        AND MAKE_DATE(dispatches.year, dispatches.month, dispatches.day) >= DATE('2026-01-01')
        AND dispatches.ts_email_sent >= TIMESTAMP('2026-01-01')
        AND dispatches.ts_email_sent <= CURRENT_TIMESTAMP()
),
sends_with_milestones AS (
    SELECT
        sends.sk_user,
        sends.ts_email_sent,
        sends.ts_email_opened,
        MAX(sends.ts_email_sent) OVER (PARTITION BY sends.sk_user) AS ts_last_sent,
        MAX(sends.ts_email_opened) OVER (PARTITION BY sends.sk_user) AS ts_last_opened
    FROM
        recommendation_sends AS sends
),
user_engagement AS (
    SELECT
        milestones.sk_user,
        MAX(milestones.ts_last_sent) AS ts_last_sent,
        MAX(milestones.ts_last_opened) AS ts_last_opened,
        COUNT_IF(milestones.ts_email_sent >= milestones.ts_last_sent - INTERVAL 14 DAYS) AS qt_sends_in_analysis_window,
        COUNT_IF(
            milestones.ts_email_sent >= milestones.ts_last_sent - INTERVAL 14 DAYS
            AND milestones.ts_email_opened IS NOT NULL
        ) AS qt_opens_in_analysis_window
    FROM
        sends_with_milestones AS milestones
    GROUP BY
        milestones.sk_user
)
SELECT
    engagement.sk_user AS id_user,
    users.email,
    users.uuid_person
FROM
    user_engagement AS engagement
INNER JOIN
    dw_public.dim_user AS users
    ON engagement.sk_user = users.sk_user
WHERE
    engagement.qt_sends_in_analysis_window >= 14
    AND engagement.qt_opens_in_analysis_window = 0
    AND engagement.ts_last_sent >= CURRENT_TIMESTAMP() - INTERVAL 30 DAYS
    AND (
        engagement.ts_last_opened IS NULL
        OR engagement.ts_last_opened < engagement.ts_last_sent
    )
    AND NULLIF(users.email, '') IS NOT NULL
    AND users.email NOT LIKE '%@corretores.quintoandar.com.br'
    AND (users.country_code = 'BR' OR users.country_code IS NULL)
