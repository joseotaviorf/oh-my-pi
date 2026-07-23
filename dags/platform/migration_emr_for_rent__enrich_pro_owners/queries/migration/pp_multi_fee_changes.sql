WITH historical_fee_changes AS (
  SELECT
    upo.id_user AS id_owner,
    aud.adm_fee AS administration_fee,
    LAG(aud.adm_fee) OVER (PARTITION BY upo.id_user ORDER BY aud.rev) AS previous_administration_fee,
    aud.is_active,
    LAG(aud.is_active) OVER (PARTITION BY upo.id_user ORDER BY aud.rev) AS previous_is_active,
    ure.ts_revision AS ts_change
  FROM
    datalake_ebdb_clean.pro_owner_fee_aud AS aud
  JOIN
    datalake_ebdb_clean.user_pro_owner AS upo
      ON aud.id_user_pro_owner = upo.id
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON aud.rev = ure.id
  WHERE
    ure.ts_revision < TIMESTAMP '2026-03-30'
),
filtered_historical_fee_changes AS (
  SELECT
    id_owner,
    administration_fee,
    is_active,
    ts_change
  FROM
    historical_fee_changes
  WHERE
    (administration_fee <> previous_administration_fee OR previous_administration_fee IS NULL)
    OR (is_active <> previous_is_active OR previous_is_active IS NULL)
),
new_fee_changes AS (
  SELECT
    u.id AS id_owner,
    pal.new_adm_fee AS administration_fee,
    CAST(pal.is_new_fee_active AS BOOLEAN) AS is_active,
    pal.ts_created AS ts_change
  FROM
    datalake_rental_management_clean.pp_multi_audit_log AS pal
  JOIN
    datalake_rental_management_clean.pp_multi_user AS pmu
      ON pal.id_pp_multi_user = pmu.id
  JOIN
    datalake_ebdb_clean.user AS u
      ON u.uuid_person = pmu.person_uuid
  WHERE
    pal.ts_created >= TIMESTAMP '2026-03-30'
    AND pal.new_adm_fee IS NOT NULL
    AND (
      (pal.new_adm_fee <> pal.previous_adm_fee OR pal.previous_adm_fee IS NULL)
      OR (pal.is_new_fee_active <> pal.is_previous_fee_active OR pal.is_previous_fee_active IS NULL)
    )
),
all_fee_changes AS (
  SELECT * FROM filtered_historical_fee_changes
  UNION ALL
  SELECT * FROM new_fee_changes
)

SELECT
  id_owner,
  administration_fee,
  is_active,
  MAX(ts_change) OVER(PARTITION BY id_owner, DATE(ts_change)) = ts_change AS is_last_status_of_day,
  ts_change AS ts_adm_fee_started,
  LEAD(ts_change) OVER (PARTITION BY id_owner ORDER BY ts_change) AS ts_adm_fee_ended
FROM
  all_fee_changes
