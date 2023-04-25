SELECT
  a.id_user,
  MAX(a.ts_client_event) AS dt_last_event
FROM
  datalake_amplitude_clean_staging.170698_af_app_opened_events a
LEFT JOIN
  datalake_ebdb_user.user u
    ON a.id_user = u.id
WHERE
  id_user IS NOT NULL
  AND YEAR(CURRENT_DATE()) >= 2023
GROUP BY 1
