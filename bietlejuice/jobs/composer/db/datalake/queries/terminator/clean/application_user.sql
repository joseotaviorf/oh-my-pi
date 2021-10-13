SELECT  
    id,
    external_id AS id_external,
    keycloak_token_id AS id_keycloak_token,
    name,
    email,
    phone,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_terminator_raw.application_user