SELECT
    eval_item_id AS id_eval_item,
    eval_section_id AS id_eval_section,
    reference_item_id AS id_reference_item,
    business_group_id AS id_business_group,
    evaluation_id AS id_evaluation,
    perf_rating_model_id AS id_performance_rating_model,
    description AS item_description,
    owned_by,
    created_by,
    last_updated_by AS updated_by,
    mandatory_flag = 'Y' AS is_mandatory,
    critical_flag = 'Y' AS is_critical,
    not_rated_flag = 'Y' AS is_not_rated,
    added_in_task = 'Y' AS is_added_in_task,
    CAST(object_version_number AS INT) AS object_version_number,
    CAST(creation_date AS TIMESTAMP) AS ts_created,
    CAST(last_update_date AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_performance_raw.hra_eval_items
