SELECT
    id,
    CAST(group_id AS BIGINT) AS id_group,
    requestor_id AS id_requestor,
    CAST(get_json_object(properties, '$.houseId') AS BIGINT) AS id_house,
    type,
    status,
    requestor_type,
    CAST(get_json_object(properties, '$.rentValue') AS DECIMAL(10,2)) AS rent_value,
    CAST(get_json_object(properties, '$.packageValue') AS DECIMAL(10,2)) AS package_value,
    get_json_object(result, '$.credit') AS credit_result,
    properties,
    result,
    created_at AS ts_created,
    updated_at AS ts_updated,
    expires_at AS ts_expires
FROM
    datalake_docx_raw.group_authorization
