WITH listing_business_context AS (
    SELECT
        id_house,
        CAST(MAX(CAST((business_context = 'SALE') AS INTEGER)) AS BOOLEAN) AS is_for_sale,
        CAST(MAX(CAST((business_context = 'RENT') AS INTEGER)) AS BOOLEAN) AS is_for_rent,
        MAX(IF(business_context = 'SALE', status, NULL)) AS house_sale_status,
        MAX(IF(business_context = 'SALE', status_reason, NULL)) AS house_sale_status_reason,
        MAX(IF(business_context = 'RENT', status, NULL)) AS house_rent_status,
        MAX(IF(business_context = 'RENT', status_reason, NULL)) AS house_rent_status_reason
    FROM
        datalake_ebdb_listing.listing_business_context
    GROUP BY 1
),
house_listing AS (
    SELECT
        hl.id_house,
        hl.id_house_listing AS sk_house_listing,
        hlco.first_consultant_type,
        CAST(hl.version AS SMALLINT) AS version,
        IF(hl.version > 0, hl.ts_listing_version_start, NULL) AS ts_listing_version_start,
        hl.ts_listing_version_end,
        CAST(COALESCE(hlco.id_user, -1) AS BIGINT) AS sk_user_consultant,
        CASE
            WHEN lbc.id_house IS NULL THEN TRUE -- When house is not in listing_business_context, it is for rent
            ELSE COALESCE(lbc.is_for_rent, FALSE)
        END AS is_for_rent,
        h.country_code
    FROM
        datalake_ebdb_listing.house AS h
    JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON hl.id_house = h.id
    LEFT JOIN
        listing_business_context AS lbc
            ON lbc.id_house = h.id
    LEFT JOIN
        datalake_big_agent.house_rent_listing_consultant AS hlco
            ON hlco.id_house_listing = hl.id_house_listing
            AND hlco.is_last_ciq_on_listing IS TRUE
),
first_listing AS (
    SELECT
        hl.sk_user_consultant,
        COUNT(DISTINCT COALESCE(plb2b.id_house_listing, -1)) AS first_listings,
        DATE(DATE_TRUNC('month' , dd.date)) AS dt_month_start
    FROM
        datalake_listing_flow.listing_flows_with_reprocessed_leads AS lfrl
    LEFT JOIN
        datalake_rent_potential_listing.potential_listing_b2b AS plb2b
            ON plb2b.id = lfrl.id
    JOIN
        house_listing AS hl
            ON COALESCE(plb2b.id_house_listing, -1) = hl.sk_house_listing
    JOIN
        datalake_quintoandar.aux_date AS dd
            ON dd.date = DATE(lfrl.ts_first_listing)
    WHERE
        hl.country_code = 'MX'
        AND lfrl.ts_first_listing IS NOT NULL
        AND hl.first_consultant_type <> 'Core'
    GROUP BY
        1, 3
),
contract_signed AS (
    SELECT
        hl.sk_user_consultant,
        COUNT(DISTINCT lc.id_contract) AS contracts_signed,
        DATE(DATE_TRUNC('month' , dd.date)) AS dt_month_start
    FROM
        datalake_listing_contracts.listing_contracts AS lc
    JOIN
        datalake_ebdb_contract.contract AS c
            ON lc.id_contract = c.id
            AND c.status IN ('Ativo', 'Finalizado')
    JOIN
        house_listing AS hl
            ON lc.id_house_listing = hl.sk_house_listing
    JOIN
        datalake_quintoandar.aux_date AS dd
            ON dd.date = DATE(c.ts_signed)
            AND c.ts_signed IS NOT NULL
    WHERE
        lc.country_code = 'MX'
        AND hl.first_consultant_type <> 'Core'
    GROUP BY
        1, 3
),
cibs_information AS (
    SELECT
        GET_JSON_OBJECT(a.details, '$.userExternalId') AS id_cib,
        NULLIF(CAST(LEFT(u.name, 200) AS VARCHAR(255)), '') AS cib_name,
        NULLIF(u.email, '') AS cib_email,
        DATE(GET_JSON_OBJECT(a.details, '$.registeredAt')) AS dt_registered,
        dd.month_start AS dt_month_start
    FROM
        datalake_quintoandar.aux_date AS dd
    LEFT JOIN
        datalake_big_agent.agent AS a
            ON dd.month_start >= DATE_TRUNC('month' , DATE(GET_JSON_OBJECT(a.details, '$.registeredAt')))
            AND dd.month_start < DATE_TRUNC('month', NOW())
    LEFT JOIN
        datalake_ebdb_user.user AS u
            ON u.id = GET_JSON_OBJECT(a.details, '$.userExternalId')
    WHERE
        u.country_code = 'MX'
    GROUP BY
        1, 2, 3, 4, 5
),
cibs_info_for_segmentation AS (
    SELECT
        ci.id_cib,
        ci.cib_name,
        ci.cib_email,
        COALESCE(fl.first_listings, 0) AS first_listings,
        COALESCE(cs.contracts_signed, 0) AS contracts_signed,
        ROUND(MONTHS_BETWEEN(DATE(NOW()), ci.dt_registered), 1) AS months_registered,
        ci.dt_registered,
        ci.dt_month_start
    FROM
        cibs_information AS ci
    LEFT JOIN
        first_listing AS fl
            ON fl.sk_user_consultant = ci.id_cib
            AND ci.dt_month_start = fl.dt_month_start
    LEFT JOIN
        contract_signed AS cs
            ON cs.sk_user_consultant = ci.id_cib
            AND ci.dt_month_start = cs.dt_month_start
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8
)
SELECT
    id_cib,
    cib_name,
    cib_email,
    CASE
        WHEN months_registered >= 3 AND contracts_signed >= 2 AND first_listings >= 8 THEN 'MASTER'
        WHEN months_registered >= 1 AND contracts_signed >= 1 AND first_listings >= 2 THEN 'LOYAL'
        ELSE 'INTER'
    END AS level,
    first_listings,
    contracts_signed,
    months_registered,
    dt_registered,
    YEAR(dt_month_start) AS year,
    MONTH(dt_month_start) AS month
FROM
    cibs_info_for_segmentation
