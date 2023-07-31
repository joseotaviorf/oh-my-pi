WITH transactions_raw AS (
    SELECT 
        REVERSE(SPLIT(source_file, "/"))[0] || "-" || ROW_NUMBER() OVER (PARTITION BY source_file ORDER BY 1) AS id_itbi_transaction,
        IF(
          SIZE(SPLIT(address, ' - ')) IN (4, 5, 6, 7),
          IF(
            LEFT(REVERSE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '))[0],1) IN ('0','1','2','3','4','5','6','7','8','9'),
            ARRAY_JOIN(SLICE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '), 1, SIZE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' ')) - 1), ' '),
            ELEMENT_AT(SPLIT(address, ' - '), 1)
          ),
          'N/A'
        ) AS address,
        IF(
          SIZE(SPLIT(address, ' - ')) IN (5, 6, 7) AND LEFT(REVERSE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '))[0],1) IN ('0','1','2','3','4','5','6','7','8','9'),
          REVERSE(SPLIT(ELEMENT_AT(SPLIT(address, ' - '), 1),' '))[0],
          'N/A'
        ) AS number,
        CASE
          WHEN SIZE(SPLIT(address, ' - ')) = 6 THEN ELEMENT_AT(SPLIT(address, ' - '), 2)
          WHEN SIZE(SPLIT(address, ' - ')) = 7
          THEN ARRAY_JOIN(slice(SPLIT(address, ' - '), 2, 2), ' - ')
        END AS complement,
        IF(
          SIZE(SPLIT(address, ' - ')) IN (4, 5, 6, 7), 
          ELEMENT_AT(SPLIT(address, ' - '), SIZE(SPLIT(address, ' - ')) - 2), 
          'N/A'
        ) AS zipcode,
        IF(
          SIZE(SPLIT(address, ' - ')) IN (5, 6, 7), 
          ELEMENT_AT(SPLIT(address, ' - '), SIZE(SPLIT(address, ' - ')) - 3),
          'N/A'
        ) AS neighborhood,
        'Belo Horizonte' AS city,
        IF(
          SIZE(SPLIT(address, ' - ')) IN (4, 5, 6, 7),
          ELEMENT_AT(SPLIT(address, ' - '), SIZE(SPLIT(address, ' - '))),
          'N/A' 
        ) AS state,
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
        amount_tax_paid_summarized,
        NULLIF(year_built, 0) AS year_built,
        dt_transaction,
        dt_load,
        month,
        year
    FROM
        datalake_itbi_clean.itbi_bh
),
dejavu AS (
    SELECT 
        id_address,
        id_region,
        SPLIT(output_address, ', ')[0] AS address,
        SPLIT(SPLIT(output_address, ', ')[1], ' - ')[0] AS number,
        SPLIT(SPLIT(output_address, ', ')[1], ' - ')[1] AS neighborhood,
        SPLIT(output_address, ', ')[3] AS zipcode,
        latitude,
        longitude
    FROM 
        datalake_vespucio.dejavu
)
SELECT 
    t.id_itbi_transaction,
    COALESCE(d.id_region, z.id_region) AS id_region,
    COALESCE(d.address, INITCAP(t.address), z.address) AS address,
    COALESCE(d.number, t.number) AS number,
    INITCAP(t.complement) AS complement,
    COALESCE(d.zipcode, t.zipcode, z.zipcode) AS zipcode,
    COALESCE(r.name, d.neighborhood, z.neighborhood, t.neighborhood) AS neighborhood,
    COALESCE(t.city, z.city_name) AS city,
    d.latitude,
    d.longitude,
    t.state,
    t.occupation_description,
    t.standard_finish,
    t.urban_zoning_code,
    t.property_type,
    t.raw_source_address,
    t.source_file,
    t.land_area_m2,
    t.built_area_m2,
    t.all_units_area_m2,
    t.ideal_fraction,
    t.adopted_calculation_basis,
    t.amount_tax_paid_summarized,
    t.year_built,
    t.dt_transaction,
    t.dt_load,
    t.month,
    t.year
FROM 
    transactions_raw AS t
LEFT JOIN 
    dejavu AS d
        ON MD5(CONCAT(t.address, t.number, t.city)) = d.id_address
LEFT JOIN 
    datalake_region.region AS r 
        ON d.id_region = r.id
LEFT JOIN
    datalake_zipcodes.zipcodes AS z 
        ON t.zipcode = z.zipcode
WHERE 
    t.occupation_description = 'Residencial'
    AND t.year >= 2019
    AND z.city_name = 'Belo Horizonte'