SELECT
    id,
    agent_uuid AS uuid_agent,
    person_uuid AS uuid_person,
    partnership_representative_id AS id_partnership_representative,
    partnership_representative_type,
    affiliation_type,
    status,
    slug,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.agent 