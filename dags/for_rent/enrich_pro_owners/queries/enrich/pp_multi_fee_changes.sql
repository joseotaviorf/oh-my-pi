WITH administration_fee_changes AS (
  SELECT
    upo.id_user AS id_owner,
    aud.adm_fee AS administration_fee,
    LAG(aud.adm_fee) OVER (PARTITION BY upo.id_user ORDER BY aud.rev) AS previous_administration_fee,
    aud.is_active,
    LAG(aud.is_active) OVER (PARTITION BY upo.id_user ORDER BY aud.rev) AS previous_is_active,
    aud.rev,
    ure.ts_revision
  FROM
    datalake_ebdb_clean.pro_owner_fee_aud AS aud
  JOIN
    datalake_ebdb_clean.user_pro_owner AS upo
      ON aud.id_user_pro_owner = upo.id
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON aud.rev = ure.id
)

SELECT
  id_owner,
  administration_fee,
  is_active,
  MAX(ts_revision) OVER(PARTITION BY id_owner, DATE(ts_revision)) = ts_revision AS is_last_status_of_day,
  ts_revision AS ts_adm_fee_started,
  LEAD(ts_revision) OVER (PARTITION BY id_owner ORDER BY ts_revision) AS ts_adm_fee_ended
FROM
  administration_fee_changes
WHERE
  (administration_fee <> previous_administration_fee OR previous_administration_fee IS NULL)
  OR (is_active <> previous_is_active OR previous_is_active IS NULL)
