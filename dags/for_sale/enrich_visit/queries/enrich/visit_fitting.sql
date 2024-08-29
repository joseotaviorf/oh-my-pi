SELECT
  vf.id,
  vf.id_visit,
  vf.id_visitor,
  lh.id_user AS id_owner,
  vf.id_house,
  hl.id_house_listing,
  hl.country_code,
  vf.business_context,
  vf.intention,
  vf.status,
  vf.channel,
  vf.request_context,
  vf.dt_visit AS dt_visit_desired,
  TO_UTC_TIMESTAMP(
        (
            CAST(vf.dt_visit AS TIMESTAMP)
            + FLOOR((vf.begin_slot * 15 / 60)+8) * INTERVAL 1 HOURS
            + ABS(vf.begin_slot * 15 % 60) * INTERVAL 1 MINUTES
        ),
        COALESCE(ct.default_timezone, 'UTC')
    ) AS ts_visit_desired_begin_local_tz,
  TO_UTC_TIMESTAMP(
        (
            CAST(vf.dt_visit AS TIMESTAMP)
            + FLOOR((vf.end_slot * 15 / 60)+8) * INTERVAL 1 HOURS
            + ABS(vf.end_slot * 15 % 60) * INTERVAL 1 MINUTES
        ),
        COALESCE(ct.default_timezone, 'UTC')
    ) AS ts_visit_desired_end_local_tz,
  vf.ts_expiration,
  vf.ts_created
FROM
  datalake_ebdb_clean.visit_fitting AS vf
INNER JOIN
    datalake_ebdb_listing.house_listing AS hl
        ON vf.id_house = hl.id_house
        AND vf.ts_created >= hl.ts_listing_version_start
        AND (vf.ts_created <= hl.ts_listing_version_end
          OR hl.ts_listing_version_end IS NULL)
INNER JOIN
    datalake_ebdb_clean.country AS ct
        ON ct.code = hl.country_code
INNER JOIN
    datalake_ebdb_listing.house AS lh
        ON lh.id = vf.id_house
