WITH rent_strategic_regions AS (
  SELECT DISTINCT
      concat_city_neighborhood,
      is_strategic_region,
      DATE(date_trunc('MONTH', DATEADD(MONTH,1,ts_load))) AS year_month_reference
  FROM
      datalake_gsheets_clean.rent_comission_for_strategic_region
  QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_region, MONTH(ts_load), YEAR(ts_load) ORDER BY ts_load DESC) = 1  
),
listings AS (
  SELECT
      hl.id_house_listing,
      h.region_city_name,
      h.neighborhood,
      h.id_region,
      REGEXP_REPLACE(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    REGEXP_REPLACE(
                                        REGEXP_REPLACE(
                                            LOWER( h.region_city_name || h.neighborhood),
                                            '[àáâäãå]', 'a'),
                                            '[èéêë]', 'e'),
                                            '[ìíîï]', 'i'),
                                            '[òóôöõ]', 'o'),
                                            '[ùúûü]', 'u'),
                                            'ç', 'c'),
                                            'ñ', 'n'),
                                            ' ', ''), 
                                            '''', ''),
                                            '-','') AS concat_city_neighborhood,
      CASE
          WHEN hl.version = 1 THEN hl.ts_first_publication
          WHEN hl.version > 0 THEN hl.ts_listing_version_start
          ELSE NULL
      END AS ts_publication,
      CASE 
        WHEN DATE(ts_publication) < DATE("2023-10-01") THEN DATE("2023-09-01")
        ELSE DATE(DATE_TRUNC('MONTH', ts_publication))
      END AS year_month_publication_reference
  FROM
      datalake_ebdb_listing.house AS h
  JOIN 
      datalake_ebdb_listing.house_listing AS hl 
          ON hl.id_house = h.id
)
SELECT 
    l.id_house_listing,
    l.id_region,
    l.region_city_name AS city_name,
    l.neighborhood AS neighborhood_name,
    COALESCE(sr.is_strategic_region, FALSE) AS is_strategic_region,
    l.year_month_publication_reference AS dt_publication_reference,
    l.ts_publication
FROM 
    listings AS l 
LEFT JOIN 
    rent_strategic_regions AS sr
        ON l.concat_city_neighborhood = sr.concat_city_neighborhood
        AND l.year_month_publication_reference = sr.year_month_reference