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

owner_houses_history AS (
  SELECT
    h.id AS id_house,
    hbh.id_user AS id_owner,
    ur.country_code,
    IF(lbc.is_rent_context OR lbc.id_house IS NULL, TRUE, FALSE) AS is_for_rent,
    IF((((hbh.affiliate_type = 'B2BPartner') OR (pa.id_partner IS NOT NULL AND p.type = 'PRIME') OR (hbh.id_house_listing IS NOT NULL)) AND pa.status = 'ACTIVE'), TRUE, FALSE) OR por.id_house IS NOT NULL AS is_b2b,
    IF(um.id_winner_account IS NOT NULL, TRUE, FALSE) AS is_merged_user,
    por.id_house IS NOT NULL AS is_portability,
    rl.rental_administrator,
    hls.status_history,
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
      AND dd.date < COALESCE(DATE(hbh.ts_ended), CURRENT_TIMESTAMP())
  LEFT JOIN
    datalake_ebdb_listing.house_listing_status AS hls
      ON h.id = hls.id_house
      AND dd.date >= hls.ts_status_started
      AND dd.date < COALESCE(hls.ts_status_ended, CURRENT_TIMESTAMP())
  LEFT JOIN
    datalake_ebdb_listing.listing_business_context AS lbc
      ON h.id = lbc.id_house
  LEFT JOIN
    datalake_ebdb_clean.user_merge AS um
      ON hbh.id_user = um.id_loser_account
  LEFT JOIN
    datalake_ebdb_clean.partner_agent AS pa
      ON COALESCE(um.id_winner_account, hbh.id_user) = pa.id_user
  LEFT JOIN
    datalake_ebdb_clean.partner AS p
      ON pa.id_partner = p.id
  LEFT JOIN 
    house_portability AS por
      ON h.id = por.id_house
      AND dd.date >= COALESCE(por.ts_listing_version_start, '1900-01-01 00:00:00')
      AND dd.date < COALESCE(DATE(por.ts_listing_version_end), CURRENT_TIMESTAMP())
  LEFT JOIN 
    datalake_ebdb_country.user AS ur
      ON hbh.id_user = ur.id_user
  WHERE 
    dd.date < CURRENT_DATE()
    AND status_history IN ('alugado', 'publicado', 'suspenso')
    AND ur.country_code = 'BR'
),

owner_qtd_houses_rental_administrator AS (
  SELECT
    id_owner,
    country_code,
    COUNT(DISTINCT id_house) AS houses,
    IF(rental_administrator = 'OWNER', COUNT(DISTINCT id_house), 0) AS brokerage_only_houses,
    IF(rental_administrator = 'QUINTOANDAR', COUNT(DISTINCT id_house), 0) AS quintoandar_houses,
    is_merged_user,
    date AS dt_houses_owned
  FROM 
    owner_houses_history
  WHERE 
    is_for_rent = True
    AND is_b2b = False
  GROUP BY 1,2,6,7,rental_administrator
),

owner_qtd_houses AS (
  SELECT
    id_owner,
    country_code,
    SUM(houses) AS houses,
    SUM(brokerage_only_houses) AS brokerage_only_houses,
    SUM(quintoandar_houses) AS quintoandar_houses,
    is_merged_user,
    dt_houses_owned
  FROM 
    owner_qtd_houses_rental_administrator
  GROUP BY 1,2,6,7
)
  
SELECT
  id_owner,
  country_code,
  houses,
  LAG(brokerage_only_houses) OVER (PARTITION BY id_owner ORDER BY dt_houses_owned) AS brokerage_only_previous_houses,
  brokerage_only_houses,
  LAG(quintoandar_houses) OVER (PARTITION BY id_owner ORDER BY dt_houses_owned) AS quintoandar_previous_houses,
  quintoandar_houses,
  is_merged_user,
  dt_houses_owned
FROM 
  owner_qtd_houses