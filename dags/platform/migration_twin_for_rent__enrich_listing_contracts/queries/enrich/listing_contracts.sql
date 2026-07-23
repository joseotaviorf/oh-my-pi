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
        COALESCE(LAG(c.id) OVER(PARTITION BY lc.id_house ORDER BY lc.id_house_listing, c.ts_created, t.ts_created), NULL) AS id_previous_contract,
        lc.id_house,
        hl.country_code,
        c.status AS contract_status,
        LAG(c.status) OVER(PARTITION BY lc.id_house ORDER BY lc.id_house_listing) AS previous_contract_status,
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
),
house_listing_contracts AS (
    WITH latest_contract AS (
        SELECT
            id_house_listing,
            MAX(id_contract) AS id_contract,
            MAX(id_previous_contract) AS id_previous_contract,
            DENSE_RANK() OVER (PARTITION BY id_house ORDER BY id_house_listing) AS order_renting
        FROM
          contracts_base
        WHERE
          contract_status IN ('Ativo', 'Finalizado')
        GROUP BY id_house_listing, id_house
    )
    SELECT
        hl.id_house_listing,
        c.id AS id_contract,
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
    cb.id_house_listing,
    cb.id_contract,
    cb.id_house,
    cb.id_previous_contract,
    cb.country_code,
    cb.listing_status,
    cb.contract_status,
    cb.previous_contract_status,
    cb.termination_status,
    CAST((CAST(hl.ts_listing_version_end AS LONG) - CAST(CAST(hlc.dt_contract_annulment AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_ended_rental_to_relisting,
    CAST((CAST(hlc.ts_next_contract_signed AS LONG) - CAST(hl.ts_listing_version_end AS LONG))/(86400) AS INTEGER) AS days_relisting_to_re_rental,
    CAST((CAST(hlc.ts_next_contract_signed AS LONG) - CAST(CAST(hlc.dt_contract_annulment AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_ended_rental_to_re_rented,
    cb.is_early_relisting,
    cb.is_early_demand,
    cb.is_extended_rental,
    COALESCE(LAG(cb.is_on_termination) OVER(PARTITION BY cb.id_house ORDER BY cb.id_house_listing, cb.ts_contract_created, cb.ts_termination_created), NULL) AS is_previous_contract_on_termination,
    cb.ts_listing_version_started,
    cb.ts_listing_version_ended,
    cb.ts_early_demand_started,
    cb.ts_contract_created,
    cb.ts_termination_created,
    cb.dt_termination,
    IF(cb.previous_contract_status IN ('Ativo', 'Finalizado'),
      LAG(cb.ts_termination_created) OVER(PARTITION BY cb.id_house ORDER BY cb.id_house_listing, cb.ts_contract_created, cb.ts_termination_created),
      NULL
    ) AS dt_previous_contract_termination,
    IF(cb.previous_contract_status IN ('Ativo', 'Finalizado'),
      LAG(cb.dt_termination) OVER(PARTITION BY cb.id_house ORDER BY cb.id_house_listing, cb.ts_contract_created, cb.ts_termination_created),
      NULL
    ) AS dt_previous_termination
FROM
    contracts_base AS cb
JOIN
    datalake_ebdb_listing.house_listing hl
        ON hl.id_house_listing = cb.id_house_listing
LEFT JOIN
    house_listing_contracts hlc
        ON hl.id_house_listing = hlc.id_house_listing
