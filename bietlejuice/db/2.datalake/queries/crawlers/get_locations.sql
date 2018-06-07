select distinct
  type,
  lat,
  lng,
  street,
  neighborhood
from datalake_raw.crawlers
where ws = '{ws}'
  and started_on = date '{started_on}'
  and not regexp_like(advertiser_name, '(?i)quinto ?andar')
  and regexp_like(lower(city), 's.o paulo')
  and date(if(updated_on != '', substr(updated_on, 1, 10))) >= date '{since}'
  and type not in ('FLAT')
;