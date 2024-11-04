SELECT
    id,
    proposal_id AS id_proposal,
    house_id AS id_house,
    user_id AS id_user,
    city_id AS id_city,
    group_id AS id_group,
    scope,
    limit_value,
    proponent_group_type,
    reason,
    result,
    status,
    type,
    automatic,
    early_result,
    created_at AS ts_created,
    updated_at AS ts_updated,
    expires_at AS ts_expires
FROM
    datalake_docx_raw.credit_evaluation
