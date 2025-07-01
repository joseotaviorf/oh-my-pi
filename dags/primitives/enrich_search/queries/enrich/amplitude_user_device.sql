WITH merged_users AS (
  SELECT
    id_amplitude,
    id_amplitude_merged
  FROM
  	datalake_amplitude_clean.170698_user_merge

  GROUP BY 1,2
),

spv AS (
  SELECT
    id_user,
    id_device,
    id_amplitude,
    year

  FROM
     datalake_amplitude_clean.170698_search_page_viewed_events

  UNION ALL

  SELECT
    id_user,
    id_device,
    id_amplitude,
    year
  FROM
     datalake_amplitude_clean.170698_search_results_page_viewed_events

),

clean_spv AS (
  SELECT
    id_user,
    id_device,
    id_amplitude
  FROM
     spv
  WHERE
     id_amplitude <> 0
     AND year >= 2021

  GROUP BY 1,2,3
)

SELECT
  coalesce(mu.id_amplitude_merged, cspv.id_amplitude) AS id_amplitude_main,
  cspv.id_amplitude,
  cspv.id_user,
  cspv.id_device
FROM
    clean_spv cspv
LEFT JOIN
    merged_users mu
  ON
    cspv.id_amplitude = mu.id_amplitude
