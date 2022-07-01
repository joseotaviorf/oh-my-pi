WITH max_video_revision_by_house AS (
  SELECT
    aud.external_domain,
    aud.id_external_domain,
    MAX(CAST(ts_revised AS TIMESTAMP)) AS ts_last_revised
  FROM
    datalake_kodak_clean_prod.video_aud AS aud
  JOIN
    datalake_kodak_clean_prod.user_revision_entity AS ure
      ON aud.rev = ure.id
  GROUP BY 1, 2
),
videos AS (
  WITH listings_with_videos AS (
    SELECT
        v.id_external_domain AS id_house,
        COUNT(*) AS number_of_videos
    FROM
      datalake_kodak_clean_prod.video AS v
    WHERE
      v.external_domain = 'HOUSE'
      AND v.id_source IS NOT NULL
    GROUP BY 1
  )
  SELECT
      v.id_house,
      v.number_of_videos,
      r.ts_last_revised
  FROM
    listings_with_videos AS v
  LEFT JOIN
    max_video_revision_by_house AS r
      ON v.id_house = r.id_external_domain
),
max_photo_revision_by_house AS (
  SELECT
    aud.external_domain,
    aud.id_external_domain,
    MAX(CAST(ts_revised AS TIMESTAMP)) AS ts_last_revised
  FROM
    datalake_kodak_clean_prod.photo_sphere_aud AS aud
  JOIN
    datalake_kodak_clean_prod.user_revision_entity AS ure
      ON aud.rev = ure.id
  GROUP BY 1, 2
),
photos AS (
  WITH listings_with_photos AS (
    SELECT
      p.id_external_domain AS id_house,
      FILTER(
        ARRAY_AGG(
          REPLACE(
            TRIM(
              LOWER(
                CAST(JSON_EXTRACT(p.metadata, '$.description') AS VARCHAR)  -- extract json
            )), ' ', '-')  -- slugify strings by trim, lower, and replace spaces for hypens
          ) -- aggregate into an array
        , x -> x IS NOT NULL) AS description_360_photos,  -- filter out null strings
        COUNT(*) AS number_of_360_photos
    FROM
      datalake_kodak_clean_prod.photo_sphere AS p
    WHERE
      p.external_domain = 'HOUSE'
      AND p.path IS NOT NULL
    GROUP BY 1
  )
  SELECT
      p.id_house,
      p.description_360_photos,
      p.number_of_360_photos,
      r.ts_last_revised
  FROM
    listings_with_photos AS p
  LEFT JOIN max_photo_revision_by_house AS r
      ON p.id_house = r.id_external_domain
)
SELECT
  COALESCE(v.id_house, p.id_house) AS id_house,
  COALESCE(v.number_of_videos, 0) AS number_of_videos,
  COALESCE(p.number_of_360_photos, 0) AS number_of_360_photos,
  CAST(p.description_360_photos AS VARCHAR(10000)) AS description_360_photos,
  v.ts_last_revised AS ts_video_last_updated,
  p.ts_last_revised AS ts_360_photos_last_updated,
  NOW() AS ts_load
FROM
  videos AS v
FULL OUTER JOIN
  photos AS p
    ON v.id_house = p.id_house
