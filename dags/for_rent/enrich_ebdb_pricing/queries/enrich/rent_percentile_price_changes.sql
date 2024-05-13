WITH percentile_price AS (
  SELECT
    aud.id_house,
    aud.rev,
    aud.p_10,
    aud.p_20,
    aud.p_30,
    aud.p_40,
    aud.p_50,
    aud.p_60,
    aud.p_70,
    aud.p_80,
    aud.p_90,
    aud.certainty,
    LAG(aud.p_10) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_p_10,
    LAG(aud.p_10) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_p_20,
    LAG(aud.p_10) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_p_30,
    LAG(aud.p_10) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_p_40,
    LAG(aud.p_10) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_p_50,
    LAG(aud.p_10) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_p_60,
    LAG(aud.p_10) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_p_70,
    LAG(aud.p_10) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_p_80,
    LAG(aud.p_90) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_p_90,
    LAG(aud.certainty) OVER (PARTITION BY aud.id_house ORDER BY ure.ts_revision) AS previous_certainty,
    MAX(ure.ts_revision) OVER (PARTITION BY DATE(ure.ts_revision), aud.id_house) = ure.ts_revision AS is_last_status_of_day,
    ure.ts_revision
  FROM
    datalake_ebdb_clean.house_predicted_price_aud AS aud
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON aud.rev = ure.id
  WHERE
    aud.business_context = 'RENT'
)

SELECT
  id_house,
  rev,
  p_10,
  p_20,
  p_30,
  p_40,
  p_50,
  p_60,
  p_70,
  p_80,
  p_90,
  certainty,
  is_last_status_of_day,
  ts_revision AS ts_price_started,
  LEAD(ts_revision) OVER (PARTITION BY id_house ORDER BY ts_revision) AS ts_price_ended
FROM
  percentile_price AS pp
WHERE
  (p_10 <> previous_p_10 OR previous_p_10 IS NULL)
  OR (p_20 <> previous_p_20 OR previous_p_20 IS NULL)
  OR (p_30 <> previous_p_30 OR previous_p_30 IS NULL)
  OR (p_40 <> previous_p_40 OR previous_p_40 IS NULL)
  OR (p_50 <> previous_p_50 OR previous_p_50 IS NULL)
  OR (p_60 <> previous_p_60 OR previous_p_60 IS NULL)
  OR (p_70 <> previous_p_70 OR previous_p_70 IS NULL)
  OR (p_80 <> previous_p_80 OR previous_p_80 IS NULL)
  OR (p_90 <> previous_p_90 OR previous_p_90 IS NULL)
  OR (certainty <> previous_certainty OR previous_certainty IS NULL)