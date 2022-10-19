SELECT DISTINCT
    CAST(COALESCE(dc.id_user, '-1') AS BIGINT) AS id_client,
    CAST(COALESCE(dc.id, '-1') AS BIGINT) AS id_contract,
    CAST(COALESCE(house.id_user, '-1') AS BIGINT) AS id_owner,
    CAST(COALESCE(dhl.id_house_listing, '-1') AS BIGINT) AS id_house_listing,
    dhl.id_house,
    COALESCE(CAST(dhl.version AS SMALLINT), 1) AS version,
    dhl.ts_listing_version_start AS dt_listing_version_start,
    dhl.ts_listing_version_end AS dt_listing_version_end
FROM
    datalake_ebdb_listing.house_listing dhl
LEFT JOIN
    datalake_ebdb_clean.contract dc
        ON dc.id_house = dhl.id_house
        AND dc.house_number = CAST(SUBSTRING(dhl.id_house_listing, -3) AS INT)
LEFT JOIN
    datalake_ebdb_clean.rent_flow fl
        ON fl.id_current_proposal = dc.id_proposal
LEFT JOIN
    datalake_ebdb_listing.house house
        ON house.id = fl.id_house
