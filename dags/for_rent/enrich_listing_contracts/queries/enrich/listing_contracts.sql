WITH listing_contracts AS (
    SELECT
        -- Relating each listing to its respective contract
        hl.id_house,
        hl.id_house_listing,
        c.id AS id_contract
    FROM
        datalake_ebdb_listing.house_listing AS hl
    JOIN
        datalake_ebdb_contract.contract AS c
            ON hl.id_house = c.id_house
            AND c.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '2000-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, CURRENT_DATE)
),
terminations AS (
    SELECT
        id_contract,
        status,
        ts_created
    FROM
        datalake_terminator_clean.termination
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY ts_created DESC) = 1
),
contracts_base AS (
    SELECT
        lc.id_house_listing,
        c.id AS id_contract,
        lc.id_house,
        hl.country_code,
        c.status AS contract_status,
        t.status AS termination_status,
        hl.status AS listing_status,
        hl.is_early_relisting,
        hl.is_early_demand,
        hl.is_extended_rental,
        IF(c.status <> 'Finalizado' AND t.status IS NOT NULL AND t.status NOT IN ('CANCELED', 'DONE'), TRUE, FALSE) AS is_on_termination,
        hl.ts_listing_version_start AS ts_listing_version_started,
        hl.ts_listing_version_end AS ts_listing_version_ended,
        hl.ts_early_demand_started,
        c.ts_created AS ts_contract_created,
        t.ts_created AS ts_termination_created,
        c.dt_termination
    FROM
        datalake_ebdb_contract.contract AS c
    JOIN
        listing_contracts AS lc
            ON lc.id_contract = c.id
    JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON lc.id_house_listing = hl.id_house_listing
    LEFT JOIN
        terminations AS t
            ON t.id_contract = c.id
)
SELECT
    id_house_listing,
    id_contract,
    id_house,
    COALESCE(LAG(id_contract) OVER(PARTITION BY id_house ORDER BY id_house_listing, ts_contract_created, ts_termination_created), NULL) AS id_previous_contract,
    country_code,
    listing_status,
    contract_status,
    termination_status,
    is_early_relisting,
    is_early_demand,
    is_extended_rental,
    COALESCE(LAG(is_on_termination) OVER(PARTITION BY id_house ORDER BY id_house_listing, ts_contract_created, ts_termination_created), NULL) AS is_previous_contract_on_termination,
    ts_listing_version_started,
    ts_listing_version_ended,
    ts_early_demand_started,
    ts_contract_created,
    ts_termination_created,
    dt_termination,
    LAG(dt_termination) OVER(PARTITION BY id_house ORDER BY id_house_listing, ts_contract_created, ts_termination_created) AS dt_previous_contract_termination
FROM
    contracts_base
