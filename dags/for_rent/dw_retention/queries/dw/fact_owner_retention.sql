WITH 
house_listing_contracts AS (
    WITH 
    latest_contract AS (
        SELECT
            id_house_listing,
            MAX(id_contract) AS id_contract,
            MAX(id_previous_contract) AS id_previous_contract,
            DENSE_RANK() OVER (PARTITION BY id_house ORDER BY id_house_listing) AS order_renting
        FROM
            datalake_listing_contracts.listing_contracts
        WHERE
            contract_status IN ('Ativo', 'Finalizado')
        GROUP BY 
            id_house_listing, id_house
    )
    SELECT
        hl.id_house_listing,
        c.id AS id_contract,
        hl.id_house,
        lc.id_previous_contract,
        hl.version AS house_version,
        lc.order_renting,
        COUNT(c.id) OVER (PARTITION BY c.id_house) AS nr_renting,
        c.ts_signed AS ts_contract_signed,
        c.dt_termination AS dt_contract_annulment,
        LEAD(c.ts_signed, 1) OVER (PARTITION BY hl.id_house ORDER BY hl.version) AS ts_next_contract_signed
    FROM
        datalake_ebdb_listing.house_listing AS hl
    LEFT JOIN
        latest_contract AS lc
            ON hl.id_house_listing = lc.id_house_listing
    LEFT JOIN
        datalake_ebdb_contract.contract AS c
            ON c.id = lc.id_contract
)
SELECT 
    hl.id_house_listing AS sk_house_listing,
    hl.id_house AS sk_house,
    h.id_user AS sk_owner,
    dc.id AS sk_contract,
    NOW() AS ts_load
FROM
    datalake_ebdb_listing.house_listing AS hl
JOIN
    datalake_ebdb_listing.house AS h
        ON h.id = hl.id_house
LEFT JOIN 
    house_listing_contracts AS hlc
        ON hlc.id_house_listing = hl.id_house_listing
LEFT JOIN
    datalake_ebdb_contract.contract AS dc
        ON dc.id = hlc.id_contract