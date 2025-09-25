-- Early filter the owners that don't have at least 5 potential ongoing houses
WITH owners_to_process AS (
  SELECT
    id_owner
  FROM
    datalake_rental_historical_follow_up.house_listings_daily_info
  GROUP BY
    id_owner
  HAVING
    COUNT(DISTINCT id_house) >= 5
),
daily_house_listing AS (
  SELECT
    hldi.id_owner,
    COALESCE(l.dejavuid, CAST(hldi.id_house AS STRING)) AS uniqueid,
    hldi.id_house,
    IF(c.status = 'Ativo', TRUE, FALSE) AS has_ongoing_contract,
    CASE
      WHEN
        hldi.status_history = 'alugado'
        OR (
          hldi.status_history = 'SUSPENDED'
          AND hldi.status_change_reason = 'RENTED'
        )
      THEN
        'RENTED'
      WHEN hldi.status_history IN ('edicao', 'EDITING') THEN 'EDITING'
      WHEN hldi.status_history IN ('excluido', 'OPTED_OUT') THEN 'OPTED_OUT'
      WHEN hldi.status_history IN ('publicado', 'PUBLISHED') THEN 'PUBLISHED'
      WHEN hldi.status_history IN ('despublicado', 'UNPUBLISHED') THEN 'UNPUBLISHED'
      WHEN
        hldi.status_history = 'suspenso'
        OR (
          hldi.status_history = 'SUSPENDED'
          AND hldi.status_change_reason != 'RENTED'
        )
      THEN
        'SUSPENDED'
      ELSE 'OTHER'
    END AS status,
    hldi.year,
    hldi.month,
    hldi.day
  FROM
    datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
      JOIN
        owners_to_process AS otp
        ON hldi.id_owner = otp.id_owner
      LEFT JOIN
        vespucio_prod_delta.listings AS l
        ON l.source_id::bigint = hldi.id_house
      LEFT JOIN 
        datalake_ebdb_contract.contract AS c
        ON c.id_house = hldi.id_house
          AND c.is_ongoing_contract = true
),
daily_owner_stats AS (
  SELECT
    id_owner,
    uniqueid,
    collect_set(id_house) AS id_houses,
    COUNT_IF(has_ongoing_contract) AS ongoing_contracts,
    CASE
      WHEN array_contains(collect_set(status), 'RENTED') THEN 'RENTED'
      WHEN array_contains(collect_set(status), 'SUSPENDED') THEN 'SUSPENDED'
      WHEN array_contains(collect_set(status), 'PUBLISHED') THEN 'PUBLISHED'
      WHEN array_contains(collect_set(status), 'EDITING') THEN 'EDITING'
      WHEN array_contains(collect_set(status), 'UNPUBLISHED') THEN 'UNPUBLISHED'
      WHEN array_contains(collect_set(status), 'OPTED_OUT') THEN 'OPTED_OUT'
      ELSE 'OTHER'
    END AS status,
    year,
    month,
    day
  FROM
    daily_house_listing
  GROUP BY
    ALL
),
pp_multi_daily_stats AS (
  SELECT
    id_owner,
    collect_list(struct(uniqueid, id_houses, status)) AS houses,
    CASE
      WHEN MAKE_DATE(year, month, day) = DATE('{load_start_date}')  THEN 'ACTIVE'
      WHEN MAKE_DATE(year, month, day) >= DATE('{load_start_date}') - INTERVAL '2' YEAR THEN 'POTENTIAL'
      ELSE 'LIFETIME'
    END AS classification_window,
    make_date(year, month, day) AS stats_date,
    SUM(ongoing_contracts) AS ongoing_contracts,
    COUNT_IF(status = 'RENTED') AS houses_rented,
    COUNT_IF(status = 'SUSPENDED') AS houses_suspended,
    COUNT_IF(status = 'PUBLISHED') AS houses_published,
    COUNT_IF(status = 'EDITING') AS houses_in_edition,
    COUNT_IF(status = 'OPTED_OUT') AS houses_opted_out,
    COUNT_IF(status = 'UNPUBLISHED') AS houses_unpublished,
    COUNT(uniqueid) AS total_houses
  FROM
    daily_owner_stats
  GROUP BY
    ALL
),
pp_multi_classification_window AS (
  SELECT
    id_owner,
    classification_window,
    MAX_BY(houses, stats_date) AS houses,
    MAX(GREATEST(houses_rented, ongoing_contracts) + houses_suspended + houses_published) AS max_ongoing_houses,
    MAX(houses_rented) AS max_houses_rented,
    MAX(houses_suspended) AS max_houses_suspended,
    MAX(houses_published) AS max_houses_published,
    MAX(houses_in_edition) AS max_houses_in_edition,
    MAX(houses_opted_out) AS max_houses_opted_out,
    MAX(houses_unpublished) AS max_houses_unpublished,
    MAX(total_houses) AS max_total_houses
  FROM
    pp_multi_daily_stats
  GROUP BY
    ALL
),
pp_multi_stats AS (
  SELECT
    id_owner,
    active_houses,
    active_ongoing_houses,
    active_houses_in_edition,
    active_houses_opted_out,
    active_houses_published,
    active_houses_suspended,
    active_houses_rented,
    active_houses_unpublished,
    active_total_houses,
    two_year_max_houses,
    two_year_max_ongoing_houses,
    two_year_max_houses_in_edition,
    two_year_max_houses_opted_out,
    two_year_max_houses_published,
    two_year_max_houses_suspended,
    two_year_max_houses_rented,
    two_year_max_houses_unpublished,
    two_year_max_total_houses,
    lifetime_max_houses,
    lifetime_max_ongoing_houses,
    lifetime_max_houses_in_edition,
    lifetime_max_houses_opted_out,
    lifetime_max_houses_published,
    lifetime_max_houses_suspended,
    lifetime_max_houses_rented,
    lifetime_max_houses_unpublished,
    lifetime_max_total_houses
  FROM
    pp_multi_classification_window
      PIVOT (
        MAX(houses) AS houses,
        MAX(max_ongoing_houses) AS ongoing_houses,
        MAX(max_houses_rented) AS houses_rented,
        MAX(max_houses_suspended) AS houses_suspended,
        MAX(max_houses_published) AS houses_published,
        MAX(max_houses_in_edition) AS houses_in_edition,
        MAX(max_houses_opted_out) AS houses_opted_out,
        MAX(max_houses_unpublished) AS houses_unpublished,
        MAX(max_total_houses) AS total_houses FOR classification_window IN (
          'ACTIVE' AS active,
          'POTENTIAL' AS two_year_max,
          'LIFETIME' AS lifetime_max
        )
      )
  WHERE
    active_ongoing_houses >= 5
    OR two_year_max_ongoing_houses >= 5
    OR lifetime_max_ongoing_houses >= 5
),
pp_multi_houses AS (
  SELECT DISTINCT
    pms.id_owner,
    exploded_id_house AS id_house
  FROM
    pp_multi_stats AS pms
    LATERAL VIEW EXPLODE(pms.active_houses) exploded_houses_table AS house_struct
    LATERAL VIEW EXPLODE(house_struct.id_houses) exploded_ids_table AS exploded_id_house
  UNION
  SELECT DISTINCT
    pms.id_owner,
    exploded_id_house AS id_house
  FROM
    pp_multi_stats AS pms
    LATERAL VIEW EXPLODE(pms.two_year_max_houses) exploded_houses_table AS house_struct
    LATERAL VIEW EXPLODE(house_struct.id_houses) exploded_ids_table AS exploded_id_house
  UNION
  SELECT DISTINCT
    pms.id_owner,
    exploded_id_house AS id_house
  FROM
    pp_multi_stats AS pms
    LATERAL VIEW EXPLODE(pms.lifetime_max_houses) exploded_houses_table AS house_struct
    LATERAL VIEW EXPLODE(house_struct.id_houses) exploded_ids_table AS exploded_id_house
),
pp_multi_visits AS (
  SELECT
    pmh.id_owner,
    COALESCE(NULLIF(COUNT(b.id), 0), 0) AS total_visits,
    COALESCE(
      COUNT_IF(
        b.status = 'Cancelado'
        AND b.reason_category = 'Owner'
      ),
      0
    ) AS canceled_visits,
    COALESCE(canceled_visits / total_visits, 0) AS owner_cancellation_rate
  FROM
    pp_multi_houses AS pmh
      LEFT JOIN 
        datalake_booking.booking AS b
        ON pmh.id_house = b.id_house
        AND b.is_visit = TRUE
        AND b.ts_booking_utc >= DATE('{load_start_date}') - INTERVAL '150' DAYS
  GROUP BY
    pmh.id_owner
),
key_location_stats AS (
  SELECT
    pmh.id_owner,
    COALESCE(
      MAX(
        CASE
          WHEN he.key_location = 'AGENT' THEN 1
          ELSE 0
        END
      ) = 1,
      false
    ) AS agent_had_key
  FROM
    pp_multi_houses AS pmh
  LEFT JOIN
    datalake_ebdb_listing.house_entrance AS he
        ON pmh.id_house = he.id_house
  GROUP BY
    pmh.id_owner
),
contract_stats AS (
  SELECT
    pmh.id_owner,
    COALESCE(
      MAX(
        CASE
          WHEN c.status IN ('Ativo', 'Finalizado') THEN 1
          ELSE 0
        END
      ) = 1,
      false
    ) AS has_owner_singed_contract
  FROM
    pp_multi_houses AS pmh
  LEFT JOIN
    datalake_ebdb_contract.contract AS c
      ON pmh.id_house = c.id_house
  GROUP BY
    pmh.id_owner
),
possible_fraud AS (
  SELECT
    pmv.id_owner,
    pmv.total_visits,
    pmv.canceled_visits,
    pmv.owner_cancellation_rate,
    kls.agent_had_key,
    cs.has_owner_singed_contract,
    IF(pmv.total_visits - pmv.canceled_visits <= 0 
      AND kls.agent_had_key = FALSE
      AND cs.has_owner_singed_contract = FALSE, TRUE, FALSE
    ) AS is_possible_fraud
  FROM
    pp_multi_visits pmv
  JOIN
    key_location_stats kls
      ON pmv.id_owner = kls.id_owner
  JOIN
    contract_stats cs
      ON pmv.id_owner = cs.id_owner
)
SELECT
  pms.id_owner,
  ---
  CASE
    WHEN pms.active_ongoing_houses >= 5 THEN 'ACTIVE'
    WHEN pms.two_year_max_ongoing_houses >= 5 THEN 'POTENTIAL'
    ELSE 'LIFETIME'
  END AS pp_multi_classification,
  ---
  pms.active_houses AS houses,
  pms.two_year_max_houses,
  pms.lifetime_max_houses,
  ---
  COALESCE(pms.active_ongoing_houses, 0) AS ongoing_houses,
  COALESCE(pms.active_houses_in_edition, 0) AS houses_in_edition,
  COALESCE(pms.active_houses_opted_out, 0) AS houses_opted_out,
  COALESCE(pms.active_houses_published, 0) AS houses_published,
  COALESCE(pms.active_houses_suspended, 0) AS houses_suspended,
  COALESCE(pms.active_houses_rented, 0) AS houses_rented,
  COALESCE(pms.active_houses_unpublished, 0) AS houses_unpublished,
  COALESCE(pms.active_total_houses, 0) AS total_houses,
  ---
  COALESCE(pms.two_year_max_ongoing_houses, 0) AS two_year_max_ongoing_houses,
  COALESCE(pms.two_year_max_houses_in_edition, 0) AS two_year_max_houses_in_edition,
  COALESCE(pms.two_year_max_houses_opted_out, 0) AS two_year_max_houses_opted_out,
  COALESCE(pms.two_year_max_houses_published, 0) AS two_year_max_houses_published,
  COALESCE(pms.two_year_max_houses_suspended, 0) AS two_year_max_houses_suspended,
  COALESCE(pms.two_year_max_houses_rented, 0) AS two_year_max_houses_rented,
  COALESCE(pms.two_year_max_houses_unpublished, 0) AS two_year_max_houses_unpublished,
  COALESCE(pms.two_year_max_total_houses, 0) AS two_year_max_total_houses,
  ---
  COALESCE(pms.lifetime_max_ongoing_houses, 0) AS lifetime_max_ongoing_houses,
  COALESCE(pms.lifetime_max_houses_in_edition, 0) AS lifetime_max_houses_in_edition,
  COALESCE(pms.lifetime_max_houses_opted_out, 0) AS lifetime_max_houses_opted_out,
  COALESCE(pms.lifetime_max_houses_published, 0) AS lifetime_max_houses_published,
  COALESCE(pms.lifetime_max_houses_suspended, 0) AS lifetime_max_houses_suspended,
  COALESCE(pms.lifetime_max_houses_rented, 0) AS lifetime_max_houses_rented,
  COALESCE(pms.lifetime_max_houses_unpublished, 0) AS lifetime_max_houses_unpublished,
  COALESCE(pms.lifetime_max_total_houses, 0) AS lifetime_max_total_houses,
  ---
  pf.total_visits,
  pf.canceled_visits,
  pf.owner_cancellation_rate,
  pf.agent_had_key,
  pf.has_owner_singed_contract,
  pf.is_possible_fraud,
  ---
  EXTRACT(YEAR FROM DATE('{load_start_date}')) AS year,
  EXTRACT(MONTH FROM DATE('{load_start_date}')) AS month,
  EXTRACT(DAY FROM DATE('{load_start_date}')) AS day
FROM
  pp_multi_stats AS pms
LEFT JOIN
  possible_fraud AS pf
    ON pf.id_owner = pms.id_owner