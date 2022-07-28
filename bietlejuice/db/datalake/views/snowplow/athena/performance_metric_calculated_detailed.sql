DROP VIEW IF EXISTS datalake_snowplow_raw_prod.performance_metric_calculated_detailed;
CREATE OR REPLACE VIEW datalake_snowplow_raw_prod.performance_metric_calculated_detailed AS
WITH event_performance_metric_calculated AS (
    SELECT json_extract_scalar(raw_event, '$.ue_derivated_context1') as event_json,
           json_extract_scalar(raw_event, '$.dvce_created_tstamp')   as dvce_created_tstamp,
           event,
           vendor,
           version,
           cast(year as integer)                                     as year,
           cast(month as integer)                                    as month,
           cast(day as integer)                                      as day
    FROM datalake_snowplow_raw_prod.events
    WHERE vendor = 'pwa-tenants'
      AND event = 'performance_metric_calculated'
      AND SUBSTR(version, 1, 1) = '1' -- Filter the major version of the event
)
SELECT json_extract_scalar(event_json, '$.data.data.event.metric_name')               as metric_name,
       json_extract_scalar(event_json, '$.data.data.event.metric_value')              as metric_value,
       json_extract_scalar(event_json, '$.data.data.event.connection_effective_type') as connection_effective_type,
       json_extract_scalar(event_json, '$.data.data.event.connection_type')           as connection_type,
       json_extract_scalar(event_json, '$.data.data.event.connection_save_data')      as connection_save_data,
       json_extract_scalar(event_json, '$.data.data.event.device_memory')             as device_memory,
       json_extract_scalar(event_json, '$.data.data.event.input_name')                as input_name,
       json_extract_scalar(event_json, '$.data.data.event.uri')                       as uri,
       dvce_created_tstamp,
       event,
       vendor,
       version,
       year,
       month,
       day
FROM event_performance_metric_calculated
;