SELECT
    id,
    buyer_company_event_id AS id_buyer_company_event,
    person_uuid AS uuid_person,
    company_uuid AS uuid_company,
    type,
    is_active,
    started_at AS ts_started,
    finished_at AS ts_finished,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.buyer_company