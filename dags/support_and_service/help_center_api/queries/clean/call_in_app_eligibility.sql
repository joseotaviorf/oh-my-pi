SELECT
    id AS id_user,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_help_center_api_raw.t_call_in_app_eligibility
