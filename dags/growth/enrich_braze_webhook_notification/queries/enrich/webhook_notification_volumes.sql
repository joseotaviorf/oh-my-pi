WITH
canvas_details_indica_ai AS (
	SELECT
		id_canvas,
	    canvas_name,
	    canvas_description,
	    variants,
	    steps,
	    ts_updated
    FROM
    	datalake_braze_details_clean.canvas_details_indica_ai
    WHERE
        DATE(ts_updated) = DATE('{year}-{month}-{day}')
),
canvas_details_owners AS (
	SELECT
		id_canvas,
	    canvas_name,
	    canvas_description,
	    variants,
	    steps,
	    ts_updated
    FROM
    	datalake_braze_details_clean.canvas_details_owners
    WHERE
        DATE(ts_updated) = DATE('{year}-{month}-{day}')
),
canvas_details_tenants AS (
	SELECT
		id_canvas,
	    canvas_name,
	    canvas_description,
	    variants,
	    steps,
	    ts_updated
    FROM
    	datalake_braze_details_clean.canvas_details_tenants
    WHERE
        DATE(ts_updated) = DATE('{year}-{month}-{day}')
),
exploded_steps_indica_ai AS (
    SELECT
        explode(steps) AS step
    FROM
        canvas_details_indica_ai
),
exploded_steps_owners AS (
    SELECT
        explode(steps) AS step
    FROM
        canvas_details_owners
),
exploded_steps_tenants AS (
    SELECT
        explode(steps) AS step
    FROM
        canvas_details_tenants
),
organized_messages AS (
    SELECT
        step.id AS id_step,
        step.name AS step_name,
        TRIM(
            CAST(
                REPLACE(
                SPLIT(SPLIT(step.messages, ',') [5], ':') [1],
                '"',
                ''
                ) AS STRING
            )
        ) AS rule_status
    FROM
        exploded_steps_indica_ai
    UNION ALL
    SELECT
        step.id AS id_step,
        step.name AS step_name,
        TRIM(
            CAST(
                REPLACE(
                SPLIT(SPLIT(step.messages, ',') [5], ':') [1],
                '"',
                ''
                ) AS STRING
            )
        ) AS rule_status
    FROM
        exploded_steps_owners
    UNION ALL
    SELECT
        step.id AS id_step,
        step.name AS step_name,
        TRIM(
            CAST(
                REPLACE(
                SPLIT(SPLIT(step.messages, ',') [5], ':') [1],
                '"',
                ''
                ) AS STRING
            )
        ) AS rule_status
    FROM
        exploded_steps_tenants
),
exploded_indica_ai_variants AS (
    SELECT
        id_canvas,
        canvas_name,
        canvas_description,
        EXPLODE(variants) AS variant
    FROM
        canvas_details_indica_ai
),
exploded_owners_variants AS (
    SELECT
        id_canvas,
        canvas_name,
        canvas_description,
        EXPLODE(variants) AS variant
    FROM
        canvas_details_owners
),
exploded_tenants_variants AS (
    SELECT
        id_canvas,
        canvas_name,
        canvas_description,
        EXPLODE(variants) AS variant
    FROM
        canvas_details_tenants
),
canvas_description AS (
    SELECT
        variant.id AS id_variant_canvas,
        id_canvas,
        canvas_name,
        variant.name AS variant_name
    FROM
        exploded_indica_ai_variants
    GROUP BY 1,2,3,4
    UNION ALL
    SELECT
        variant.id AS id_variant_canvas,
        id_canvas,
        canvas_name,
        variant.name AS variant_name
    FROM
        exploded_owners_variants
    GROUP BY 1,2,3,4
    UNION ALL
    SELECT
        variant.id AS id_variant_canvas,
        id_canvas,
        canvas_name,
        variant.name AS variant_name
    FROM
        exploded_tenants_variants
    GROUP BY 1,2,3,4
),
canvas_user_dispatch AS (
    SELECT
        id_user_dispatch,
        id_canvas,
        id_variant_canvas,
        id_step_canvas,
        event_channel,
        ts_webhook_sent
    FROM
        datalake_braze_dispatches_user.owners_events
    WHERE
        id_canvas IS NOT NULL
        AND event_channel = 'webhook'
        AND DATE(ts_webhook_sent) = DATE('{year}-{month}-{day}')
    GROUP BY 1,2,3,4,5,6
    UNION ALL
    SELECT
        id_user_dispatch,
        id_canvas,
        id_variant_canvas,
        id_step_canvas,
        event_channel,
        ts_webhook_sent
    FROM
        datalake_braze_dispatches_user.tenants_events
    WHERE
        id_canvas IS NOT NULL
        AND event_channel = 'webhook'
        AND DATE(ts_webhook_sent) = DATE('{year}-{month}-{day}')
    GROUP BY 1,2,3,4,5,6
    UNION ALL
    SELECT
        id_user_dispatch,
        id_canvas,
        id_variant_canvas,
        id_step_canvas,
        event_channel,
        ts_webhook_sent
    FROM
        datalake_braze_dispatches_user.affiliates_events
    WHERE
        id_canvas IS NOT NULL
        AND event_channel = 'webhook'
        AND DATE(ts_webhook_sent) = DATE('{year}-{month}-{day}')
    GROUP BY 1,2,3,4,5,6
),
events AS (
    SELECT
        cud.id_step_canvas,
        cd.canvas_name,
        cd.variant_name,
        cud.ts_webhook_sent,
        ROW_NUMBER() OVER(PARTITION BY cud.id_user_dispatch, cud.id_canvas ORDER BY cud.ts_webhook_sent DESC) AS row_number
    FROM
        canvas_user_dispatch  AS cud
        LEFT JOIN canvas_description AS cd
            ON cud.id_variant_canvas = cd.id_variant_canvas
)
SELECT
    ev.id_step_canvas,
    ev.canvas_name,
    ev.variant_name,
    om.step_name,
    om.rule_status,
    COUNT(*) AS notification_count,
    DATE(ts_webhook_sent) AS dt_webhook_sent
FROM
    events ev
    JOIN organized_messages om
        ON ev.id_step_canvas = om.id_step
WHERE
    row_number = 1
GROUP BY 1,2,3,4,5,7
