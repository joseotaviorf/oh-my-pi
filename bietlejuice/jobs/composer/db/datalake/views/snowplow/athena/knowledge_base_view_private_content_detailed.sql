DROP VIEW IF EXISTS datalake_snowplow_raw_prod.knowledge_base_view_private_content_detailed;
CREATE OR REPLACE VIEW datalake_snowplow_raw_prod.knowledge_base_view_private_content_detailed AS
WITH event_knowledge_base_view_private_content AS (
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
        AND event = 'knowledge_base_view_private_content'
        AND SUBSTR(version, 1, 1) = '1' -- Filter the major version of the event
)
SELECT 
    json_extract_scalar(event_json, '$.data.data.event.customer_id') AS customer_id,
    json_extract_scalar(event_json, '$.data.data.event.task_id') AS task_id,
    json_extract_scalar(event_json, '$.data.data.event.document_code') AS document_code,
    json_extract_scalar(event_json, '$.data.data.event.tab') AS tab,
    json_extract_scalar(event_json, '$.data.data.event.has_private_text') AS has_private_text,
    json_extract_scalar(event_json, '$.data.data.event.has_public_content') AS has_public_content,
    json_extract_scalar(event_json, '$.data.data.event.has_public_text') AS has_public_text,
    json_extract_scalar(event_json, '$.data.data.event.snowplow_schema') AS snowplow_schema,
    json_extract_scalar(event_json, '$.data.data.event.referrer') AS referrer,
    json_extract_scalar(event_json, '$.data.data.event.uri') AS uri,
    dvce_created_tstamp,
    event,
    vendor,
    version,
    year,
    month,
    day
FROM 
    event_knowledge_base_view_private_content
;