WITH sale_strategic_regions AS (
  SELECT DISTINCT
    concat_city_neighborhood,
    is_strategic_region,
    DATE(date_trunc('MONTH', DATEADD(MONTH,1,ts_load))) AS year_month_reference
  FROM
    datalake_gsheets_clean.sale_comission_for_strategic_region
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_region, MONTH(ts_load), YEAR(ts_load) ORDER BY ts_load DESC) = 1   
),
listings_sale AS (
  SELECT
    sl.id_sale_listing,
    h.city AS city_name,
    h.neighborhood AS house_neighborhood,
    h.id_region,
    lbc.ts_first_listing AS ts_first_publication,
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
        WHEN DATE(lbc.ts_first_listing) < DATE("2023-10-01") THEN DATE("2023-09-01")
        ELSE DATE(DATE_TRUNC('MONTH', lbc.ts_first_listing))
    END AS year_month_publication_reference
  FROM 
      datalake_ebdb_listing.listing_business_context AS lbc
  JOIN
      datalake_ebdb_listing.house AS h
        ON h.id = lbc.id_house
  JOIN 
      datalake_sale_listings.sale_listing AS sl 
        ON lbc.id_house = sl.id_house
  WHERE
      CAST(substr(CAST(sl.id_sale_listing AS VARCHAR(15)),-1,3) AS INTEGER) = 1
      AND lbc.business_context = 'SALE'
)
SELECT 
    ls.id_sale_listing,
    ls.id_region,
    ls.city_name,
    ls.house_neighborhood AS neighborhood_name,
    COALESCE(sr.is_strategic_region, FALSE) AS is_strategic_region,
    ls.year_month_publication_reference AS dt_publication_reference,
    ls.ts_first_publication
FROM 
    listings_sale AS ls 
LEFT JOIN 
    sale_strategic_regions AS sr
        ON ls.concat_city_neighborhood = sr.concat_city_neighborhood
        AND ls.year_month_publication_reference = sr.year_month_reference