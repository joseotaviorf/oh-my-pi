SELECT
    id,
    prospect_uuid AS uuid_prospect,
    person_uuid AS uuid_person,
    legal_entity_type,
    status,
    business_association,
    quintoandar_knowledge,
    social,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.ProspectAgent