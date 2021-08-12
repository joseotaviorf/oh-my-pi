WITH house_b2b_portability AS ( -- TODO [ODS] Move to an enrich
    SELECT
        hl.id_house_listing
    FROM datalake_ebdb_listing.house_listing hl
    JOIN datalake_ebdb_clean.house h
        ON h.id = hl.id_house
    JOIN datalake_ebdb_listing.portability p
        ON p.id_house = hl.id_house AND p.is_owner_b2b
    WHERE p.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, now())
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  c.id AS sk_contract,
  c.id AS id_contract,
  c.rent,
  c.billing_day_of_month AS day_month_due,
  c.guarantee_type AS guarantee,
  c.type,
  c.status,
  c.paying_condo AS condo_payer,
  c.responsible_for_condo AS condo_responsible,
  c.paying_iptu AS iptu_payer,
  c.responsible_for_iptu AS iptu_responsible,
  c.rental_guarantee_installment AS rental_insurance_installments,
  c.rental_guarantee_value AS rental_insurance_value,
  c.home_insurance_installment AS home_insurance_installments,
  c.home_insurance_value,
  c.fist_rent_comission_fee AS first_rental_commission,
  c.monthly_administration_fee,
  c.condo_price AS condo,
  c.iptu,
  c.tenant_service_fee,
  c.signature_type,
  c.status_closing AS closing_status,
  c.cancellation_reason,
  c.contract_version AS version,
  (hp.id_house_listing IS NOT NULL) OR contract_b2b.is_b2b AS is_b2b,
  contract_b2b.b2b_type,
  contract_b2b.b2b_prime_type,
  c.is_ongoing_contract,
  c.is_tenant_service_fee_opt_out,
  c.dt_started AS dt_start,
  c.dt_entered AS dt_entrance,
  c.dt_contract_expected_end AS dt_intended_end,
  c.dt_termination AS dt_annulment,
  c.ts_created,
  c.ts_updated,
  c.ts_signed AS ts_signature,
  c.ts_minuta_approved AS ts_draft_approved,
  c.ts_canceled,
  c.ts_tenant_service_fee_opt_out,
  c.ts_analyst_annulment_input,
  NOW() AS ts_load
FROM datalake_ebdb_contract.contract c
LEFT JOIN datalake_ebdb_contract.contract_b2b contract_b2b
    ON contract_b2b.id_contract = c.id
LEFT JOIN datalake_ebdb_listing.house_listing hl
	ON hl.id_house = c.id_house
	AND c.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01') AND COALESCE(hl.ts_listing_version_end, NOW())
LEFT JOIN house_b2b_portability hp
    ON hp.id_house_listing = hl.id_house_listing
