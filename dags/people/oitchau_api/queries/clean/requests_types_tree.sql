SELECT
    uuid AS id_request_type,
    companyUuid AS id_company,
    requestTypeTemplateUuid AS id_request_type_template,
    externalId AS id_external,
    updatedBy AS id_updated_by_user,
    name AS request_type_name,
    active AS is_active,
    userDefined AS is_user_defined,
    createdAt AS ts_created,
    updatedAt AS ts_updated,
    deletedAt AS ts_deleted,
    subtypes AS request_subtypes,
    ts_load,
    year,
    month,
    day
FROM
    datalake_oitchau_raw.requests_types_tree
