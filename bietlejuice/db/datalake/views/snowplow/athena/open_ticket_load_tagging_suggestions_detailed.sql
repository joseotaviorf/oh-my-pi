DROP VIEW IF EXISTS datalake_snowplow_raw_prod.open_ticket_load_tagging_suggestions_detailed;
CREATE OR REPLACE VIEW datalake_snowplow_raw_prod.open_ticket_load_tagging_suggestions_detailed AS
WITH open_ticket_load_tagging_suggestions AS (
    SELECT 
        ue_derivated_context1 AS event_json,
        dvce_created_tstamp,
        event,
        vendor,
        version,
        cast(year AS integer) AS year,
        cast(month AS integer) AS month,
        cast(day AS integer) AS day
    FROM 
        datalake_snowplow_raw_prod.streaming_events_formatted
    WHERE 
        vendor = 'magiclink'
        AND event = 'open_ticket_load_tagging_suggestions'
        AND SUBSTR(version, 1, 1) = '1' -- Filter the major version of the event
)
SELECT 
    json_extract_scalar(event_json, '$.data.data.event.customer_id') AS customer_id,
    json_extract_scalar(event_json, '$.data.data.event.task_id') AS task_id,
    cast(json_extract(event_json, '$.data.data.event.customer_type_tag_suggestions') AS ARRAY(VARCHAR)) AS customer_type_tag_suggestions,
    cast(json_extract(event_json, '$.data.data.event.contact_motivation_tag_suggestions') AS ARRAY(VARCHAR)) AS contact_motivation_tag_suggestions,
    cast(json_extract(event_json, '$.data.data.event.contact_theme_tag_suggestions') AS ARRAY(VARCHAR)) AS contact_theme_tag_suggestions,
    json_extract_scalar(event_json, '$.data.data.event.uri') AS uri,
    json_extract_scalar(event_json, '$.data.data.event.referrer') AS referrer,
    dvce_created_tstamp,
    event,
    vendor,
    version,
    year,
    month,
    day
FROM 
    open_ticket_load_tagging_suggestions
;