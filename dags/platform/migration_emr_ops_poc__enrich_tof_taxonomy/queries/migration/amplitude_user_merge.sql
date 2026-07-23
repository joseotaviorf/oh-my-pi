WITH id_merge AS (
  SELECT DISTINCT
    id_amplitude_merged,
    id_amplitude
  FROM
    datalake_amplitude_clean.170698_user_merge
),
id_users AS (
  SELECT DISTINCT
    id_amplitude AS id_amplitude_merged,
    id_user
  FROM
    datalake_online_attribution.events_exploded
  WHERE NULLIF(id_user, '') IS NOT NULL
)
SELECT DISTINCT
  iu.id_amplitude_merged,
  iu.id_user,
  im.id_amplitude AS id_amplitude_all
FROM
  id_users AS iu
LEFT JOIN
  id_merge AS im
    ON im.id_amplitude_merged = iu.id_amplitude_merged
UNION ALL
SELECT DISTINCT
  iu.id_amplitude_merged AS id_amplitude_merged,
  iu.id_user,
  iu.id_amplitude_merged AS id_amplitude_all
FROM
  id_users AS iu

