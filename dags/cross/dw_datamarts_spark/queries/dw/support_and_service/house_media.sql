WITH max_video_revision_by_house AS (
  SELECT
    aud.external_domain,
    aud.id_external_domain,
    MAX(CAST(ts_revised AS TIMESTAMP)) AS ts_last_revised
  FROM
    datalake_kodak_clean.video_aud AS aud
  JOIN
    datalake_kodak_clean.user_revision_entity AS ure
      ON
        aud.rev = ure.id
    GROUP BY 1, 2
),
videos AS (
  WITH listings_with_videos AS (
    SELECT
        v.id_external_domain AS id_house,
        COUNT(*) AS number_of_videos
    FROM
      datalake_kodak_clean.video AS v
    WHERE
      v.external_domain = 'HOUSE'
      AND
        v.id_source IS NOT NULL
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
    datalake_kodak_clean.photo_sphere_aud AS aud
  JOIN
    datalake_kodak_clean.user_revision_entity AS ure
      ON
        aud.rev = ure.id
    GROUP BY 1, 2
),
photos AS (
  WITH listings_with_photos AS (
    SELECT
        p.id_external_domain AS id_house,
        CAST(FILTER(
          COLLECT_LIST(
            REPLACE(TRIM(LOWER(
              CAST(get_json_object(p.metadata, '$.description') AS string)  -- extract json
            )), ' ', '-')  -- slugify strings by trim, lower, and replace spaces for hypens
          ) -- aggregate into an array
        , x -> x IS NOT NULL) as string) AS description_360_photos,  -- filter out null strings
        count(*) as number_of_360_photos
    FROM
      datalake_kodak_clean.photo_sphere AS p
    WHERE
      p.external_domain = 'HOUSE'
        AND
          p.path IS NOT NULL
      GROUP BY 1
  )
  SELECT
      p.id_house,
      p.description_360_photos,
      p.number_of_360_photos,
      r.ts_last_revised
  FROM
    listings_with_photos AS p
  LEFT JOIN
    max_photo_revision_by_house AS r
      ON p.id_house = r.id_external_domain
)
SELECT
  CAST(COALESCE(v.id_house, p.id_house) AS string) AS id_house,
  CAST(COALESCE(v.number_of_videos, 0) AS string) AS number_of_videos,
  CAST(COALESCE(p.number_of_360_photos, 0) AS string) AS number_of_360_photos,
  CAST(p.description_360_photos AS string) AS description_360_photos,
  DATE_FORMAT(v.ts_last_revised, "yyyy-MM-dd HH:mm:ss.000") AS ts_video_last_updated,
  DATE_FORMAT(p.ts_last_revised, "yyyy-MM-dd HH:mm:ss.000") AS ts_360_photos_last_updated,
  DATE_FORMAT(NOW(), "yyyy-MM-dd HH:mm:ss.000") AS ts_load
FROM
  videos AS v
FULL OUTER JOIN
  photos AS p
    ON
      v.id_house = p.id_house
