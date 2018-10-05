select distinct lat, lng, cep
  from datalake_raw.crawlers
where started_on = date '{started_on}'
  and ((lat is not null and lng is not null) or (cep is not null and trim(cep) != ''))
  and (neighborhood is null or city is null
  or trim(neighborhood) = '' or trim(city) = '')
