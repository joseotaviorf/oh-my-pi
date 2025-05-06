WITH bic_users AS (
  SELECT DISTINCT
    id_user,
    make_date(uss.year, uss.month, uss.day) AS dt_snapshot,
    main_phone,
    is_tenant_post_contract,
    is_landlord_post_contract,
    ljs.has_published_listings,
    CASE
      WHEN (is_tenant_post_contract = TRUE OR is_landlord_post_contract = TRUE OR ljs.has_published_listings = TRUE) THEN FALSE
      ELSE TRUE
    END AS eligible
  FROM
    datalake_ss_logic_model.user_ss_metrics uss
  LEFT JOIN
    datalake_landlord_journey.landlord_journey_step AS ljs
      ON uss.id_user = ljs.id_owner
      AND uss.id_snapshot = ljs.id_snapshot
),
outbound AS (
  SELECT DISTINCT
    id_lead,
    ('+55' || phone_number) AS phone_number,
    make_date(year,month,day) AS dt_call,
    date_add(current_date(), -90) AS dt_cut
  FROM
    datalake_olos_dialer.outbound_contact_attempts
),
base AS (
  SELECT DISTINCT
    o.*,
    bic.id_user AS id_user_bic,
    bic.main_phone AS main_phone_bic,
    bic.is_tenant_post_contract,
    bic.is_landlord_post_contract,
    bic.has_published_listings,
    bic.eligible
  FROM
    outbound AS o
  LEFT JOIN
    bic_users AS bic
      ON bic.main_phone = o.phone_number
      AND o.dt_call = bic.dt_snapshot
)
SELECT DISTINCT
  main_phone_bic AS phone_number,
  COLLECT_SET(id_user_bic) AS users,
  MAX(is_tenant_post_contract) AS is_tenant_post_contract,
  MAX(is_landlord_post_contract) AS is_landlord_post_contract,
  MAX(COALESCE(has_published_listings, FALSE)) AS has_published_listings,
  "inside_sales" AS whitelist_group
FROM
  base
WHERE
  eligible = TRUE
  AND dt_call >= dt_cut
GROUP BY 1
