SELECT 
    id,
    email,
    first_name,
    last_name,
    sso_source,
    is_active,
    is_superuser,
    is_qbnewb,
    is_datasetnewb,
    date_joined as ts_joined,
    last_login as ts_last_login,
    updated_at as ts_updated,
    year,
    month,
    day
FROM 
  datalake_metabase_raw.core_user
