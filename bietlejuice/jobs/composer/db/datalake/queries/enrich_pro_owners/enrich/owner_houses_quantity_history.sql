WITH house_portability AS (
    SELECT
        hl.id_house_listing
    FROM 
        datalake_ebdb_listing.house_listing hl
    JOIN 
        datalake_ebdb_clean.house h
            ON h.id = hl.id_house
    JOIN 
        datalake_ebdb_clean.portability por
            ON por.id_house = hl.id_house 
            AND por.owner_type = 'B2B'
    WHERE por.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, NOW())
),
lbc AS (
    SELECT
        id_house,
        CAST(MAX(CAST((business_context = 'RENT') AS INTEGER)) AS BOOLEAN) AS is_for_rent,
        CAST(MAX(CAST((business_context = 'SALE') AS INTEGER)) AS BOOLEAN) AS is_for_sale
    FROM 
        datalake_ebdb_listing.listing_business_context
    GROUP BY 1
),
house_listing_owners_status AS (
    SELECT
        hls.id_house,
        h.id_user AS id_owner,
        hls.status_history,
        IF((l.affiliate_type = 'B2BPartner') OR (partner_agent.id IS NOT NULL AND partner.type = 'PRIME') OR (hp.id_house_listing IS NOT NULL), TRUE, FALSE) AS is_b2b,
        IF(lbc.is_for_rent OR lbc.id_house IS NULL, TRUE, FALSE) AS is_for_rent,
        hls.ts_status_ended,
        hls.ts_status_started
    FROM 
        datalake_ebdb_clean.house h
    JOIN
        datalake_ebdb_listing.house_listing_status AS hls
            ON hls.id_house = h.id
    LEFT JOIN 
        datalake_ebdb_clean.conversion_lead cl
            ON cl.id_house = h.id
    LEFT JOIN 
        datalake_ebdb_clean.lead l
            ON l.id = cl.id_converted_lead
    LEFT JOIN
        datalake_ebdb_clean.partner_agent partner_agent
            ON partner_agent.id_user = h.id_user
    LEFT JOIN
        datalake_ebdb_clean.partner partner
            ON partner.id = partner_agent.id_partner
    LEFT JOIN
        house_portability AS hp
            ON hp.id_house_listing = hls.id_house_listing
    LEFT JOIN 
        lbc AS lbc
            ON lbc.id_house = h.id
),
status_changes AS (
  SELECT
        id_owner,
        ts_status_started
    FROM
        house_listing_owners_status
    WHERE
        -- is_for_rent = True
        -- AND is_b2b = False
        id_owner > 0 
    GROUP BY 1, 2
),
houses_changes_filter AS (
    SELECT
        sc.id_owner,
        sc.ts_status_started,
        CASE
          WHEN hlos.status_history IN ('alugado', 'publicado', 'suspenso') 
              AND hlos.is_for_rent = True
              AND is_b2b = False
              AND hlos.id_owner > 0 THEN hlos.id_house
          ELSE NULL
        END AS id_house
    FROM
        status_changes AS sc
    JOIN
        house_listing_owners_status AS hlos
            ON hlos.id_owner = sc.id_owner
            AND hlos.ts_status_started <= sc.ts_status_started 
            AND (hlos.ts_status_ended > sc.ts_status_started OR hlos.ts_status_ended IS NULL)
),
qtd_houses_changes AS (
  SELECT 
    id_owner,
    ts_status_started,
    COUNT(DISTINCT id_house) AS houses
  FROM
    houses_changes_filter
  GROUP BY 1, 2
),
/*Same qtd could appear in sequence. If one house has status changing between
alugado, publicado, suspenso the qtd won't change, so we will just store
a date that doesn't have meaning
*/
qtd_houses_changes_trimmed AS (
    SELECT
        id_owner,
        LAG(houses) OVER (PARTITION BY id_owner ORDER BY ts_status_started) AS previous_houses,
        houses,
        ts_status_started
    FROM
        qtd_houses_changes
)
SELECT
    id_owner,
    houses,
    previous_houses,
    ts_status_started AS ts_house_number_started,
    LEAD(ts_status_started) OVER (PARTITION BY id_owner ORDER BY ts_status_started) AS ts_house_number_ended
FROM
    qtd_houses_changes_trimmed
WHERE
    houses != COALESCE(previous_houses, -1)
    AND ts_status_started <= DATE_ADD(DATE('{year}-{month}-{day}'),1) -- To avoid a retroactive change we only retrieve D-1 data.