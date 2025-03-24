SELECT
    id,
    external_id AS id_external,
    keycloak_token_id AS id_keycloak_token,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    name,
    email,
    phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_terminator_test_raw.application_user_aud
