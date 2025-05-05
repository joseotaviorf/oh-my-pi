WITH b2b_user AS (
  SELECT
    u.id AS id_user,
    pa.status AS partner_agent_status,
    p.type AS partner_type
  FROM
    datalake_ebdb_clean.user AS u
  LEFT JOIN
    datalake_ebdb_clean.partner_agent AS pa
      ON u.id = pa.id_user
  LEFT JOIN
    datalake_ebdb_clean.partner AS p
      ON pa.id_partner = p.id
),

house_portability AS (
  SELECT
    hl.id_house,
    hl.ts_listing_version_start,
    hl.ts_listing_version_end
  FROM
    datalake_ebdb_listing.house_listing hl
  JOIN
    datalake_ebdb_clean.portability por
      ON por.id_house = hl.id_house
      AND por.owner_type = 'B2B'
      AND por.ts_created >= COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00')
      AND por.ts_created < COALESCE(hl.ts_listing_version_end, NOW())
),

user_merge AS (
  SELECT
    id_user,
    EXPLODE(predecessor_user_list) AS id_predecessor_user
  FROM
    datalake_ebdb_user.user_merge
),

owner_houses_history AS (
  SELECT /*+ RANGE_JOIN(hbh, 2000) */
    h.id AS id_house,
    COALESCE(um.id_user, hbh.id_user) AS id_owner,
    ur.country_code,
    IF(lbc.is_rent_context OR lbc.id_house IS NULL, TRUE, FALSE) AS is_for_rent,
    IF((((hbh.affiliate_type = 'B2BPartner') OR (pa.id_partner IS NOT NULL AND p.type = 'PRIME') OR (hbh.id_house_listing IS NOT NULL)) AND pa.status = 'ACTIVE'), TRUE, FALSE) OR por.id_house IS NOT NULL AS is_b2b,
    IF(um.id_user IS NOT NULL, TRUE, FALSE) AS is_merged_user,
    por.id_house IS NOT NULL AS is_portability,
    rl.rental_administrator,
    hls.status_history,
    hls.status_change_reason,
    dd.date
  FROM
    datalake_ebdb_clean.house AS h
  CROSS JOIN
    datalake_quintoandar.aux_date AS dd
  LEFT JOIN
    datalake_ebdb_listing.rent_listing AS rl
      ON h.id = rl.id_house
  LEFT JOIN
    datalake_pro_owners.house_b2b_history  AS hbh
      ON h.id = hbh.id_house
      AND dd.date >= DATE(hbh.ts_started)
      AND dd.date < DATE(COALESCE(hbh.ts_ended, CURRENT_TIMESTAMP()))
  LEFT JOIN
    datalake_ebdb_listing.house_listing_status AS hls
      ON h.id = hls.id_house
      AND dd.date >= DATE(hls.ts_status_started)
      AND dd.date < DATE(COALESCE(hls.ts_status_ended, CURRENT_TIMESTAMP()))
  LEFT JOIN
    datalake_ebdb_listing.listing_business_context AS lbc
      ON h.id = lbc.id_house
  LEFT JOIN
    user_merge AS um
      ON um.id_predecessor_user = hbh.id_user
  LEFT JOIN
    datalake_ebdb_clean.partner_agent AS pa
      ON COALESCE(um.id_user, hbh.id_user) = pa.id_user
  LEFT JOIN
    datalake_ebdb_clean.partner AS p
      ON pa.id_partner = p.id
  LEFT JOIN
    house_portability AS por
      ON h.id = por.id_house
      AND dd.date >= DATE(COALESCE(por.ts_listing_version_start, '1900-01-01 00:00:00'))
      AND dd.date < DATE(COALESCE(por.ts_listing_version_end, CURRENT_TIMESTAMP()))
  LEFT JOIN
    datalake_ebdb_country.user AS ur
      ON hbh.id_user = ur.id_user
  WHERE
    dd.date = MAKE_DATE({year}, {month}, {day})
    AND ur.country_code = 'BR'
),

owner_qtd_houses_rental_administrator AS (
  SELECT
    id_owner,
    country_code,
    COUNT(DISTINCT IF(status_history IN ('alugado', 'publicado', 'suspenso', 'SUSPENDED', 'PUBLISHED'), id_house, NULL)) AS ongoing_houses,
    COUNT(DISTINCT IF(status_history IN ('edicao', 'EDITING'), id_house, NULL)) AS houses_in_edition,
    COUNT(DISTINCT IF(status_history IN ('excluido', 'OPTED_OUT'), id_house, NULL)) AS houses_opted_out,
    COUNT(DISTINCT IF(status_history IN ('publicado', 'PUBLISHED'), id_house, NULL)) AS houses_published,
    COUNT(DISTINCT IF(status_history = 'suspenso'
      OR (status_history = 'SUSPENDED' AND status_change_reason != 'RENTED'), id_house, NULL)) AS houses_suspended,
    COUNT(DISTINCT IF(status_history = 'alugado'
      OR (status_history = 'SUSPENDED' AND status_change_reason = 'RENTED'), id_house, NULL)) AS houses_rented,
    COUNT(DISTINCT IF(status_history IN ('despublicado', 'UNPUBLISHED'), id_house, NULL)) AS houses_unpublished,
    COUNT(DISTINCT id_house) AS total_houses,
    IF(rental_administrator = 'OWNER', COUNT(DISTINCT id_house), 0) AS brokerage_only_houses,
    IF(rental_administrator = 'QUINTOANDAR', COUNT(DISTINCT id_house), 0) AS quintoandar_houses,
    IF(rental_administrator = 'THIRD_PARTY', COUNT(DISTINCT id_house), 0) AS third_party_houses,
    is_merged_user,
    date AS dt_houses_owned
  FROM
    owner_houses_history
  WHERE
    is_for_rent = True
    AND is_b2b = False
  GROUP BY 1,2,14,15,rental_administrator
),

owner_qtd_houses AS (
  SELECT
    id_owner,
    country_code,
    SUM(houses_published) AS houses_published,
    SUM(houses_suspended) AS houses_suspended,
    SUM(houses_rented) AS houses_rented,
    SUM(houses_unpublished) AS houses_unpublished,
    SUM(houses_in_edition) AS houses_in_edition,
    SUM(houses_opted_out) AS houses_opted_out,
    SUM(ongoing_houses) AS ongoing_houses,
    SUM(total_houses) AS total_houses,
    SUM(brokerage_only_houses) AS brokerage_only_houses,
    SUM(quintoandar_houses) AS quintoandar_houses,
    SUM(third_party_houses) AS third_party_houses,
    is_merged_user,
    dt_houses_owned
  FROM
    owner_qtd_houses_rental_administrator
  GROUP BY 1,2,14,15
),

pp_multi_history AS (
  SELECT /*+ RANGE_JOIN(aud, 50000) */
    COALESCE(um.id_user, aud.id_user) AS id_owner,
    aud.id_account_manager,
    aud.is_active,
    DATE(FROM_UNIXTIME(ure.ts_revision/1000)) AS dt_event,
    LEAD(DATE(FROM_UNIXTIME(ure.ts_revision/1000))) OVER (PARTITION BY COALESCE(um.id_user, aud.id_user) ORDER BY aud.rev) AS dt_next_event
  FROM
    datalake_ebdb_clean.user_pro_owner_aud AS aud
  LEFT JOIN
    datalake_ebdb_clean.user_revision_entity AS ure
      ON aud.rev = ure.id
  LEFT JOIN
    user_merge AS um
      ON aud.id_user = um.id_predecessor_user
)

SELECT /*+ RANGE_JOIN(oqh, 800) */
  oqh.id_owner,
  IF(ppm.is_active, ppm.id_account_manager, NULL) AS id_account_manager,
  oqh.country_code,
  oqh.houses_published,
  oqh.houses_suspended,
  oqh.houses_rented,
  oqh.houses_unpublished,
  oqh.houses_in_edition,
  oqh.houses_opted_out,
  oqh.ongoing_houses,
  oqh.total_houses,
  oqh.brokerage_only_houses,
  oqh.quintoandar_houses,
  oqh.third_party_houses,
  oqh.is_merged_user,
  IF(ppm.id_owner IS NOT NULL AND ppm.is_active, TRUE, FALSE) AS is_pp_multi_active,
  oqh.dt_houses_owned,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  owner_qtd_houses AS oqh
LEFT JOIN
  pp_multi_history AS ppm
    ON oqh.id_owner = ppm.id_owner
    AND oqh.dt_houses_owned >= dt_event
    AND oqh.dt_houses_owned < COALESCE(dt_next_event, CURRENT_DATE())
