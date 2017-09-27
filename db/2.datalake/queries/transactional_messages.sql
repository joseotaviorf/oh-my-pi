with max_tm as (
  select
    messageid, max(dt) as max_dt
  from datalake_raw.cm_transactional_messages
  where project = '{0}'
  group by messageid
),
transactional_messages as (
  select distinct
    ctm.canberesent,
    ctm.message.subject as subject,
    regexp_extract(ctm.recipient, '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+') as email_to,
    regexp_extract(message."from", '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+') as email_from,
    ctm.messageid,
    ctm.sentat,
    ctm.smartemailid,
    ctm.status,
    ctm.totalclicks,
    ctm.totalopens,
    regexp_extract_all(ctm.message.body.text, 'https://quintoandar.com.br/imovel/(\d+)', 1) as property_ids
  from datalake_raw.cm_transactional_messages ctm
  join max_tm mt
   on ctm.messageid = mt.messageid
    and ctm.dt = mt.max_dt
  where ctm.project = '{0}'
),
clicks as (
  select distinct
    tm.messageid,
    c.click.emailaddress as emailaddress,
    c.click.url as url,
    892700000 + cast(regexp_extract(c.click.url, 'prop-receb-(.*)-', 1) as bigint) as imovelid,
    null as first_opened_date,
    c.click.date as "date",
    c.click.geolocation.city as city,
    c.click.geolocation.countrycode as countrycode,
    c.click.geolocation.countryname as countryname,
    c.click.geolocation.region as region,
    c.click.geolocation.longitude as longitude,
    c.click.geolocation.latitude as latitude,
    null as opened,
    true as clicked
  from datalake_raw.cm_transactional_messages tm
  cross join unnest(tm.clicks) as c (click)
  where tm.project = '{0}'
),
opens as (
  select distinct
    tm.messageid,
    o.open.emailaddress,
    null as url,
    null as imovelid,
    min(o.open."date") over (partition by tm.messageid) as first_opened_date,
    o.open."date" as "date",
    o.open.geolocation.city as city,
    o.open.geolocation.countrycode as countrycode,
    o.open.geolocation.countryname as countryname,
    o.open.geolocation.region as region,
    o.open.geolocation.longitude as longitude,
    o.open.geolocation.latitude as latitude,
    true as opened,
    null as clicked
  from datalake_raw.cm_transactional_messages tm
  cross join unnest(tm.opens) as o (open)
  where tm.project = '{0}'
),
link_interactions as (
  select distinct
    messageid,
    emailaddress,
    url,
    imovelid,
    first_opened_date,
    "date",
    city,
    countrycode,
    countryname,
    region,
    longitude,
    latitude,
    opened,
    clicked
  from opens o
  union
  select distinct
    messageid,
    emailaddress,
    url,
    imovelid,
    first_opened_date,
    "date",
    city,
    countrycode,
    countryname,
    region,
    longitude,
    latitude,
    opened,
    clicked
  from clicks c
)
select
  tm.canberesent,
  tm.subject,
  tm.email_from,
  tm.email_to,
  tm.messageid,
  tm.sentat,
  tm.smartemailid,
  tm.status,
  tm.totalclicks,
  tm.totalopens,
  892700000 + cast(p.props as bigint) as property_email_id,
  row_number() over (partition by tm.messageid) as rn_property_email_id,
  li.url,
  li.imovelid as property_link_id,
  li.first_opened_date,
  li."date",
  li.city,
  li.countrycode,
  li.countryname,
  li.region,
  li.longitude,
  li.latitude,
  li.opened,
  li.clicked
from transactional_messages tm
cross join unnest(tm.property_ids) as p (props)
left join link_interactions li
on tm.messageid = li.messageid