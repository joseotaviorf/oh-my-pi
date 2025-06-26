SELECT DISTINCT
  CAST(id_user AS BIGINT) AS id_user,
  CAST(
    GET_JSON_OBJECT(user_properties, '$.ab_beakman_conversational_platform_wall_e_experiment')
    AS INTEGER
   ) AS wall_e_rollout_flag
FROM
  datalake_amplitude_clean.events
WHERE
  MAKE_DATE(year, month, day) >= DATE('{load_start_date}')
  AND id_app = 170698
  AND id_user IS NOT NULL