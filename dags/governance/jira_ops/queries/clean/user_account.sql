SELECT
    accountId AS id_account,
    accountType AS account_type,
    emailAddress AS email_address,
    displayName AS display_name,
    locale AS locale,
    timeZone AS time_zone,
    groups,
    applicationRoles AS application_roles,
    avatarUrls AS avatar_urls,
    CAST(active AS BOOLEAN) AS is_active,
    dt_load,
    year,
    month,
    day
FROM
    datalake_jira_ops_raw.user_account
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
