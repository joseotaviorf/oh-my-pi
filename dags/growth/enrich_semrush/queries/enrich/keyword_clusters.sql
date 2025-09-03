WITH categories_and_subcategories AS (
SELECT
  id_region_match_operation_city,
  id_region_match_operation_neighborhood,
  player AS player_name,
  keyword,
  keyword_clean,
  match_igbe_city,
  match_operation_city,
  match_operation_neighborhood,
  url,
  trends,
  position,
  previous_position,
  position_difference,
  keyword_intents,
  position_type,
  serp_features_by_position,
  serp_features_by_keyword,
  search_volume,
  MAX(search_volume) OVER (PARTITION BY keyword_clean, year, month) AS max_seach_volume_by_kw,
  cpc,
  traffic,
  share_of_traffic,
  traffic_cost_percentage,
  competition,
  number_of_results,
  keyword_difficulty,
  is_goldenset,
  has_mention_to_location,
  has_mention_to_neighborhood,
  has_mention_to_city,
  has_mention_to_country,
  has_mention_to_cep,
  has_mention_to_city_zone,
  has_mention_to_agent,
  has_mention_to_apartment,
  has_mention_to_brokerage,
  has_mention_to_company,
  has_mention_to_condo,
  has_mention_to_condo_facilities,
  has_mention_to_construction,
  has_mention_to_decor,
  has_mention_to_e_classified,
  has_mention_to_guide_tips,
  has_mention_to_helps_doubts,
  has_mention_to_house_type,
  has_mention_to_house_facilities,
  has_mention_to_kitnet,
  has_mention_to_law_taxes_market,
  has_mention_to_life_hack,
  has_mention_to_non_related,
  has_mention_to_number,
  has_mention_to_other_house_types,
  has_mention_to_other_info,
  has_mention_to_platform,
  has_mention_to_poi,
  has_mention_to_rent,
  has_mention_to_sale,
  has_mention_to_short_term_homestays,
  has_mention_to_short_term_rental,
  has_mention_to_state,
  has_mention_to_street,
  has_mention_to_transaction_info_doubts,
  has_mention_to_vacation,
  rent_subcategories,

  CASE 
    WHEN CONTAINS(keyword_clean, 'ipca 20') THEN 0
    WHEN has_mention_to_non_related = 1 THEN 0
    WHEN has_mention_to_other_house_types = 1 THEN 0
    WHEN match_operation_city <> '' THEN 1
    WHEN match_operation_neighborhood <> '' THEN 1
    WHEN has_mention_to_apartment = 1 THEN 1
    WHEN has_mention_to_house_type = 1 THEN 1
    WHEN has_mention_to_kitnet = 1 THEN 1
  ELSE 1
  END AS business,

  CASE 
    WHEN has_mention_to_rent = 1 AND has_mention_to_short_term_rental = 1 THEN 1
    WHEN has_mention_to_rent = 1 THEN 1
    WHEN has_mention_to_sale = 1 THEN 1
    WHEN has_mention_to_vacation = 1 THEN 1
  ELSE 0
  END AS transactional,

  CASE 
    WHEN keyword_clean LIKE 'casas para alugar%' THEN 0
    WHEN has_mention_to_decor = 1 AND (has_mention_to_rent = 1 OR has_mention_to_sale = 1) THEN 0 
    WHEN has_mention_to_decor = 1 THEN 1
    WHEN has_mention_to_transaction_info_doubts = 1 THEN 1
    WHEN has_mention_to_law_taxes_market = 1 THEN 1
    WHEN has_mention_to_guide_tips = 1 THEN 1
    WHEN has_mention_to_helps_doubts = 1 THEN 1
    WHEN has_mention_to_life_hack = 1 THEN 1
    WHEN has_mention_to_other_info = 1 THEN 1
  ELSE 0
  END AS informational,

  CASE 
    WHEN has_mention_to_cep = 1 THEN 1
    WHEN has_mention_to_city = 1 THEN 1
    WHEN has_mention_to_city_zone = 1 THEN 1
    WHEN has_mention_to_state = 1 THEN 1
    WHEN has_mention_to_street = 1 THEN 1
    WHEN has_mention_to_neighborhood = 1 THEN 1
    WHEN has_mention_to_poi = 1 THEN 1
    WHEN has_mention_to_condo = 1 THEN 1
    WHEN has_mention_to_country = 1 THEN 1
  ELSE 0
  END AS location,

  CASE 
    WHEN has_mention_to_house_type = 1 THEN 1
    WHEN has_mention_to_kitnet = 1 THEN 1
    WHEN has_mention_to_other_house_types = 1 THEN 1
    WHEN has_mention_to_apartment = 1 THEN 1
  ELSE 0
  END AS house_flag,

  CASE 
    WHEN has_mention_to_agent = 1 THEN 1
    WHEN has_mention_to_brokerage = 1 THEN 1
    WHEN has_mention_to_company = 1 THEN 1
    WHEN has_mention_to_construction = 1 THEN 1
    WHEN has_mention_to_e_classified = 1 THEN 1
    WHEN has_mention_to_platform = 1 THEN 1
    WHEN has_mention_to_short_term_homestays = 1 THEN 1
  ELSE 0
  END AS player,

  CASE 
    WHEN has_mention_to_condo_facilities = 1 THEN 1
    WHEN has_mention_to_house_facilities = 1 THEN 1
  ELSE 0
  END AS amenities,

  CASE 
    WHEN has_mention_to_rent = 1 AND has_mention_to_short_term_rental = 1 THEN 'Short Term Rental'
    WHEN has_mention_to_rent = 1 AND has_mention_to_vacation = 1 THEN 'Vacation Rental'
    WHEN has_mention_to_rent = 1 THEN 'Rent'
    WHEN has_mention_to_sale = 1 THEN 'Sale'
  ELSE 0
  END AS transactional_type,

  CASE 
    WHEN has_mention_to_decor = 1 THEN 'Decor'
    WHEN has_mention_to_transaction_info_doubts = 1 THEN 'Transaction Info/Doubts'
    WHEN has_mention_to_guide_tips = 1 THEN 'Guide and Tips'
    WHEN has_mention_to_law_taxes_market = 1 THEN 'Law, Taxes and Market'
    WHEN has_mention_to_helps_doubts = 1 THEN 'Helps and Doubts'
    WHEN has_mention_to_life_hack = 1 THEN 'Life Hack'
    WHEN has_mention_to_other_info = 1 THEN 'Other'
  ELSE 0
  END AS informational_type,

  CASE 
    WHEN has_mention_to_cep = 1 THEN 'CEP'
    WHEN has_mention_to_condo = 1 THEN 'Condo'
    WHEN has_mention_to_poi = 1 THEN 'POI'
    WHEN has_mention_to_street = 1 AND has_mention_to_number = 1 THEN 'Address'
    WHEN has_mention_to_street = 1 THEN 'Street'
    WHEN has_mention_to_neighborhood = 1 AND (LENGTH(match_operation_neighborhood) >= LENGTH(match_igbe_city)) AND (LENGTH(match_operation_neighborhood) >= LENGTH(match_operation_city)) THEN 'Neighborhood'
    WHEN has_mention_to_neighborhood = 1 AND LENGTH(match_operation_neighborhood) > 0 AND ((CHARINDEX(match_operation_neighborhood, match_igbe_city) = 0) AND (CHARINDEX(match_operation_neighborhood, match_operation_city) = 0)) THEN 'Neighborhood'
    WHEN match_igbe_city = match_operation_neighborhood AND match_operation_neighborhood != match_operation_city THEN 'Neighborhood'
    WHEN has_mention_to_neighborhood = 1 AND LENGTH(match_operation_neighborhood) = 0 THEN 'Neighborhood'
    WHEN has_mention_to_neighborhood = 1 AND keyword_clean LIKE '%bairro%' THEN 'Neighborhood'
    WHEN has_mention_to_city_zone = 1 THEN 'City Zone'
    WHEN has_mention_to_city = 1 THEN 'City'
    WHEN has_mention_to_state = 1 THEN 'State'
    WHEN has_mention_to_country = 1 THEN 'Country'
  ELSE 0
  END AS local_type,

  CASE 
    WHEN has_mention_to_kitnet = 1 THEN 'Kitnet'
    WHEN has_mention_to_apartment = 1 THEN 'Apartment'
    WHEN has_mention_to_house_type = 1 THEN 'House'
    WHEN has_mention_to_other_house_types = 1 THEN 'Other'
  ELSE 0
  END AS house_type,

  CASE 
    WHEN has_mention_to_e_classified = 1 THEN 'E-Classified'
    WHEN has_mention_to_platform = 1 THEN 'Platform'
    WHEN has_mention_to_short_term_homestays = 1 THEN 'Short Term Homestays'
    WHEN has_mention_to_agent = 1 THEN 'Agent'
    WHEN has_mention_to_brokerage = 1 THEN 'Brokerage'
    WHEN has_mention_to_construction = 1 THEN 'Construction'
    WHEN has_mention_to_company = 1 THEN 'Company'
  ELSE 0
  END AS player_type,

  CASE 
    WHEN has_mention_to_condo_facilities = 1 THEN 'Condo Facilities'
    WHEN has_mention_to_house_facilities = 1 THEN 'House Facilities'
  ELSE 0
  END AS amenity_type,
  dt_display,
  dt_report,
  ts_report,
  year,
  month,
  day 
FROM 
  datalake_semrush.keyword_attributes
WHERE
  year = YEAR(DATE('{load_start_date}'))
  AND month = MONTH(DATE('{load_start_date}'))
)

SELECT
  id_region_match_operation_city,
  id_region_match_operation_neighborhood,
  player_name,
  keyword,
  keyword_clean,
  match_igbe_city,
  match_operation_city,
  match_operation_neighborhood,
  url,
  trends,
  position,
  previous_position,
  position_difference,
  keyword_intents,
  position_type,
  serp_features_by_position,
  serp_features_by_keyword,
  search_volume,
  max_seach_volume_by_kw,
  cpc,
  traffic,
  share_of_traffic,
  traffic_cost_percentage,
  competition,
  number_of_results,
  keyword_difficulty,
  is_goldenset,
  has_mention_to_location,
  has_mention_to_neighborhood,
  has_mention_to_city,
  has_mention_to_country,
  has_mention_to_cep,
  has_mention_to_city_zone,
  has_mention_to_agent,
  has_mention_to_apartment,
  has_mention_to_brokerage,
  has_mention_to_company,
  has_mention_to_condo,
  has_mention_to_condo_facilities,
  has_mention_to_construction,
  has_mention_to_decor,
  has_mention_to_e_classified,
  has_mention_to_guide_tips,
  has_mention_to_helps_doubts,
  has_mention_to_house_type,
  has_mention_to_house_facilities,
  has_mention_to_kitnet,
  has_mention_to_law_taxes_market,
  has_mention_to_life_hack,
  has_mention_to_non_related,
  has_mention_to_number,
  has_mention_to_other_house_types,
  has_mention_to_other_info,
  has_mention_to_platform,
  has_mention_to_poi,
  has_mention_to_rent,
  has_mention_to_sale,
  has_mention_to_short_term_homestays,
  has_mention_to_short_term_rental,
  has_mention_to_state,
  has_mention_to_street,
  has_mention_to_transaction_info_doubts,
  has_mention_to_vacation,
  rent_subcategories,
  business,
  transactional,
  informational,
  location,
  house_flag,
  player,
  amenities,
  transactional_type,
  informational_type,
  local_type,
  house_type,
  player_type,
  amenity_type,
  CASE
    WHEN has_mention_to_non_related = 1 THEN 'Non-Related'
    WHEN (has_mention_to_rent = 1 OR has_mention_to_sale = 1) AND has_mention_to_decor = 1 THEN 'Non-Related'
    WHEN player = 1 THEN 'Player'
    WHEN informational = 1 THEN 'Informational'
    WHEN has_mention_to_rent = 1 AND location = 1 THEN 'Rent Local'
    WHEN has_mention_to_rent = 1 THEN 'Rent Generic'
    WHEN has_mention_to_sale = 1 AND location = 1 THEN 'Sale Local'
    WHEN has_mention_to_sale = 1 THEN 'Sale Generic'
    WHEN house_flag = 1 AND location = 1 THEN 'House Type Local'
    WHEN house_flag = 1 THEN 'House Type Generic'
    WHEN location = 1 THEN 'Local'
    ELSE 'Unallocated'
  END AS cluster_macro,
  CASE
    WHEN has_mention_to_non_related = 1 THEN 'Non-Related'
    WHEN (has_mention_to_rent = 1 OR has_mention_to_sale = 1) AND has_mention_to_decor = 1 THEN 'Non-Related'

    WHEN player = 1 AND informational = 1 AND location = 1 AND house_flag = 1 THEN 'Player with informational, local and house type'
    WHEN player = 1 AND has_mention_to_rent = 1 AND location = 1 AND house_flag = 1 THEN 'Player with rent, local and house type'
    WHEN player = 1 AND has_mention_to_sale = 1 AND location = 1 AND house_flag = 1 THEN 'Player with sale, local and house type'

    WHEN player = 1 AND informational = 1 AND location = 1 AND house_flag = 0 THEN 'Player with informational and local'
    WHEN player = 1 AND has_mention_to_rent = 1 AND location = 1 AND house_flag = 0 THEN 'Player with rent and local'
    WHEN player = 1 AND has_mention_to_sale = 1 AND location = 1 AND house_flag = 0 THEN 'Player with sale and local'

    WHEN player = 1 AND informational = 1 AND location = 0 AND house_flag = 1 THEN 'Player with informational and house type'
    WHEN player = 1 AND has_mention_to_rent = 1 AND location = 0 AND house_flag = 1 THEN 'Player with rent and house type'
    WHEN player = 1 AND has_mention_to_sale = 1 AND location = 0 AND house_flag = 1 THEN 'Player with sale and house type'

    WHEN player = 1 AND informational = 1 AND location = 0 AND house_flag = 0 THEN 'Player with informational'
    WHEN player = 1 AND has_mention_to_rent = 1 AND location = 0 AND house_flag = 0 THEN 'Player with rent'
    WHEN player = 1 AND has_mention_to_sale = 1 AND location = 0 AND house_flag = 0 THEN 'Player with sale'
    
    WHEN player = 1 AND informational = 0 AND has_mention_to_rent = 0 AND has_mention_to_sale = 0 AND location = 1 AND house_flag = 1 THEN 'Player with local and house type'
    WHEN player = 1 AND informational = 0 AND has_mention_to_rent = 0 AND has_mention_to_sale = 0 AND location = 1 AND house_flag = 0 THEN 'Player with local'
    WHEN player = 1 AND informational = 0 AND has_mention_to_rent = 0 AND has_mention_to_sale = 0 AND location = 0 AND house_flag = 1 THEN 'Player with house type'
    
    WHEN player = 1 AND informational = 0 AND has_mention_to_rent = 0 AND has_mention_to_sale = 0 AND location = 0 AND house_flag = 0 THEN 'Player'
    
    WHEN player = 0 AND informational = 1 AND location = 1 AND house_flag = 1 THEN 'Informational with local and house type'
    WHEN player = 0 AND informational = 1 AND location = 0 AND house_flag = 1 THEN 'Informational with house type'
    WHEN player = 0 AND informational = 1 AND location = 1 AND house_flag = 0 THEN 'Informational with local'
    WHEN player = 0 AND informational = 1 AND location = 0 AND house_flag = 0 THEN 'Informational'
    
    WHEN player = 0 AND informational = 0 AND has_mention_to_rent = 1 AND location = 1 AND house_flag = 1 THEN 'Rent with local and house type'
    WHEN player = 0 AND informational = 0 AND has_mention_to_rent = 1 AND location = 0 AND house_flag = 1 THEN 'Rent with house type'
    WHEN player = 0 AND informational = 0 AND has_mention_to_rent = 1 AND location = 1 AND house_flag = 0 THEN 'Rent with local'
    WHEN player = 0 AND informational = 0 AND has_mention_to_rent = 1 AND location = 0 AND house_flag = 0 THEN 'Rent'
    
    WHEN player = 0 AND informational = 0 AND has_mention_to_sale = 1 AND location = 1 AND house_flag = 1 THEN 'Sale with local and house type'
    WHEN player = 0 AND informational = 0 AND has_mention_to_sale = 1 AND location = 0 AND house_flag = 1 THEN 'Sale with house type'
    WHEN player = 0 AND informational = 0 AND has_mention_to_sale = 1 AND location = 1 AND house_flag = 0 THEN 'Sale with local'
    WHEN player = 0 AND informational = 0 AND has_mention_to_sale = 1 AND location = 0 AND house_flag = 0 THEN 'Sale'
    
    WHEN player = 0 AND informational = 0 AND has_mention_to_rent = 0 AND has_mention_to_sale = 0 AND location = 1 AND house_flag = 1 THEN 'House type with local'
    WHEN player = 0 AND informational = 0 AND has_mention_to_rent = 0 AND has_mention_to_sale = 0 AND location = 0 AND house_flag = 1 THEN 'House type'
    
    WHEN player = 0 AND informational = 0 AND has_mention_to_rent = 0 AND has_mention_to_sale = 0 AND location = 1 AND house_flag = 0 THEN 'Local'
    
    ELSE 'Unallocated'
  END AS cluster_micro,
  dt_display,
  dt_report,
  ts_report,
  year,
  month,
  day 
FROM
   categories_and_subcategories