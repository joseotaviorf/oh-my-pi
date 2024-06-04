SELECT
  REPLACE(
    SUBSTR(CAST(olsl.sk_house_listing AS STRING), 1, 9) || CAST(week_start AS STRING),
    '-',
    ''
  ) AS id_house_week,
  olsl.sk_house_listing,
  olsl.week_start,
  olsl.weeks_since_publication,
  olsl.status_change_reason
FROM dw_datamarts.ongoing_listed_suspended_listings AS olsl
LEFT JOIN dw_rent.fact_house_listings AS fhl
  ON fhl.sk_house_listing = olsl.sk_house_listing
WHERE
  olsl.week_start > DATE_ADD(CURRENT_DATE, -180)
  AND olsl.status_history IN ('publicado', 'PUBLISHED')
  AND fhl.sk_region > 0