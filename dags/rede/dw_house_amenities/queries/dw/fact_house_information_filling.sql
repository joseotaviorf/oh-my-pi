WITH house AS (
    SELECT
        h.id AS id_house,
        h.id_region,
        cs_supply.sk_company
    FROM
        datalake_ebdb_listing.house AS h
    LEFT JOIN
        datalake_rede_company.company_sks AS cs_supply
            ON (
                h.uuid_company IS NOT NULL
                AND h.uuid_company = cs_supply.uuid_company
            ) OR (
                h.uuid_company IS NULL
                AND h.id_company_hubspot IS NOT NULL
                AND h.id_company_hubspot = cs_supply.id_hubspot
            ) OR (
                h.uuid_company IS NULL
                AND h.id_company_hubspot IS NULL
                AND h.partner_3p_supply = cs_supply.extracted_3p_tag
            )
)
SELECT
    dhav.sk_house_amenities_version * 10000 + dhi.sk_information AS sk_house_information_change,
    dhav.sk_house_amenities_version,
    ah.id_house AS sk_house,
    dhi.sk_information,
    COALESCE(ah.id_user, -1) AS sk_user_revisor,
    COALESCE(h.id_region, -1) AS sk_region,
    COALESCE(h.sk_company, -1) AS sk_company,
    COALESCE(BIGINT(DATE_FORMAT(ah.ts_change, 'yyyyMMdd')), -1) AS sk_revision_date,
    COALESCE(BIGINT(DATE_FORMAT(ah.ts_next_change, 'yyyyMMdd')), -1) AS sk_next_revision_date,
    ah.is_atlas_update,
    ah.ts_change AS ts_revision,
    ah.ts_next_change AS ts_next_revision,
    NOW() AS ts_load
FROM
    datalake_ebdb_amenities.amenity_change_history AS ah
LEFT JOIN
    dw_house.dim_house_information AS dhi
        ON ah.id_amenity = dhi.id_amenity
        AND ah.is_condo_amenity = (dhi.information_type = 'CONDO_AMENITY')
        AND COALESCE(UPPER(ah.has_feature::STRING), 'Unknown') = dhi.value
LEFT JOIN
    dw_house.dim_house_amenities_version AS dhav
        ON ah.id_house = dhav.id_house
        AND ah.ts_change = dhav.ts_version_started
LEFT JOIN
    house AS h
        ON ah.id_house = h.id_house
