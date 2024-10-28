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
