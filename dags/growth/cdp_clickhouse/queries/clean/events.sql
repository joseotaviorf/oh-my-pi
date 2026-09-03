SELECT
    raw.id_event,
    raw.id_person,
    CAST(raw.id_user AS STRING) AS id_user,
    CAST(NULL AS STRING) AS id_house,
    CAST(NULL AS STRING) AS id_contract,
    raw.application,
    CAST(NULL AS STRING) AS journey_step,
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
    datalake_cdp_raw.user_tracking_events AS raw
WHERE
        raw.ingestion_date >= DATE_FORMAT(TIMESTAMP('{load_start_date}'), 'yyyy-MM-dd-HH')
        AND raw.ingestion_date <= DATE_FORMAT(TIMESTAMP('{load_end_date}'), 'yyyy-MM-dd-HH')

UNION ALL

SELECT
    raw.id_event,
    raw.id_person,
    CAST(raw.id_user AS STRING) AS id_user,
    CAST(raw.id_house AS STRING) AS id_house,
    CAST(raw.id_contract AS STRING) AS id_contract,
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

UNION ALL

SELECT
    raw.id_event,
    raw.id_person,
    CAST(raw.id_user AS STRING) AS id_user,
    CAST(NULL AS STRING) AS id_house,
    CAST(NULL AS STRING) AS id_contract,
    raw.application,
    CAST(NULL AS STRING) AS journey_step,
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
    datalake_cdp_raw.comms_events AS raw
WHERE
        raw.ingestion_date >= DATE_FORMAT(TIMESTAMP('{load_start_date}'), 'yyyy-MM-dd-HH')
        AND raw.ingestion_date <= DATE_FORMAT(TIMESTAMP('{load_end_date}'), 'yyyy-MM-dd-HH')
