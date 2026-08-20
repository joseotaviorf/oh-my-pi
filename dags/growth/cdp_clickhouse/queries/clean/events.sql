SELECT
    raw.event_id AS id_event,
    raw.person_uuid AS id_person,
    raw.user_id AS id_user,
    raw.house_id AS id_house,
    raw.contract_id AS id_contract,
    raw.egw_event_type,
    LOWER(raw.application) AS application,
    raw.journey_step,
    LOWER(raw.event_name) AS event_name,
    raw.event_properties,
    raw.user_properties,
    raw.enrichments,
    TIMESTAMP_MILLIS(raw.timestamp) AS ts_event,
    TIMESTAMP_MILLIS(raw.egw_timestamp) AS ts_egw,
    TIMESTAMP_MILLIS(raw.egw_updated_at) AS ts_egw_updated_at,
    raw.ts_ingested_at,
    CURRENT_TIMESTAMP() AS ts_load,
    DATE_FORMAT(TIMESTAMP_MILLIS(raw.timestamp), 'yyyy-MM-dd') AS dt
FROM
    datalake_cdp_raw.events AS raw
WHERE
    raw.dt >= DATE_FORMAT(TIMESTAMP('{load_start_date}'), 'yyyy-MM-dd-HH')
    AND raw.dt <= DATE_FORMAT(TIMESTAMP('{load_end_date}'), 'yyyy-MM-dd-HH')
