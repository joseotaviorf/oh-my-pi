SELECT
    user_id AS id_user,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_help_center_api_raw.t_call_in_app_eligibility
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY user_id, status ORDER BY ts_created DESC) = 1
