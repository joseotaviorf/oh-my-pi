SELECT
    review_period_id AS id_review_period,
    business_group_id AS id_business_group,
    status_code,
    created_by,
    last_updated_by AS updated_by,
    object_version_number,
    start_date AS dt_started,
    end_date AS dt_ended,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hrt_review_periods_b
