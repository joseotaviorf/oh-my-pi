WITH sale_listings AS (
  SELECT 
    l.id_house,
    h.id_region,
    h.sale_price,
    h.sale_price/NULLIF(h.total_area, 0) AS price_m2,
    h.total_area
  FROM
    datalake_ebdb_clean.listing_business_context AS l
  LEFT JOIN 
    datalake_ebdb_listing.house AS h
      ON h.id = l.id_house
  WHERE 
    l.business_context = 'SALE'
    AND l.ts_first_publication IS NOT NULL 
),
segmentation AS (
  SELECT 
    l.id_house,
    COALESCE(p.tag, 'R$ Undefined') AS price_bin,
    COALESCE(pm2.tag, 'R$ Undefined') AS price_m2_bin,
    COALESCE(ta.tag, 'R$ Undefined') AS total_area_bin
  FROM
    sale_listings AS l
  LEFT JOIN
    datalake_sale_listings_lenses.segmentation_bins AS p 
      ON p.bin = 'price' 
      AND (l.sale_price >= p.lower_band AND l.sale_price < p.upper_band)
  LEFT JOIN
    datalake_sale_listings_lenses.segmentation_bins AS pm2
      ON pm2.bin = 'price_m2' 
      AND (l.price_m2 >= pm2.lower_band AND l.price_m2 < pm2.upper_band)
  LEFT JOIN
    datalake_sale_listings_lenses.segmentation_bins AS ta
      ON ta.bin = 'total_area' 
      AND (l.total_area >= ta.lower_band AND l.total_area < ta.upper_band)
),
pricing AS (
  SELECT 
    id_house,
    tier AS pricing_tier,
    tier_name AS pricing_name,
    tier_disclaimer AS pricing_disclaimer
  FROM
    datalake_sale_listings_lenses.pricing_lens
  WHERE 
    is_last_tier
),
demand AS (
  SELECT
    id_house,
    tier AS demand_tier,
    tier_name AS demand_name,
    tier_disclaimer AS demand_disclaimer
  FROM 
    datalake_sale_listings_lenses.demand_lens
  WHERE 
    is_last_tier
),
avaiability AS (
  SELECT 
    id_house,
    tier AS availability_tier,
    tier_name AS availability_name,
    tier_disclaimer AS availability_disclaimer,
    tier_drill_down AS availability_drill_down
  FROM
    datalake_sale_listings_lenses.availability_lens
  WHERE 
    is_last_tier
),
sellability AS (
  SELECT 
    id_house,
    tier AS sellability_tier,
    tier_name AS sellability_name
  FROM
    datalake_sale_listings_lenses.sellability_lens
  WHERE 
    is_last_tier
),
listing_quality AS (
  SELECT
    id_house,
    tier AS listing_quality_tier,
    tier_name AS listing_quality_name,
    tier_disclaimer AS listing_quality_disclaimer,
    tier_drill_down AS listing_quality_drill_down
  FROM 
    datalake_sale_listings_lenses.listing_quality_lens
  WHERE
    is_last_tier
),
dataset AS (
  SELECT 
    id_house,
    l.id_region,
    s.price_bin,
    s.price_m2_bin,
    s.total_area_bin,
    COALESCE(p.pricing_tier, 'P-') AS pricing_tier,
    COALESCE(d.demand_tier, 'D-') AS demand_tier,
    COALESCE(a.availability_tier, 'A-') AS availability_tier,
    COALESCE(se.sellability_tier, 'S-') AS sellability_tier,
    COALESCE(lq.listing_quality_tier, 'Q-') AS listing_quality_tier,
    COALESCE(p.pricing_name, 'Undefined') AS pricing_name,
    COALESCE(d.demand_name, 'Undefined') AS demand_name,
    COALESCE(a.availability_name, 'Undefined') AS availability_name,
    COALESCE(se.sellability_name, 'Undefined') AS sellability_name,
    COALESCE(lq.listing_quality_name, 'Undefined') AS listing_quality_name,
    p.pricing_disclaimer,
    d.demand_disclaimer,
    a.availability_disclaimer,
    a.availability_drill_down,
    lq.listing_quality_disclaimer,
    lq.listing_quality_drill_down
  FROM
    sale_listings AS l
  LEFT JOIN
    segmentation AS s 
      USING(id_house)
  LEFT JOIN 
    pricing AS p 
      USING(id_house)
  LEFT JOIN 
    demand AS d 
      USING(id_house)
  LEFT JOIN 
    avaiability AS a
      USING(id_house)
  LEFT JOIN 
    sellability AS se
      USING(id_house)
  LEFT JOIN 
    listing_quality AS lq
      USING(id_house)
),
full_name AS (
  SELECT 
    id_house,
    id_region,
    price_bin,
    price_m2_bin,
    total_area_bin,
    pricing_tier,
    demand_tier,
    availability_tier,
    sellability_tier,
    listing_quality_tier,
    pricing_name,
    demand_name,
    availability_name,
    sellability_name,
    listing_quality_name,
    pricing_tier || ': ' || pricing_name AS pricing_full_name,
    demand_tier || ': ' || demand_name AS demand_full_name,
    availability_tier || ': ' || availability_name AS availability_full_name,
    sellability_tier || ': ' || sellability_name AS sellability_full_name,
    listing_quality_tier || ': ' || listing_quality_name AS listing_quality_full_name,
    pricing_disclaimer,
    demand_disclaimer,
    availability_disclaimer,
    availability_drill_down,
    listing_quality_disclaimer,
    listing_quality_drill_down
  FROM
    dataset
)
SELECT 
  id_house,
  id_region,
  price_bin ||'  &  '|| total_area_bin || '  |  ' || pricing_tier || '  |  ' || availability_tier || '  |  ' || demand_tier || '  |  ' || sellability_tier || '  |  ' || listing_quality_name AS listing_lenses,
  price_bin ||'  &  '|| total_area_bin || '  |  ' || pricing_full_name || '  |  ' || availability_full_name || '  |  ' || demand_full_name || '  |  ' || sellability_full_name || '  |  ' || listing_quality_full_name AS full_listing_lenses,
  price_bin,
  price_m2_bin,
  total_area_bin,
  pricing_tier,
  demand_tier,
  availability_tier,
  sellability_tier,
  listing_quality_tier,
  pricing_name,
  demand_name,
  availability_name,
  sellability_name,
  listing_quality_name,
  pricing_full_name,
  demand_full_name,
  availability_full_name,
  sellability_full_name,
  listing_quality_full_name,
  pricing_disclaimer,
  demand_disclaimer,
  availability_disclaimer,
  availability_drill_down,
  listing_quality_disclaimer,
  listing_quality_drill_down
FROM
  full_name