WITH hub_member_profile AS (
  SELECT
    id,
    id_user,
    id_business_unit,
    profile,
    is_active,
    ts_created AS ts_relation_agent_hub_start,
    rev,
    CASE
      WHEN
        LEAD(id_business_unit) OVER(PARTITION BY id_user ORDER BY rev) != id_business_unit
        AND is_active = TRUE
        AND LEAD(is_active) OVER(PARTITION BY id_user ORDER BY rev) = TRUE
      THEN
        LEAD(ts_created) OVER(PARTITION BY id_user ORDER BY rev)
      WHEN
        LEAD(ts_created) OVER(PARTITION BY id_user, id_business_unit ORDER BY ts_created) IS NULL AND is_active = FALSE
      THEN
        ts_created
      WHEN
        LEAD(ts_created) OVER(PARTITION BY id_user, id_business_unit ORDER BY ts_created) IS NULL AND is_active = TRUE
      THEN
        CURRENT_DATE()
      ELSE
        LEAD(ts_created) OVER(PARTITION BY id_user, id_business_unit ORDER BY ts_created)
    END AS ts_relation_agent_hub_end
  FROM
    datalake_hub_services_clean.member_profile_aud
  WHERE
    profile in ('AGENT','NEGOTIATION_EXECUTIVE')
    AND (mod_id_business_unit = TRUE OR mod_active = TRUE)

),
hub_services_users AS (
  SELECT
    id,
    id_external,
    email,
    phone_number
  FROM
    datalake_hub_services_clean.users
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
),
business_unit AS (
  SELECT
    bu.id AS id_business_unit,
    bu.hub_name,
    bur.id_region,
    r.city_group,
    r.city_name,
    r.short_region_name,
    bu.lead_types,
    bu.business_context
  FROM
    datalake_hub_services_clean.business_unit AS bu
  LEFT JOIN datalake_hub_services_clean.business_unit_region AS bur
    ON bu.id = bur.id_business_unit
  LEFT JOIN datalake_region.region AS r
    ON bur.id_region = CAST(r.id AS INT)
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY bu.id, bu.business_context ORDER BY bu.ts_updated DESC) = 1
),
user_aud AS (
  SELECT
    id_user,
    id_agent,
    name,
    cpf,
    main_phone,
    secondary_phone,
    email
  FROM
    datalake_ebdb_clean.user_aud
  WHERE
    rev_type != 2
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY rev DESC) = 1
),
unified_users AS (
  SELECT
    um.id_loser_account,
    ul.id_agent AS id_agent_loser_account,
    um.id_winner_account,
    uw.id_agent AS id_agent_winner_account,
    um.ts_updated AS ts_merged_success
  FROM
    datalake_ebdb_clean.user_merge AS um
  LEFT JOIN
    user_aud AS ul
      ON um.id_loser_account = ul.id_user
  LEFT JOIN
    user_aud AS uw
      ON um.id_winner_account = uw.id_user
  WHERE
    status = 'MERGED'
    AND ( ul.id_agent IS NOT NULL
    OR uw.id_agent IS NOT NULL )
),
main AS (
SELECT DISTINCT
  mu.id_agent,
  mu.id AS id_user_agent,
  mp.id_business_unit,
  bu.id_region,
  u.email AS hub_service_email,
  u.phone_number AS hub_service_phone,
  mu.main_phone AS main_phone,
  CASE
    WHEN mu.secondary_phone != mu.main_phone
      THEN mu.secondary_phone
    ELSE NULL
  END AS main_secondary_phone,
  mu.email AS main_email,
  mu.cpf AS main_cpf,
  bu.business_context,
  bu.hub_name,
  bu.city_group,
  bu.city_name,
  bu.short_region_name,
  bu.lead_types,
  mp.profile,
  CASE
    WHEN
      LEAD(mp.id_business_unit) OVER(PARTITION BY mu.id_agent ORDER BY rev) != mp.id_business_unit
      AND mp.is_active = TRUE
      AND LEAD(mp.is_active) OVER(PARTITION BY mu.id_agent ORDER BY rev) = TRUE
    THEN FALSE
    ELSE mp.is_active
  END AS is_active,
  mp.rev AS revision,
  EXPLODE(SEQUENCE(CAST(mp.ts_relation_agent_hub_start AS DATE),CAST(mp.ts_relation_agent_hub_end AS DATE))) AS ts_agent_hub_relation_date
FROM
  hub_member_profile AS mp
LEFT JOIN
  hub_services_users AS u
    ON mp.id_user = u.id
LEFT JOIN
  business_unit AS bu
    ON mp.id_business_unit = bu.id_business_unit
LEFT JOIN
  unified_users AS uu
    ON u.id_external = uu.id_loser_account
LEFT JOIN
  datalake_ebdb_clean.user AS mu
    ON COALESCE(uu.id_winner_account,u.id_external) = mu.id AND COALESCE(mu.id_agent,0) != 0
WHERE
  mu.id_agent IS NOT NULL
  AND bu.business_context = 'SALE'
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY mp.id_user, mp.id_business_unit, ts_agent_hub_relation_date ORDER BY mp.is_active) = 1
)
SELECT
  CONCAT(id_agent,REPLACE(ts_agent_hub_relation_date, '-', '')) AS id_snapshot,
  id_agent,
  id_user_agent,
  id_business_unit,
  id_region,
  hub_service_email,
  hub_service_phone,
  main_phone,
  main_secondary_phone,
  main_email,
  main_cpf,
  business_context,
  hub_name,
  city_group,
  city_name,
  short_region_name,
  lead_types,
  profile,
  is_active,
  revision,
  ts_agent_hub_relation_date
FROM main
