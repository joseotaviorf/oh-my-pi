SELECT
    raw.id_event,
    raw.id_person,
    raw.id_user,
    raw.id_domain_user,
    raw.id_entity,
    raw.id_house,
    raw.id_contract,
    raw.application,
    raw.journey_step,
    raw.event_name,
    raw.event_properties,
    raw.user_properties,
    raw.enrichments,
    raw.ts_event,
    raw.ts_egw,
    raw.ts_egw_updated_at,
    raw.ts_ingested_at,
    CURRENT_TIMESTAMP() AS ts_load,
    DATE_FORMAT(raw.ts_event, 'yyyy-MM-dd') AS event_date
FROM
    datalake_cdp_raw.transactional_events AS raw
WHERE
    raw.ingestion_date >= DATE_FORMAT(TIMESTAMP('{load_start_date}'), 'yyyy-MM-dd-HH')
    AND raw.ingestion_date <= DATE_FORMAT(TIMESTAMP('{load_end_date}'), 'yyyy-MM-dd-HH')
