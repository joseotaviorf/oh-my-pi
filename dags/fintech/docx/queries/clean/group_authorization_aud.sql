SELECT
    id,
    CAST(group_id AS BIGINT) AS id_group,
    requestor_id AS id_requestor,
    CAST(GET_JSON_OBJECT(properties, '$.houseId') AS BIGINT) AS id_house,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    type,
    status,
    requestor_type,
    CAST(GET_JSON_OBJECT(properties, '$.rentValue') AS DECIMAL(10,2)) AS rent_value,
    CAST(GET_JSON_OBJECT(properties, '$.packageValue') AS DECIMAL(10,2)) AS package_value,
    GET_JSON_OBJECT(result, '$.credit') AS credit_result,
    properties,
    result,
    status_mod AS mod_status,
    properties_mod AS mod_properties,
    result_mod AS mod_result,
    expires_at_mod AS mod_ts_expired,
    expires_at AS ts_expired
FROM
    datalake_docx_raw.group_authorization_aud
