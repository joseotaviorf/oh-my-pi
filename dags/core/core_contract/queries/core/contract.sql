-- id_owner rule:
-- COALESCE(u.id, h.id_user) ensures we always resolve an owner_id.
-- Primary source: house_listing_relation (related_as='PROPERTY_OWNER').
-- Caveats: id_related may be id_user or uuid_person.
-- When uuid_person, we map it to id_user via EBDB.User.
-- Fallback: h.id_user from House to avoid missing owners.
SELECT
  SHA2(CONCAT_WS("||", 'CONTRACT', ct.id), 256) AS sk_core_contract,
  ct.id AS id_contract,
  ct.id_house,
  ct.id_user AS id_tenant,
  COALESCE(u.id, h.id_user) AS id_owner,
  ct.id_proposal,
  ct.status,
  COALESCE(ct.contract_rent_model:rentalAdministrator, 'QUINTOANDAR') AS rental_administrator,
  ct.paying_condo,
  ct.responsible_for_condo,
  ct.paying_iptu,
  ct.responsible_for_iptu,
  ct.signature_type, 
  ct.status_closing, 
  COALESCE(ct.is_relisting_enabled, FALSE) AS is_relisting_enabled,
  ct.rent,
  ct.iptu,
  ct.rental_guarantee_installment,
  ct.rental_guarantee_value,
  ct.home_insurance_installment,
  ct.home_insurance_value,
  ct.fist_rent_comission_fee AS first_rent_comission_fee,
  ct.tenant_service_fee,
  ct.agent_brokerage_share,
  ct.dt_started,
  ct.dt_entered,
  ct.dt_termination,
  ct.ts_contract_expected_end,
  ct.ts_signed,
  ct.ts_expected_termination,
  ct.ts_minuta_approved,
  ct.ts_created,
  ct.ts_updated
FROM 
  datalake_ebdb_test_clean.contract AS ct
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = ct.id_house
LEFT JOIN
    datalake_ebdb_clean.house_listing_relation AS hl
        ON hl.id = ct.id_house
        AND hl.related_as = 'PROPERTY_OWNER'
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON (u.id = hl.id_related
        OR u.uuid_person = hl.id_related)
