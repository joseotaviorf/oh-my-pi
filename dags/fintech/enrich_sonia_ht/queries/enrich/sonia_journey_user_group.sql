WITH selecting_users as (
SELECT
  user_id,
  MAX(IF(group_name = 'Test', 1, 0)) AS is_test,
  MAX(IF(group_name = 'Control', 1, 0)) AS is_control
FROM datalake_sonia_ht.sonia_journey_log
WHERE group_name IN ('Test', 'Control')
GROUP BY user_id
)
SELECT
  user_id,
  IF(is_test > 0, 'Test', 'Control') AS group_name,
  CASE
    WHEN is_test > 0 AND is_control = 0 THEN 'Test'
    WHEN is_test = 0 AND is_control > 0 THEN 'Control'
    WHEN is_test > 0 AND is_control > 0 THEN 'Error - Both'
  END AS group_name_full
FROM selecting_users
