select
  cast(lat as float) as lat,
  cast(lng as float) as lng,
  cast(city_name as varchar) as city_name,
  cast(neighborhood as varchar) as neighborhood,
  cast(region_code as varchar) as region_code,
  cast(iptu_quantity_of_apartments as int) as iptu_quantity_of_apartments,
  round(cast(qa_ongoing_contracts as int) / cast(iptu_quantity_of_apartments as float) * 100, 3) as "Ongoing_Contracts_Share",
  round(cast(qa_ongoing_listing as int) / cast(iptu_quantity_of_apartments as float) * 100, 3) as "Ongoing_Listings_Share",
  round((cast(qa_ongoing_contracts as int) + cast(qa_ongoing_listing as int)) / cast(iptu_quantity_of_apartments as float) * 100, 3) as "Total_5A_Share",
  cast(condo_name as varchar) as condo_name,
  cast(telephone as varchar) as telephone,
  cast(email as varchar) as email,
  cast(google_formatted_address as varchar) as google_formatted_address,
  cast(cast(condo_construction_year as float) as int) as condo_construction_year,
  cast(cnpj as varchar) as cnpj,
  cast(qa_ongoing_contracts as int) as qa_ongoing_contracts,
  cast(qa_ongoing_listing as int) as qa_ongoing_listing,
  cast(nullif(qa_avg_total_value, 'NaN') as float) as qa_avg_total_value,
  cast(qa_unpublished as int) as qa_unpublished,
  cast(qa_min_bedrooms as int) as qa_min_bedrooms,
  cast(qa_max_bedrooms as int) as qa_max_bedrooms,
  cast(cast(qa_max_area as float) as int) as qa_max_area,
  cast(cast(qa_min_area as float) as int) as qa_min_area,
  cast(qa_elevator as varchar) as qa_elevator,
  cast(qa_entrance as varchar) as qa_entrance,
  cast(qa_key_location as varchar) as qa_key_location,
  cast(qa_leads_last_120_days as int) as qa_leads_last_120_days,
  cast(qa_converted_leads_last_120_days as int) as qa_converted_leads_last_120_days,
  cast(qa_doormen as varchar) as qa_doormen,
  cast(qa_doormen_name as varchar) as qa_doormen_name,
  cast(qa_doormen_telephone as varchar) as qa_doormen_telephone,
  cast(qa_doormen_email as varchar) as qa_doormen_email,
  cast(competitors_advertiser as varchar) as competitors_advertiser,
  cast(competitors_listings as int) as competitors_listings,
  cast(nullif(competitors_avg_total_value, 'NaN') as float) as competitors_avg_total_value,
  cast(competitors_listing_last_date as varchar) as competitors_listing_last_date
from datamarts.external_condos
where
  (
    qa_ongoing_contracts is not null
    or qa_ongoing_listing is not null
  )
  and ("Total_5A_Share" < 100 or "Ongoing_Contracts_Share" < 100 or "Ongoing_Listings_Share" < 100)
  and cast(iptu_quantity_of_apartments as float) >= 20
