WITH itbi_sp AS (
  SELECT
    id_address_transaction,
    MAX(itbi_region) AS itbi_region,
    MAX(address_country) AS address_country,
    MAX(address_state) AS address_state,
    MAX(address_city) AS address_city,
    MAX(address_neighborhood) AS address_neighborhood,
    MAX(address_street_name) AS address_street_name,
    MAX(address_number) AS address_number,
    MAX(address_complement) AS address_complement,
    MAX(address_reference) AS address_reference,
    MAX(address_zipcode) AS address_zipcode,
    MAX(iptu_use_description) AS iptu_use_description,
    MAX(iptu_standard_description) AS property_type,
    MAX(land_area_m2) AS land_area_m2,
    MAX(built_area_m2) AS built_area_m2,
    MAX(ideal_fraction) AS ideal_fraction,
    MAX(declared_transaction_value) AS declared_transaction_value,
    MAX(reference_appraisal_value) AS reference_appraisal_value,
    MAX(transmitted_proportion) AS transmitted_proportion,
    MAX(proportional_reference_appraisal_value) AS proportional_reference_appraisal_value,
    MAX(adopted_calculation_basis) AS adopted_calculation_basis,
    MAX(year_built) AS year_built,
    MAX(ts_transaction) AS ts_transaction,
    MAX(ts_load) AS ts_load
  FROM
    datalake_open_external_data.itbi_sp_residential_transactions
  GROUP BY ALL
),
itbi_bh AS (
  SELECT
    id_address_transaction,
    MAX(itbi_region) AS itbi_region,
    MAX(address_country) AS address_country,
    MAX(address_state) AS address_state,
    MAX(address_city) AS address_city,
    MAX(address_neighborhood) AS address_neighborhood,
    MAX(address_street_name) AS address_street_name,
    MAX(address_number) AS address_number,
    MAX(address_complement) AS address_complement,
    'NA' AS address_reference,
    MAX(address_zipcode) AS address_zipcode,
    'NA' AS iptu_use_description,
    MAX(property_type) AS property_type,
    MAX(land_area_m2) AS land_area_m2,
    MAX(built_area_m2) AS built_area_m2,
    MAX(ideal_fraction) AS ideal_fraction,
    MAX(declared_transaction_value) AS declared_transaction_value,
    NULL AS reference_appraisal_value,
    NULL AS transmitted_proportion,
    NULL AS proportional_reference_appraisal_value,
    MAX(adopted_calculation_basis) AS adopted_calculation_basis,
    MAX(year_built) AS year_built,
    MAX(ts_transaction) AS ts_transaction,
    MAX(ts_load) AS ts_load
  FROM
    datalake_open_external_data.itbi_bh_residential_transactions
  GROUP BY ALL
)
SELECT
  *
FROM
  itbi_sp
UNION ALL
SELECT
  *
FROM
  itbi_bh
