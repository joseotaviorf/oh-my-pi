SELECT
    raw.id_event,
    raw.id_person,
    raw.id_user,
    raw.id_domain_user,
    raw.id_anonymous,
    raw.id_dispatch,
    raw.user_type,
    raw.channel,
    raw.comms_type,
    raw.comms_typology,
    raw.comms_journey_step,
    raw.comms_status,
    raw.comms_name,
    raw.comms_rule,
    raw.comms_action,
    raw.comms_template,
    raw.comms_source,
    raw.application,
    raw.event_properties,
    raw.user_properties,
    raw.enrichments,
    raw.event_name,
    raw.ts_event,
    raw.ts_egw,
    raw.ts_egw_updated_at,
    raw.ts_ingested_at,
    CURRENT_TIMESTAMP() AS ts_load,
    DATE_FORMAT(raw.ts_event, 'yyyy-MM-dd') AS event_date
FROM
    datalake_cdp_raw.comms_events AS raw
WHERE
    raw.ingestion_date >= DATE_FORMAT(TIMESTAMP('{load_start_date}'), 'yyyy-MM-dd-HH')
    AND raw.ingestion_date <= DATE_FORMAT(TIMESTAMP('{load_end_date}'), 'yyyy-MM-dd-HH')
