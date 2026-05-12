SELECT
    id,
    prospect_uuid AS uuid_prospect,
    intent_uuid AS uuid_intent,
    person_uuid AS uuid_person,
    company_uuid AS uuid_company,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.broker_accreditation_prospect
