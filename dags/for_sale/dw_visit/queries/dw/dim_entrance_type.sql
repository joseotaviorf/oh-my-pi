SELECT
  id AS sk_entrance_type,
  GET_JSON_OBJECT(details,'$.accessAuthorizationTypeUtilized') AS utilized_access_type,
  GET_JSON_OBJECT(details,'$.currentAccessAuthorizationType') AS current_access_type,
  problem AS entrance_problem,
  is_successful,
  GET_JSON_OBJECT(details,'$.entranceOccurredWithSavedAccessAuthorization') AS has_occured_with_saved_access_authorization,
  NOW() AS ts_load
FROM
  datalake_ebdb_clean.entrance
