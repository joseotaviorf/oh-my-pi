create or replace view public.vw_property_listing as
with filt as (
  select
	id,
	status_time,
	status_history,
	row_number() over (partition by id order by status_time) as rn
	from imovel_status_history
	where status_history in ('despublicado', 'publicado', 'alugado', 'suspenso')
--	and id = 892769994
), not_pub as (
  select
    filt.id,
    'publicado'::varchar(255) as status_history,
    date_trunc('seconds', i.first_publication) as status_time
  from
    filt
  left join
    imovel i
   on i.id = filt.id
  where filt.rn = 1
    and date_trunc('seconds', i.first_publication) != date_trunc('seconds', filt.status_time)
), aux_ish as (
  select
    id,
	status_time,
	status_history
  from filt
  where case
          when status_history = 'despublicado'
            then rn != 1
          else true
        end
  union all
  select
    id,
	status_time,
	status_history
  from not_pub
), ish as (
  select
	status_history,
    status_time,
    id,
    row_number() over (partition by id order by status_time) as rn,
    row_number() over (partition by id, status_history order by status_time) as rn_status
  from
		aux_ish
  where status_history in ('alugado', 'publicado', 'despublicado', 'suspenso')
  order by status_time asc
), contract_dates as (
    select id, imovel_id, least("dataAssinado", "dataInicio", "dataEntrada", "dataMinutaAprovada")::date as l,
    greatest("dataAssinado", "dataInicio", "dataEntrada", "dataMinutaAprovada")::date as g
    from contract
    where tipo = 'FullService'
      and status in ('Finalizado', 'Ativo')
), rent as (
    select distinct ish.id, max(ish.status_time) over (partition by ish.id, c.id) as status_time
    from ish
    join contract_dates c
      on ish.id = c.imovel_id
         and ish.status_time::date between l - interval '1 days' and g + interval '1 days'
    where ish.status_history = 'alugado'
), diff_status as (
  select
    row_number() over (partition by act.id order by act.status_time asc) as rn_status,
    row_number() over (partition by act.id, act.status_history order by act.status_time asc) as dr_status,
    act.id,
    act.status_history as status,
    act.status_time,
    nxt_status.status_history as next_status,
    nxt_status.status_time as next_status_time,
    nxt.status_history as next_different_status,
    nxt.status_time as next_different_status_time
  from
    ish act
  left join
    ish nxt_status
    on act.id = nxt_status.id
  	and act.status_history = nxt_status.status_history
    and act.rn_status = nxt_status.rn_status-1
  left join
  	ish nxt
    on act.id = nxt.id
  	and act.status_history != nxt.status_history
    and act.rn = nxt.rn-1
  order by
  	act.rn
), check_status as (
  select
    ds.*,
    r.id as r_id,
    ds.status = 'publicado' and dr_status = 1 as start_first_pub,
    ds.status = 'publicado' and lag(ds.status) over w = 'alugado'	and lag(r.id) over w is not null as start_pub_after_rent,
    ds.status = 'publicado' and (lag(ds.status) over w = 'despublicado' and ds.status_time - lag(ds.status_time) over w >= interval '90 days') as start_after_depub_90,
    (ds.status = 'publicado' and (lag(ds.status) over w = 'despublicado' and lag(ds.status, 2) over w = 'alugado' and lag(r.id,2) over w is not null)) or
    (ds.status = 'publicado' and (lag(ds.status) over w = 'suspenso' and lag(ds.status, 2) over w = 'alugado' and lag(r.id,2) over w is not null)) as start_after_depub_rent,
    (ds.status = 'alugado' and r.id is not null and lead(ds.status) over w = 'publicado') or
    (ds.status = 'alugado' and r.id is not null and lead(ds.status) over w = 'suspenso' and lead(ds.status,2) over w = 'publicado') end_pub_after_rent,
    ds.status = 'despublicado' and (lead(ds.status) over w = 'publicado' and lead(ds.status_time) over w - ds.status_time >= interval '90 days') as end_depub_90,
    ds.status = 'despublicado' and lag(ds.status) over w = 'alugado'	and lag(r.id) over w is not null as end_depub_rent,
    (ds.rn_status = max(ds.rn_status) over (partition by ds.id)) as end_last_status
  from
    diff_status ds
  left join rent r
   on ds.id = r.id
    and ds.status_time = r.status_time
  window
  	w as (partition by ds.id order by ds.status_time)
), aux_times as (
  select distinct
    id,
    status,
    status_time,
    r_id,
    case
    	when (end_pub_after_rent or end_depub_rent) then 1
    	when (status = 'alugado' and end_last_status) then 1
    	else 0
  	end as rent,
		case
			when (start_first_pub and end_last_status) then status_time
			when (start_first_pub) then status_time
			else lag(status_time) over w
		end as min_version_time,
		case
			when end_last_status then null
			else status_time
		end as max_version_time,
		case
			when (lag(start_first_pub) over w or start_first_pub) then 'First Listing'
			when lag(start_pub_after_rent) over w then 'Re-Listing'
			when lag(start_after_depub_rent) over w then 'Re-Listing'
			when start_pub_after_rent and end_last_status then 'Re-Listing'
			when start_after_depub_rent and end_last_status then 'Re-Listing'
			when lag(start_after_depub_90) over w then 'Recovered'
			when start_after_depub_90 and end_last_status then 'Recovered'
		end as start_version_category,
		case
			when end_last_status then null
			when end_pub_after_rent or end_depub_rent then 'Rented'
			when end_depub_90 then 'Depublished'
		end as end_version_category,
		case when end_last_status then 1 else 0 end as is_last_version,
--    start_first_pub,start_pub_after_rent,start_after_depub_90,start_after_depub_rent,end_pub_after_rent,end_depub_90,end_depub_rent,end_last_status,
    (end_pub_after_rent or end_depub_90 or end_depub_rent or end_last_status) as _end
  from
    check_status
  where
    start_first_pub or start_pub_after_rent or start_after_depub_90 or start_after_depub_rent or
    end_pub_after_rent or end_depub_90 or end_depub_rent or end_last_status
window w as (partition by id order by status_time)
), times as (
	select
		id,
		status,
		status_time,
		min_version_time,
		max_version_time,
		min(status_time) over w as first_publication_date,
		sum(rent) over (partition by id order by status_time rows unbounded preceding) as nr_renting,
		start_version_category,
		end_version_category,
		is_last_version,
		_end
	from
		aux_times
	window
		w as (partition by id order by status_time)
	order by status_time
)
select
	id,
	status,
	rank() over (partition by id order by status_time) as version,
	min_version_time,
	max_version_time,
	nr_renting,
	first_publication_date,
	start_version_category,
	end_version_category,
	is_last_version
from
	times
where _end is true
;