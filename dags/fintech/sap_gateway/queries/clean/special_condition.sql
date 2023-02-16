SELECT
    id              AS id_special_condition,
    `name`          AS special_condition_name,
    `description`   AS special_condition_description,
    created_at      AS ts_created,
    updated_at      AS ts_updated
FROM
    datalake_sap_gateway_raw.special_condition
