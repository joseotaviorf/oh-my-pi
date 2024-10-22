SELECT
    id,
    user_id AS id_user,
    session_id AS id_session,
    user_phone,
    user_mode,
    department,
    request_call_status,
    requested_at AS ts_requested
FROM
    datalake_help_center_api_raw.t_call_request
WHERE
  MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY user_id, session_id ORDER BY ts_requested DESC) = 1
