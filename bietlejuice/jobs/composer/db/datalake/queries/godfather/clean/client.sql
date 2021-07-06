SELECT
 id,
 main_id as id_main,
 name,
 email,
 `version`,
 cellphone,
 login_hash,
 tenant_ongoing_offer,
 main_created_at as ts_main_created,
 main_updated_at as ts_main_updated,
 created_at as ts_created,
 updated_at as ts_updated
FROM datalake_godfather_raw.client
