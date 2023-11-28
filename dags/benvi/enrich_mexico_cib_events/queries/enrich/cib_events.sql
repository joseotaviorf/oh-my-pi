WITH first_listing_event AS (
    SELECT
        hrlc.id_user AS id_cib,
        COALESCE(plb2b.id_house_listing, -1) AS id_event,
        hrlc.id_house,
        COALESCE(plb2b.id_house_listing, -1) AS id_house_listing,
        -1 AS id_contract,
        'FL' AS event_type,
        DATE(lfrl.ts_first_listing) AS dt_event,
        YEAR(DATE(lfrl.ts_first_listing)) AS year,
        MONTH(DATE(lfrl.ts_first_listing)) AS month,
        DAY(DATE(lfrl.ts_first_listing)) AS day
    FROM
        datalake_listing_flow.listing_flows_with_reprocessed_leads AS lfrl
    LEFT JOIN
        datalake_rent_potential_listing.potential_listing_b2b AS plb2b
            ON plb2b.id = lfrl.id
    JOIN
        datalake_big_agent.house_rent_listing_consultant AS hrlc
            ON COALESCE(plb2b.id_house_listing, -1) = hrlc.id_house_listing
    WHERE
        lfrl.country_code = 'MX'
        AND lfrl.ts_first_listing IS NOT NULL
        AND hrlc.consultant_type <> 'Core'
        AND hrlc.id_user <> -1
        AND YEAR(DATE(lfrl.ts_first_listing)) = {year}
        AND MONTH(DATE(lfrl.ts_first_listing)) = {month}
        AND DAY(DATE(lfrl.ts_first_listing)) = {day}
),
contract_signed_event AS (
    SELECT DISTINCT
        hrlc.id_user AS id_cib,
        rde.id_contract AS id_event,
        hrlc.id_house,
        rde.id_house_listing,
        rde.id_contract,
        'CS' AS event_type,
        DATE(ts_event) AS dt_event,
        YEAR(DATE(ts_event)) AS year,
        MONTH(DATE(ts_event)) AS month,
        DAY(DATE(ts_event)) AS day
    FROM
        datalake_rent_demand_events.rent_demand_events AS rde
    JOIN
        datalake_big_agent.house_rent_listing_consultant AS hrlc
            ON rde.id_house_listing = hrlc.id_house_listing
    WHERE
        rde.country_code = 'MX'
        AND rde.id_event_type = 9
        AND hrlc.consultant_type <> 'Core'
        AND hrlc.id_user <> -1
        AND YEAR(DATE(ts_event)) = {year}
        AND MONTH(DATE(ts_event)) = {month}
        AND DAY(DATE(ts_event)) = {day}
)
SELECT * FROM first_listing_event
UNION ALL
SELECT * FROM  contract_signed_event
