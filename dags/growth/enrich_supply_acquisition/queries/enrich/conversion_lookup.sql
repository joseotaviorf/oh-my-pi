-- All houses in the datalake with their business context and supply source
WITH bob_houses AS (
  SELECT 
    sp.id_external AS id_house,
    hd.business_context,
    'BOB' AS source,
    '1P' AS supply_source
  FROM
    datalake_bob.house_draft_business_context AS hd
  JOIN
    datalake_bob_clean.submission_progress AS sp 
      ON (hd.id_draft = sp.id_house_draft) 
        AND (sp.id_external IS NOT NULL)
  WHERE 
    DATE(ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
lbc_houses AS (
  SELECT 
    aud.id_house, 
    aud.business_context, 
    'LBC' AS source, 
    CASE 
      WHEN lbc.ownership = 'THIRD_PARTY' THEN '3P'
      ELSE '1P'
    END AS supply_source
  FROM
    datalake_ebdb_clean.listing_business_context_aud AS aud
  JOIN
    datalake_ebdb_clean.listing_business_context AS lbc
      ON (aud.business_context = lbc.business_context)
        AND (aud.id_house = lbc.id_house)
  WHERE
    aud.status IN ('EDITING', 'PUBLISHED')
      AND lbc.ts_created BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY aud.id_house, aud.business_context ORDER BY aud.rev) = 1
),
joined_tb AS (
  SELECT *
  FROM bob_houses
  UNION ALL
  SELECT *
  FROM lbc_houses
),
houses_with_context AS (
  SELECT 
    id_house, 
    business_context, 
    supply_source,
    MAX(source = 'LBC') AS has_listing, 
    MAX(source = 'BOB') AS has_draft
  FROM 
    joined_tb
  GROUP BY 1, 2, 3
),
lead_conversion_1p AS (
-- Rene Descartes is the newest source of this information
    SELECT 
        hlc.id, 
        hlc.id_lead, 
        hlc.id_house, 
        EXPLODE(
            CASE 
                WHEN hw.business_context IS NULL
                    THEN ARRAY('RENT', 'SALE')
                ELSE ARRAY(hw.business_context)
            END
        ) AS business_context,
        COALESCE(hw.has_listing, FALSE) AS has_listing,
        COALESCE(hw.has_draft, FALSE) AS has_draft,
        hlc.ts_created AS ts_conversion, 
        1 AS db_source, 
        COALESCE(hw.supply_source, '1P') AS supply_source
    FROM 
      datalake_rene_descartes_clean.house_lead_conversion AS hlc
    LEFT JOIN 
      houses_with_context AS hw
        ON (hlc.id_house = hw.id_house)
    WHERE 
      DATE(hlc.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    -- EBDB is a source of historic information
    SELECT 
        cl.id, 
        cl.id_converted_lead AS id_lead, 
        cl.id_house, 
        EXPLODE(
            CASE 
                WHEN hw.business_context IS NULL
                    THEN ARRAY('RENT', 'SALE')
                ELSE ARRAY(hw.business_context)
            END
        ) AS business_context,
        COALESCE(hw.has_listing, FALSE) AS has_listing,
        COALESCE(hw.has_draft, FALSE) AS has_draft,
        from_utc_timestamp(cl.ts_conversion, 'GMT+3') AS ts_conversion, 
        2 AS db_source, 
        COALESCE(hw.supply_source, '1P') AS supply_source
    FROM 
      datalake_ebdb_clean.conversion_lead AS cl
    LEFT JOIN 
      houses_with_context AS hw
        ON (cl.id_house = hw.id_house)
    WHERE 
      id_converted_lead IS NOT NULL
        AND DATE(cl.ts_conversion) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
lead_conversion_3p AS (
    SELECT 
        lbca.id_listing_business_context AS id,
        l.id AS id_lead,
        lbca.id_house,
        lbca.business_context,
        (lbca.business_context IS NOT NULL) AS has_listing,
        (lbca.business_context IS NOT NULL) AS has_draft,
        l.ts_created AS ts_conversion,
        4 AS db_source,
        '3P' AS supply_source
    FROM
        datalake_brokers_supply_processor.lead_3p AS l
    JOIN datalake_ebdb_clean.house AS h
        ON h.id_external = l.uuid_lead
    JOIN datalake_ebdb_clean.listing_business_context_aud AS lbca
        ON lbca.id_house = h.id
    WHERE 
      DATE(l.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY l.id, lbca.id_house, lbca.business_context ORDER BY l.ts_created) = 1
),
lead_conversion_ciq AS (
    SELECT 
        hd.id_draft AS id, 
        hd.id_draft AS id_lead,  
        s.id_external AS id_house, 
        hd.business_context,
        (s.id_external IS NOT NULL) AS has_listing,
        (hd.id_draft IS NOT NULL) AS has_draft,
        hd.ts_created AS ts_conversion, 
        3 AS db_source,  
        'CIQ' AS supply_source
    FROM 
      datalake_bob.house_draft_business_context AS hd
    JOIN 
      datalake_bob_clean.submission_progress AS s 
        ON (hd.id_draft = s.id_house_draft) 
          AND (s.id_external IS NOT NULL)
    WHERE 
      (hd.type = 'ADMIN_CONFIRMATION')
        AND DATE(hd.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),

all_conversions AS (
  SELECT *
  FROM lead_conversion_ciq
  UNION ALL
  SELECT *
  FROM lead_conversion_3p
  UNION ALL
  SELECT *
  FROM lead_conversion_1p
)

SELECT 
  *
FROM all_conversions
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_house, business_context ORDER BY db_source, ts_conversion) = 1
