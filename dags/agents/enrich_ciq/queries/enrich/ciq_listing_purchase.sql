WITH ciq_costs AS (
    SELECT
        cc.city,
        cc.total_costs_ciq_full_for_rent,
        ROW_NUMBER() OVER(PARTITION BY cc.city ORDER BY cc.year DESC, cc.month DESC) = 1 AS is_last_updated,
        cc.year,
        cc.month
    FROM
        datalake_gsheets_clean.ciq_costs AS cc
    WHERE
        cc.city IS NOT NULL
),
signed_contracts AS(
    SELECT
        hl.id_house,
        hl.id_contract,
        hl.id_house_listing,
        c.id_owner,
        c.status,
        COALESCE(hl.status = 'OPTED_OUT' OR (hl.status = 'UNPUBLISHED' AND hl.status_reason != 'RENTED'), FALSE) AS is_house_inactive,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end,
        hl.ts_contract_signed,
        hl.ts_next_contract_signed,
        LAG(hl.ts_contract_signed, 1) OVER (PARTITION BY hl.id_house ORDER BY hl.version) AS ts_previous_contract_signed,
        c.dt_termination
    FROM
        datalake_ebdb_listing.house_listing AS hl
    JOIN
        core_contract.contract AS c
            ON hl.id_house = c.id_house
            AND hl.id_contract = c.id_contract
),
house_consultant_history AS (
    SELECT
        hch.id_house,
        hch.id_enrollment,
        hch.id_partner,
        hch.id_internal_agent,
        hch.id_user,
        MIN(ts_agency_created) AS ts_house_registration
    FROM
        datalake_big_agent.house_consultant_history AS hch
    WHERE
        hch.consultant_type = 'CIQ_FULL'
    GROUP BY ALL
)
SELECT
    hch.id_house,
    hch.id_partner,
    c.id_house_listing,
    c.id_contract,
    c.id_owner,
    hch.id_user AS id_ciq_user,
    hch.id_internal_agent,
    hch.id_enrollment,
    ae.id AS id_accounting_entry,
    ld.id_address_parsed_short AS id_address_parsed_duplicity,
    ahd.id_duplicity AS id_atlas_duplicity,
    ld.address_full AS address,
    ld.first_listing_order AS parsed_first_listing_order,
    c.status AS contract_status,
    CASE
        WHEN c.status = 'Cancelado'	THEN 'cancelled'
        WHEN ae.id IS NOT NULL THEN 'paid'
        WHEN c.ts_contract_signed IS NULL THEN 'not_eligible'
        ELSE 'pending'
    END AS payment_status,
    CASE
        WHEN vfl.hybrid_creation_order = 'SALE > RENT' THEN 'hybrid'
        WHEN vfl.ts_first_listing_rent >= DATE("2026-07-01") THEN 'new-listings'
        WHEN vfl.ts_first_listing_rent < DATE("2026-07-01")
            AND c.ts_previous_contract_signed IS NOT NULL
            THEN 'ongoing-rentals'
        WHEN vfl.ts_first_listing_rent < DATE("2026-07-01")
            AND c.id_contract IS NULL
            THEN 'ongoing-listings'
    END AS pricing_type,
    cc.total_costs_ciq_full_for_rent AS purchase_value,
    ae.due_amount AS amount_paid,
    IF(
            c.is_house_inactive IS TRUE, 
            TIMESTAMPDIFF(DAY, c.ts_listing_version_start, COALESCE(c.ts_listing_version_end, DATE(NOW()))), 
            0
    ) AS total_days_since_house_inactived,
    ld.is_duplicated AS has_similiar_house_by_address_parsed,
    ahd.id_duplicity IS NOT NULL AS has_similiar_house_by_atlas,
    c.is_house_inactive,
    c.ts_contract_signed IS NOT NULL AS is_eligible,
    ae.dt_occurrence IS NOT NULL AS is_paid,
    ae.dt_occurrence AS dt_paid,
    c.dt_termination AS dt_contract_termination,
    c.ts_contract_signed,
    c.ts_next_contract_signed,
    c.ts_previous_contract_signed,
    IF(c.is_house_inactive IS TRUE, c.ts_listing_version_start, NULL) AS ts_house_inactived,
    hch.ts_house_registration,
    vfl.ts_first_listing_rent AS ts_first_listing,
    NOW() AS ts_load,
    YEAR(hch.ts_house_registration) AS year,
    MONTH(hch.ts_house_registration) AS month,
    DAY(hch.ts_house_registration) AS day
FROM
    core_house.house AS h
JOIN
    datalake_ebdb_clean.listing_business_context AS lbc
        ON lbc.id_house = h.id_house
        AND lbc.business_context = "RENT"
JOIN
    house_consultant_history AS hch
        ON hch.id_house = h.id_house
JOIN
    datalake_listing_deduplication.listing_deduplication AS ld
        ON ld.id_house = h.id_house
LEFT JOIN
    datalake_listing_deduplication.atlas_house_deduplication AS ahd
        ON ahd.id_house = h.id_house
LEFT JOIN
    datalake_listing_deduplication.valid_first_listing AS vfl
        ON vfl.id_house = h.id_house
LEFT JOIN
    signed_contracts AS c
        ON c.id_house = h.id_house
LEFT JOIN
    ciq_costs AS cc
        ON TRIM(LOWER(cc.city)) = TRIM(LOWER(h.city))
        AND CAST(cc.year AS INT) = YEAR(c.ts_contract_signed)
        AND CAST(cc.month AS INT) = MONTH(c.ts_contract_signed)
        AND cc.is_last_updated IS TRUE
LEFT JOIN
    datalake_robin_hood.accounting_entry AS ae
        ON TRY_CAST(ae.id_house AS BIGINT) = h.id_house
        AND TRY_CAST(ae.id_contract AS BIGINT) = c.id_contract
        AND LOWER(TRIM(ae.source_code)) = 'ciq-listing-purchase'
        AND ae.ts_blocked IS NULL