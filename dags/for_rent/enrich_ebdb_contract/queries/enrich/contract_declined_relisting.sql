WITH
listing_rent_model AS (
  SELECT
    t.id AS id_termination,
    c.id AS id_contract,
    c.id_house,
    h.id_user AS id_owner,
    MIN_BY(ure.id_user, ure.ts_revision) FILTER (WHERE NOT aud.is_early_relisting) AS id_user_modifier,
    c.is_relisting_enabled,
    MIN(aud.is_early_relisting) AS is_early_relisting,
    MIN(ure.ts_revision) FILTER (WHERE NOT aud.is_early_relisting) AS ts_revision
  FROM
    datalake_terminator_clean.termination AS t
  JOIN
    datalake_ebdb_contract.contract AS c
      ON t.id_contract = c.id
  JOIN
    datalake_ebdb_clean.listing_business_context AS lbc
      ON c.id_house = lbc.id_house
  JOIN
    datalake_ebdb_clean.listing_rent_model_aud AS aud
      ON lbc.id = aud.id_listing_business_context
  JOIN
    datalake_ebdb_user.user_revision_entity as ure
      ON aud.rev = ure.id
      AND ure.ts_revision BETWEEN t.ts_created AND DATEADD(DAY, 1, DATE(COALESCE(c.ts_analyst_annulment_input, c.dt_termination)))
  JOIN
    datalake_ebdb_clean.house AS h
      ON c.id_house = h.id
  WHERE
    t.ts_created >= '2024-09-15'
  GROUP BY ALL
),
contract_aud AS (
  SELECT
    t.id AS id_termination,
    aud.id_contract,
    aud.id_house,
    h.id_user AS id_owner,
    MIN_BY(ure.id_user, ure.ts_revision) FILTER (WHERE NOT aud.is_relisting_enabled) AS id_user_modifier,
    aud.is_relisting_enabled,
    DATE(t.ts_created) AS dt_termination_requested,
    MIN(ure.ts_revision) FILTER (WHERE NOT aud.is_relisting_enabled) AS ts_revision
  FROM
    datalake_terminator_clean.termination AS t
  JOIN
    datalake_ebdb_contract.contract AS c
      ON t.id_contract = c.id
  JOIN
    datalake_ebdb_clean.contract_aud AS aud
      ON t.id_contract = aud.id_contract
      AND aud.mod_is_relisting_enabled
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON ure.id = aud.rev
      AND ure.ts_revision BETWEEN t.ts_created AND DATEADD(DAY, 1, DATE(COALESCE(c.ts_analyst_annulment_input,c.dt_termination)))
  JOIN
    datalake_ebdb_clean.house AS h
      ON aud.id_house = h.id
  WHERE
    t.ts_created BETWEEN DATE('2024-05-18') AND DATE('2024-09-14')
    AND aud.mod_is_relisting_enabled
  GROUP BY ALL
),
unificated AS (
  SELECT
    id_termination,
    id_contract,
    id_house,
    id_user_modifier,
    CASE
      WHEN ts_revision IS NULL THEN NULL
      WHEN id_owner = id_user_modifier THEN 'DECLINED_BY_PP'
      WHEN id_owner != id_user_modifier THEN 'DECLINED_BY_CX/ENG'
      ELSE 'AUTO_DECLINED'
    END AS decline_person,
    is_relisting_enabled,
    NULL AS is_early_relisting,
    ts_revision
  FROM
    contract_aud
  UNION ALL
  SELECT
    id_termination,
    id_contract,
    id_house,
    id_user_modifier,
    CASE
      WHEN ts_revision IS NULL THEN NULL
      WHEN is_relisting_enabled
        AND NOT is_early_relisting
        AND id_owner = id_user_modifier THEN 'DECLINED_BY_PP'
      WHEN is_relisting_enabled
        AND NOT is_early_relisting
        AND id_owner != id_user_modifier THEN 'DECLINED_BY_CX/ENG'
      ELSE 'AUTO_DECLINED'
    END AS decline_person,
    is_relisting_enabled,
    is_early_relisting,
    ts_revision
  FROM
    listing_rent_model
)
SELECT
  u.id_termination,
  u.id_contract,
  u.id_house,
  u.id_user_modifier,
  u.decline_person,
  ch.country_code,
  u.is_relisting_enabled,
  u.is_early_relisting AS is_early_relisting_enabled,
  u.ts_revision AS ts_declined
FROM
  unificated AS u
JOIN
  datalake_ebdb_country.house AS ch
    ON u.id_house = ch.id_house
WHERE
  u.ts_revision IS NOT NULL
