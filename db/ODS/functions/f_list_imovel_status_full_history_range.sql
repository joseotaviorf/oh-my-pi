DROP FUNCTION IF EXISTS public.f_list_imovel_status_full_history(_offset int, _limit int);

CREATE OR REPLACE FUNCTION public.f_list_imovel_status_full_history(
	_offset int,
	_limit int
)
RETURNS SETOF public.imovel_status_full_history AS

$body$

BEGIN

return query
with rn as
(
  select
    h.id,
    h.status,
    h.status_date,
    h.status_time,
    h.status_history,
    h.current_status,
    h."datePublication",
    h.published,
   	row_number() over (partition by id order by status_time asc) as rnk
  from
    imovel_status_history h
),
dates as
(
  select
    rn.*,
    min(rn.status_date) over (partition by rn.id) as first_status_date,
    max(rn.status_date) over (partition by rn.id) as last_status_date,
    next.status_date as next_status_date,
    next.status_time as next_status_time,
    next.status_history as next_status,
 	coalesce(next.status_time - rn.status_time, '1 day'::interval) as diff_status_time,
    coalesce(next.status_time - rn.status_time, '1 day'::interval) >= '4 hour'::interval and rn.published = 1 as pub_at_least_min_time_flag
  from
  	rn
  left join
 	rn as next
    on next.rnk = rn.rnk+1
    and rn.id = next.id
)

select
  d.date,
  t.*,
  row_number() over (partition by id, status_history order by id, rnk desc, date asc) = 1 as distinct_status_flag,
  row_number() over (partition by t.id, d.date order by t.id, t.rnk desc, d.date DESC) = 1 as last_position_date_flag,
  case when
	-- intervalo minimo entre status
    t.diff_status_time >= '4 hour'::interval and
    (
        row_number() over (partition by id, status_history order by id, rnk desc, date asc) = 1
        or row_number() over (partition by t.id, d.date order by t.id, t.rnk desc, d.date DESC) = 1
    ) then true
    else false
  end as all_status_date_position_flag

from
  dim_date d
left join  dates t
  on (d.date >= t.status_date and d.date <= now())

where

  t.id in
  (
  	select
      distinct id
    from imovel_status_history
    order by id desc
    offset coalesce(_offset, 1000)
    limit coalesce(_limit, 1000)
  )

--  t.id in (892794888, 892794484, 892794992, 892779384)

order by
   id,
   date,
   status_time;

END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY INVOKER
COST 100 ROWS 1000;