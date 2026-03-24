SELECT
    UserId AS id_user,
    AgentId AS id_agent,
    UserPermissionId AS id_user_permission,
    UserName AS user_name,
    Email AS email,
    Login AS login,
    PermissionDesc AS agent_profile,
    Activated AS is_activated,
    EnablePersonalTransfer is_enable_personal_transfer,
    flag_Agent AS is_agent,
    flag_Manager AS is_manager,
    flag_Supervisor AS is_supervisor,
    LastLogin AS ts_last_login,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.Users
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')