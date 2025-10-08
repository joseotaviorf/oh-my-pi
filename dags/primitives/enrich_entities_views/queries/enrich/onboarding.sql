SELECT
  ob.id AS id_entity,
  ct.id_house,
  ct.id_tenant,
  ct.id_owner,
  ob.id_contrato AS id_contract,
  'FR_ONBOARDING' AS entity,
  'RENT' AS business_context,
  ob.status,
  CASE
    WHEN ob.status IN ('Finished', 'Aborted') THEN FALSE
    ELSE TRUE
  END AS is_active,
  ob.ts_created,
  ob.ts_updated
FROM
  datalake_ebdb_clean.onboarding AS ob
LEFT JOIN
    core_contract.contract AS ct
        ON ob.id_contrato = ct.id_contract