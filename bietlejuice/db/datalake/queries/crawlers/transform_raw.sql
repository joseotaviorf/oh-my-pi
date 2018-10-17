select
  cast(id as bigint) as id,
  lower(website) as website,
  url,
  case
    when http_status is null or trim(http_status) = ''
      then null
    else cast(cast(http_status as real) as smallint)
  end as http_status,
  started_on, updated_on, crawled_on,
  lower(business) as business,
  case
    when regexp_like(lower(type), '(casa.*condom.nio)|(condom.nio.*casa)') then 'CasaCondominio'
    when regexp_like(lower(type), '(loft)|(kitnet)|(studio)|(kitchenette)') then 'StudioOuKitchenette'
    when regexp_like(lower(type), '(casa)|(sobrado)') then 'Casa'
    when regexp_like(lower(type), '(apartamento)|(flat)|(cobertura)') then 'Apartamento'
    else lower(type)
  end as type,
  advertiser_name,
  case
    when advertiser_type is null
          and regexp_like(lower(trim(advertiser_name)), '(im.ve)|(auxili)|(alug)|(empre)|(agent)|(constru)|(admin)|(apart)|(i(n?)mobili)|(ltda)|(empreend)|(^lello( ?))|(coelho da fonseca)|(flat)|(^lopes( ?))')
          and not regexp_like(lower(trim(advertiser_name)), '(corretor)')
      then 'imobiliaria'
    when lower(advertiser_type) = 'propietario'
      then 'proprietario'
    else lower(advertiser_type)
  end as advertiser_type,
  regexp_extract(phones, '.(\d+),.(\d+).*', 1) as primary_phone_number,
  regexp_extract(phones, '.(\d+),[^0-9]?(\d+).*', 2) as secondary_phone_number,
  case
    when price is null or trim(price) = ''
      then null
    else cast(price as double)
  end as price,
  case
    when rent is null or trim(rent) = ''
      then null
    else cast(rent as double)
  end as rent,
  case
    when condominium is null or trim(condominium) = ''
      then null
    else cast(condominium as double)
  end as condominium,
  case
    when iptu is null or trim(iptu) = ''
      then null
    else cast(iptu as double)
  end as iptu,
  case
    when total_area is null or trim(total_area) = ''
      then null
    else cast(total_area as double)
  end as total_area,
  case
    when useful_area is null or trim(useful_area) = ''
      then null
    else cast(useful_area as double)
  end as useful_area,
  case
    when bedrooms is null or trim(bedrooms) = ''
      then null
    else cast(cast(bedrooms as real) as smallint)
  end as bedrooms,
  case
    when suites is null or trim(suites) = ''
      then null
    else cast(cast(suites as real) as smallint)
  end as suites,
  case
    when toilets is null or trim(toilets) = ''
      then null
    else cast(cast(toilets as real) as smallint)
  end as toilets,
  case
    when garages is null or trim(garages) = ''
      then null
    else cast(cast(garages as real) as smallint)
  end as garages,
  photos, description, unit_features, common_features, complementary_info,
  case
    when year_building is null or year_building = '' or year_building < '1900'
      then null
    else cast(cast(year_building as real) as integer)
  end as year_building,
  cast(regexp_replace(cep, '\D', '') as varchar) as cep,
  case
    when lat is null or trim(lat) = ''
      then null
    else cast(lat as double)
  end as lat,
  case
    when lng is null or trim(lng) = ''
      then null
    else cast(lng as double)
  end as lng,
  street, neighborhood, city, state, crawl_timestamp
from datalake_raw.crawlers
  where started_on = date '{started_on}'
