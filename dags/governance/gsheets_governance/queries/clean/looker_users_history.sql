SELECT 
    user_email,
    'looker' AS platform,
    history_created_date AS ts_entered
FROM datalake_gsheets_raw.looker_users_history