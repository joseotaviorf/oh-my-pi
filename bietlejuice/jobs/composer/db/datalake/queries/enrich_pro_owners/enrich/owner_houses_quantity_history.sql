WITH event_bus AS (
    SELECT
        id_house,
        ts_status_started AS ts_event
    FROM
        datalake_ebdb_listing.house_listing_status
    UNION
    SELECT
        id_house,
        ts_started AS ts_event
    FROM
        datalake_pro_owners.house_b2b_history
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
        IF((hbh.affiliate_type = 'B2BPartner') OR (hbh.id_partner IS NOT NULL AND partner.type = 'PRIME') OR (hbh.id_house_listing IS NOT NULL), TRUE, FALSE) AS is_b2b,
        IF(lbc.is_for_rent OR lbc.id_house IS NULL, TRUE, FALSE) AS is_for_rent,
        hls.ts_status_ended,
        hls.ts_status_started
     FROM
        event_bus AS eb
    JOIN
        datalake_ebdb_clean.house h
            ON eb.id_house = h.id
    JOIN
        datalake_ebdb_listing.house_listing_status AS hls
            ON eb.id_house = hls.id_house
            AND eb.ts_event >= hls.ts_status_started
            AND eb.ts_event < COALESCE(hls.ts_status_ended, '2100-12-31')
    LEFT JOIN 
        datalake_pro_owners.house_b2b_history AS hbh
            ON eb.id_house = hbh.id_house
            AND eb.ts_event >= hbh.ts_started
            AND eb.ts_event < COALESCE(hbh.ts_ended, '2100-12-31')
    LEFT JOIN
        datalake_ebdb_clean.partner partner
            ON partner.id = hbh.id_partner
    LEFT JOIN 
        lbc AS lbc
            ON lbc.id_house = h.id
    WHERE
        eb.ts_event IS NOT NULL
),
status_changes AS (
  SELECT
        id_owner,
        ts_status_started AS ts_event
  FROM
      house_listing_owners_status
  WHERE
      id_owner > 0 
  UNION
  SELECT
      id_owner,
      ts_status_ended AS ts_event
  FROM
      house_listing_owners_status
  WHERE
      id_owner > 0
),
houses_changes_filter AS (
    SELECT
        sc.id_owner,
        sc.ts_event AS ts_status_started,
        CASE
          WHEN hlos.status_history IN ('alugado', 'publicado', 'suspenso') 
              AND hlos.is_for_rent = True
              AND is_b2b = False
              AND hlos.id_owner > 0 THEN hlos.id_house
          ELSE NULL
        END AS id_house
    FROM
        status_changes AS sc
    LEFT JOIN
        house_listing_owners_status AS hlos
            ON hlos.id_owner = sc.id_owner
            AND hlos.ts_status_started <= sc.ts_event
            AND (hlos.ts_status_ended > sc.ts_event OR hlos.ts_status_ended IS NULL)
    WHERE
        sc.ts_event IS NOT NULL
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