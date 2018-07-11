-- TODO: Migrate to datalake_clean.crawled_listings when it is ready

with listings as (
  select
    id,
    ws,
    min(started_on) as first_seen,
    max(started_on) as last_seen,
    max(try(cast(regexp_extract(updated_on, '^(\d{4}-\d{2}-\d{2}).*', 1) as date))) as last_update
  from datalake_raw.crawlers
  where ws in ('vivareal', 'zapimoveis')
  group by 1, 2
)
, locations as (
  select distinct
    id,
    ws,
    if(street <> 'Endereço Não Informado' and street <> '', split(street, ',')[1]) as street,
    try(cast(regexp_replace(regexp_extract(street, ',[ +]?(n\. )?(\d+(\.\d+)?)([ |\/].*)?(,.*)?$', 2), '\D+', '') as integer)) as street_number,
    try(cast(lat as double)) as latitude,
    try(cast(lng as double)) as longitude
  from datalake_raw.crawlers
  where ws in ('vivareal', 'zapimoveis')
    and started_on >= date '__LAST_CRAWLER_RUN__'
    and regexp_like(city, '(?i)s[a|ã]o ?paulo')
    and not regexp_like(advertiser_name, '(?i)quinto ?andar')
)
, ds as (
  select distinct
    rank() over (partition by loc.street order by length(st.prefix) desc) as rnk,
    st.abbreviation,
    st.prefix,
    loc.street,
    loc.street_number
  from locations loc
  join listings lis
    on loc.id = lis.id and loc.ws = lis.ws
  join datalake_raw.ebdb_poligonoregiao pr
    on ST_Contains(ST_Polygon(pr.poligono), ST_Point(loc.longitude, loc.latitude))
  left join datalake_raw.street_type st
    on strpos(replace(loc.street, ' ', ''), replace(st.prefix, ' ', '')) = 1
      and st.city = 'sp'
  where lis.first_seen >= date '__LAST_CRAWLER_RUN__'
    and loc.street_number is not null
    and loc.latitude is not null
    and loc.longitude is not null
)
select
  trim(abbreviation) as abbreviation,
  case
    when abbreviation is null then try(upper(trim(substr(street, strpos(street, ' ')))))
    else trim(upper(substr(street, length(prefix)+1)))
  end as street_name,
  street_number
from ds
where rnk = 1