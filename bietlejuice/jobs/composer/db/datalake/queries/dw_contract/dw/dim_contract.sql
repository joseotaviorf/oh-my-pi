WITH house_b2b_portability AS ( -- TODO [ODS] Move to an enrich
    SELECT
        hl.id_house_listing
    FROM
        datalake_ebdb_listing.house_listing hl
    JOIN
        datalake_ebdb_clean.house h
            ON h.id = hl.id_house
    JOIN
        datalake_ebdb_listing.portability p
            ON p.id_house = hl.id_house AND p.is_owner_b2b
    WHERE
        p.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, NOW())
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  c.id AS sk_contract,
  c.id AS id_contract,
  CAST(c.rent AS DECIMAL(14, 2)) AS rent,
  CAST(c.first_rent_charged AS DECIMAL(14, 2)) AS first_rent_charged,
  CAST(c.billing_day_of_month AS SMALLINT) AS day_month_due,
  c.guarantee_type AS guarantee,
  c.type,
  c.status,
  c.paying_condo AS condo_payer,
  c.responsible_for_condo AS condo_responsible,
  c.paying_iptu AS iptu_payer,
  c.responsible_for_iptu AS iptu_responsible,
  CAST(c.rental_guarantee_installment AS SMALLINT) AS rental_insurance_installments,
  CAST(c.rental_guarantee_value AS  DECIMAL(14, 2)) AS rental_insurance_value,
  CAST(c.home_insurance_installment AS SMALLINT) AS home_insurance_installments,
  CAST(c.home_insurance_value AS DECIMAL(14, 2)) AS home_insurance_value,
  CAST(c.fist_rent_comission_fee AS DECIMAL(14, 2)) AS first_rental_commission,
  CAST(c.monthly_administration_fee AS DECIMAL(5, 4)) AS monthly_administration_fee,
  CAST(c.condo_price AS DECIMAL(14, 2)) AS condo,
  CAST(c.iptu AS DECIMAL(14, 2)) AS iptu,
  CAST(c.tenant_service_fee AS DECIMAL(5, 2)) AS tenant_service_fee,
  c.signature_type,
  c.status_closing AS closing_status,
  c.cancellation_reason,
  c.contract_version AS version,
  (hp.id_house_listing IS NOT NULL) OR contract_b2b.is_b2b AS is_b2b,
  contract_b2b.is_contract_b2b,
  contract_b2b.contract_partner_type,
  contract_b2b.b2b_type,
  contract_b2b.b2b_prime_type,
  contract_b2b.contract_plan,
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
  CAST(c.ts_canceled AS TIMESTAMP) AS ts_canceled,
  c.ts_tenant_service_fee_opt_out,
  CAST(c.ts_analyst_annulment_input AS TIMESTAMP) AS ts_analyst_annulment_input,
  NOW() AS ts_load
FROM
    datalake_ebdb_contract.contract c
LEFT JOIN
    datalake_ebdb_contract.contract_b2b contract_b2b
        ON contract_b2b.id_contract = c.id
LEFT JOIN
    datalake_ebdb_listing.house_listing hl
	    ON hl.id_house = c.id_house
	    AND c.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01') AND COALESCE(hl.ts_listing_version_end, NOW())
LEFT JOIN
    house_b2b_portability hp
        ON hp.id_house_listing = hl.id_house_listing
