SELECT
    id,
    intent_uuid AS uuid_intent,
    person_uuid AS uuid_person,
    last_completed_step,
    payload AS payload_json,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.broker_accreditation_intent
