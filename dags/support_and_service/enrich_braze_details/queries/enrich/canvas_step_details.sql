WITH owners_details_exploded AS (
    SELECT
            id_canvas,
            canvas_name,
            EXPLODE(steps) AS step_exploded, 
            ts_updated
    FROM
        datalake_braze_details_clean.canvas_details_owners
), 

canvas_step_details_owners AS (
    SELECT
        id_canvas, 
        canvas_name,
        'OWNERS' AS app_group,
        ELEMENT_AT(step_exploded, "id") AS id_step,
        ELEMENT_AT(step_exploded, "name") AS step_name,
        ELEMENT_AT(step_exploded, "channels") AS step_channel, 
        ELEMENT_AT(step_exploded, "messages") AS step_message,
        ELEMENT_AT(step_exploded, "next_step_ids") AS id_next_step, 
        ts_updated
    FROM
        owners_details_exploded
), 

tenants_details_exploded AS (
    SELECT
        id_canvas,
        canvas_name,
        EXPLODE(steps) AS step_exploded, 
        ts_updated
    FROM
        datalake_braze_details_clean.canvas_details_tenants
), 

canvas_step_details_tenants AS (
    SELECT
        id_canvas, 
        canvas_name,
        'TENANTS' AS app_group,
        ELEMENT_AT(step_exploded, "id") AS id_step,
        ELEMENT_AT(step_exploded, "name") AS step_name,
        ELEMENT_AT(step_exploded, "channels") AS step_channel, 
        ELEMENT_AT(step_exploded, "messages") AS step_message,
        ELEMENT_AT(step_exploded, "next_step_ids") AS id_next_step,
        ts_updated
    FROM
        tenants_details_exploded
), 

affiliates_details_exploded AS (
    SELECT
        id_canvas,
        canvas_name,
        EXPLODE(steps) AS step_exploded, 
        ts_updated
    FROM
        datalake_braze_details_clean.canvas_details_indica_ai
), 

canvas_step_details_affiliates AS (
    SELECT
        id_canvas, 
        canvas_name,
        'AFFILIATES' AS app_group,
        ELEMENT_AT(step_exploded, "id") AS id_step,
        ELEMENT_AT(step_exploded, "name") AS step_name,
        ELEMENT_AT(step_exploded, "channels") AS step_channel, 
        ELEMENT_AT(step_exploded, "messages") AS step_message,
        ELEMENT_AT(step_exploded, "next_step_ids") AS id_next_step, 
        ts_updated
    FROM
        affiliates_details_exploded
)

SELECT
    id_canvas,
    id_step,
    id_next_step,
    canvas_name,
    app_group,
    step_name,
    step_channel,
    step_message,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    canvas_step_details_owners
WHERE
    DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
UNION ALL
SELECT
    id_canvas,
    id_step,
    id_next_step,
    canvas_name,
    app_group,
    step_name,
    step_channel,
    step_message,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    canvas_step_details_tenants
WHERE
    DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
UNION ALL
SELECT
    id_canvas,
    id_step,
    id_next_step,
    canvas_name,
    app_group,
    step_name,
    step_channel,
    step_message,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    canvas_step_details_affiliates
WHERE
    DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')