SELECT
    id,
    uuid,
    person_uuid AS uuid_person,
    ip,
    type,
    user_agent,
    deal_id AS id_deal,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_lending_raw.user_consent