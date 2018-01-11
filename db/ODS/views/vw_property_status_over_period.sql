drop view if exists vw_property_status_over_period;
create or replace view public.vw_property_status_over_period as
with dup as (
  select
    ((p.id || '00') || COALESCE(p.version, 1))::bigint AS sk_property,
    p.id,
    p.min_version_time::date as pub_date,
    p."version",
    (i.date - p.min_version_time::date)::varchar || ' days' as days,
    max(i.status_time) over (partition by p.id, (i.date - p.min_version_time::date)) as max_t,
    i.status_time,
    i.date as date,
    i.status_history as status
  from vw_property_listing  p
  join imovel_status_full_history i
    on i.id = p.id
       and i.date in (
            p.min_version_time::date + interval '7' day,
            p.min_version_time::date + interval '14' day,
            p.min_version_time::date + interval '21' day,
            p.min_version_time::date + interval '28' day,
            p.min_version_time::date + interval '35' day,
            p.min_version_time::date + interval '42' day,
            p.min_version_time::date + interval '49' day,
            p.min_version_time::date + interval '56' day
       )
)
select
  sk_property,
  id,
  pub_date,
  "version",
  days,
  "date",
  status
from dup
where max_t = status_time
;