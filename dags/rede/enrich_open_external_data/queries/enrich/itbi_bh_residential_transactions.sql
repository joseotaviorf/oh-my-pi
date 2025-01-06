WITH itbi_bh_enriched AS (
  SELECT
    /* The ID is created by reversing the source file path, taking the first part, and appending it with
      the row number within each source file. */
    REVERSE(SPLIT(source_file, "/"))[0] || "-" || ROW_NUMBER() OVER (PARTITION BY source_file ORDER BY 1) AS id_itbi_transaction_source,
    'ITBI_BH' AS itbi_region,
    'BR' AS address_country,
    IF(
      SIZE(SPLIT(address, ' - ')) IN (4, 5, 6, 7),
      ELEMENT_AT(SPLIT(address, ' - '), SIZE(SPLIT(address, ' - '))),
      'N/A'
    ) AS address_state,
    'Belo Horizonte' AS address_city,
    INITCAP(
      IF(
        SIZE(SPLIT(address, ' - ')) IN (5, 6, 7),
        -- If the size allows, the third-to-last element is extracted as the neighborhood:
        ELEMENT_AT(SPLIT(address, ' - '), SIZE(SPLIT(address, ' - ')) - 3),
        -- If not, it's labeled as 'N/A':
        'N/A'
      )
    ) AS address_neighborhood,
    INITCAP(
      IF(
        -- If the address has at least 4 components:
        SIZE(SPLIT(address, ' - ')) IN (4, 5, 6, 7),
        -- Checking if the last element may represent a number, if so, joining the rest of the elements as street name:
        IF(
          LEFT(REVERSE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '))[0],1) IN ('0','1','2','3','4','5','6','7','8','9'),
          ARRAY_JOIN(SLICE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '), 1, SIZE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' ')) - 1), ' '),
          -- Otherwise, considering the whole element as street name:
          ELEMENT_AT(SPLIT(address, ' - '), 1)
        ), 'N/A'
      )
    ) AS address_street_name,
    IF(
      SIZE(SPLIT(address, ' - ')) IN (5, 6, 7) AND LEFT(REVERSE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '))[0],1) IN ('0','1','2','3','4','5','6','7','8','9'),
      -- If the last element appears to be a number, it's extracted as the address number:
      REVERSE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '))[0],
      -- If not, it's labeled as 'N/A':
      'N/A'
    ) AS address_number,
    INITCAP(
      CASE
        -- If there are 6 elements, the second one is considered as the complement:
        WHEN SIZE(SPLIT(address, ' - ')) = 6 THEN ELEMENT_AT(SPLIT(address, ' - '), 2)
        -- If there are 7 elements, the second and third ones are joined as the complement:
        WHEN SIZE(SPLIT(address, ' - ')) = 7
        THEN ARRAY_JOIN(slice(SPLIT(address, ' - '), 2, 2), ' - ')
      END
    ) AS address_complement,
    IF(
      SIZE(SPLIT(address, ' - ')) IN (4, 5, 6, 7),
      -- If the size is appropriate, the second-to-last element is extracted as the zipcode:
      ELEMENT_AT(SPLIT(address, ' - '), SIZE(SPLIT(address, ' - ')) - 2),
      -- If not, it's labeled as 'N/A':
      'N/A'
    ) AS address_zipcode,
    INITCAP(occupation_description) AS occupation_description,
    standard_finish,
    urban_zoning_code,
    CASE
      WHEN predominant_construction_type = 'AP' THEN 'Residencial Vertical'
      ELSE 'Residencial Horizontal'
    END AS property_type,
    address AS raw_source_address,
    source_file,
    land_area_m2,
    built_area_m2,
    all_units_area_m2,
    ideal_fraction,
    adopted_calculation_basis,
    declared_transaction_value,
    amount_tax_paid_summarized,
    NULLIF(year_built, 0) AS year_built,
    month,
    year,
    TIMESTAMP(dt_transaction) AS ts_transaction,
    TIMESTAMP(dt_load) AS ts_load
FROM
  datalake_itbi_clean.itbi_bh
WHERE
    INITCAP(occupation_description) = 'Residencial'
    AND year >= 2019
)
SELECT
    id_itbi_transaction_source,
    MD5(
      CONCAT_WS('',
                COALESCE(ts_transaction, ''),
                COALESCE(address_country, ''),
                COALESCE(address_state, ''),
                COALESCE(address_city, ''),
                COALESCE(address_neighborhood, ''),
                COALESCE(address_street_name, ''),
                COALESCE(address_number, ''),
                COALESCE(address_complement, ''),
                COALESCE(address_zipcode, '')
            )
    ) AS id_address_transaction,
    itbi_region,
    address_country,
    address_state,
    address_city,
    address_neighborhood,
    address_street_name,
    address_number,
    address_complement,
    address_zipcode,
    occupation_description,
    standard_finish,
    urban_zoning_code,
    property_type,
    raw_source_address,
    source_file,
    land_area_m2,
    built_area_m2,
    all_units_area_m2,
    ideal_fraction,
    adopted_calculation_basis,
    declared_transaction_value,
    amount_tax_paid_summarized,
    year_built,
    month,
    year,
    ts_transaction,
    ts_load
FROM
    itbi_bh_enriched AS ibhe
