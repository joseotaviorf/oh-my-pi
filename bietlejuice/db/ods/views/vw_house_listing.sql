drop view if exists vw_house_listing;
create or replace view vw_house_listing as
with filt as (
  select
	id,
	status_time,
	status_history,
	aluguel,
	"tipoPorteiro" as tipo_porteiro,
	row_number() over (partition by id order by status_time) as rn
	from imovel_status_history
	where status_history in ('despublicado', 'publicado', 'alugado', 'suspenso')
),
not_pub as (
  select
    filt.id,
    'publicado'::varchar(255) as status_history,
    date_trunc('seconds', i.first_publication) as status_time,
    filt.aluguel,
    filt.tipo_porteiro
  from filt
  left join imovel i
   on i.id = filt.id
  where filt.rn = 1
    and date_trunc('seconds', i.first_publication) != date_trunc('seconds', filt.status_time)
),
aux_ish as (
  select
    id,
	status_time,
	status_history,
	aluguel,
	tipo_porteiro,
	coalesce(lag(status_history) over (partition by id order by status_time) = status_history, false) as truncatable
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
	status_history,
	aluguel,
	tipo_porteiro,
	false as truncatable
  from not_pub
),
contract_dates as (
    select id, imovel_id, least("dataAssinado", "dataInicio", "dataEntrada", "dataMinutaAprovada")::date as l,
    greatest("dataAssinado", "dataInicio", "dataEntrada", "dataMinutaAprovada")::date as g,
    "dataRescisao" as dt_end
    from contract
    where tipo = 'FullService'
      and status in ('Finalizado', 'Ativo')
),
rent as (
	select distinct
		ish.id,
		ish.status_history,
		case
			when abs(extract(epoch from (ish.status_time - g))/60)::int = min(abs(extract(epoch from (ish.status_time - g))/60)::int) over (partition by ish.id, status_time)
			then status_time
			else c.g::timestamp
		end as status_time,
		aluguel,
		tipo_porteiro,
		c.g as contract_time,
		c.id as contract_id,
		c.dt_end,
		abs(extract(epoch from (ish.status_time - g))/60)::int diff,
		abs(extract(epoch from (ish.status_time - g))/60)::int = min(abs(extract(epoch from (ish.status_time - g))/60)::int) over (partition by ish.id, c.id) as closest,
		abs(extract(epoch from (ish.status_time - g))/60)::int = min(abs(extract(epoch from (ish.status_time - g))/60)::int) over (partition by ish.id, status_time) as true_line
	from aux_ish ish
	join contract_dates c
	  on ish.id = c.imovel_id
	where ish.status_history = 'alugado' and ish.truncatable is false
),
ish_rent as (
	select
		id,
		status_time,
		status_history,
		aluguel,
		tipo_porteiro,
		truncatable
	from aux_ish
	union all
	select
		id,
		contract_time,
		status_history,
		aluguel,
		tipo_porteiro,
		false as truncatable
	from rent where closest = true and true_line = false
),
ish as (
  select
		status_history as status,
    status_time,
    id,
    aluguel,
		tipo_porteiro,
    row_number() over (partition by id order by status_time) as rn,
    row_number() over (partition by id, status_history order by status_time) as rn_status
  from ish_rent
  where truncatable is false
  order by status_time asc
),
check_status as (
  select
    ds.*,
    case
    	when ds.status = 'despublicado' and lag(ds.status) over w = 'alugado'	and lag(r.id) over w is not null
    	or ds.status = 'suspenso' and lag(ds.status) over w = 'alugado'	and lag(r.id) over w is not null
    	then lag(r.contract_id) over w
    	else r.contract_id
    end as contract_id,
    case
    	when ds.status = 'despublicado' and lag(ds.status) over w = 'alugado'	and lag(r.id) over w is not null
    	or ds.status = 'suspenso' and lag(ds.status) over w = 'alugado'	and lag(r.id) over w is not null
    	then lag(r.dt_end) over w
    	else r.dt_end
    end as contract_end,
    ds.status = 'publicado' and rn_status = 1 as start_first_pub,
    ds.status = 'publicado' and lag(ds.status) over w = 'alugado'	and lag(r.id) over w is not null as start_pub_after_rent,
    ds.status = 'publicado' and (lag(ds.status) over w = 'despublicado' and ds.status_time - lag(ds.status_time) over w >= interval '90 days') as start_after_depub_90,
    (ds.status = 'publicado' and (lag(ds.status) over w = 'despublicado' and lag(ds.status, 2) over w = 'alugado' and lag(r.id,2) over w is not null)) or
    (ds.status = 'publicado' and (lag(ds.status) over w = 'suspenso' and lag(ds.status, 2) over w = 'alugado' and lag(r.id,2) over w is not null)) as start_after_depub_rent,
    (ds.status = 'alugado' and r.id is not null and lead(ds.status) over w = 'publicado') end_pub_after_rent,
    ds.status = 'despublicado' and (lead(ds.status) over w = 'publicado' and lead(ds.status_time) over w - ds.status_time >= interval '90 days') as end_depub_90,
    (ds.status = 'despublicado' and lag(ds.status) over w = 'alugado'	and lag(r.id) over w is not null and lead(ds.status) over w = 'publicado') or
    (ds.status = 'suspenso' and lag(ds.status) over w = 'alugado'	and lag(r.id) over w is not null and lead(ds.status) over w = 'publicado') as end_depub_rent,
    (ds.rn = max(ds.rn) over (partition by ds.id)) as end_last_status
  from ish ds
  left join rent r
   on ds.id = r.id
    and ds.status_time = r.status_time
    and closest = true
  window w as (partition by ds.id order by ds.status_time)
),
aux_times as (
  select distinct
    id,
    status,
    status_time,
    aluguel,
		tipo_porteiro,
    contract_id,
    contract_end,
    extract(day from status_time - lag(contract_end) over w) > 90 as recovered_after_rent,
    case
    	when (end_pub_after_rent or end_depub_rent) then 1
    	when (status = 'alugado' and end_last_status) then 1
    	when (status = 'despublicado' and end_last_status and contract_id is not null) then 1
    	else 0
  	end as rent,
		case
			when (start_first_pub and end_last_status) then status_time -- if its the only status
			when (start_first_pub) then status_time -- if its the first status
			when ( -- if its the last status and the previous one is also a End-status
				(end_last_status and
				lag((end_pub_after_rent or end_depub_90 or end_depub_rent or end_last_status)) over w)
				) then status_time
			else lag(status_time) over w -- otherwise just look  to the previous
		end as min_version_time,
		case
			when end_last_status then null
			else lead(status_time) over w
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
		end_last_status,
    (end_pub_after_rent or end_depub_90 or end_depub_rent or end_last_status) as _end
  from check_status
  where start_first_pub
  	or start_pub_after_rent
  	or start_after_depub_90
  	or start_after_depub_rent
  	or end_pub_after_rent
  	or end_depub_90
  	or end_depub_rent
  	or end_last_status
	window w as (partition by id order by status_time)
),
times as (
	select
		id,
		status,
		status_time,
		aluguel,
		tipo_porteiro,
		min_version_time,
		max_version_time,
		min(status_time) over w as first_publication_date,
		sum(rent) over (partition by id order by status_time rows unbounded preceding) as nr_renting,
		case
			when lag(recovered_after_rent) over (partition by id order by status_time) then 'Recovered'
			when recovered_after_rent and end_last_status then 'Recovered'
			else start_version_category
		end as start_version_category,
		end_version_category,
		is_last_version,
		contract_id,
		_end
	from aux_times
	window w as (partition by id order by status_time)
	order by status_time
)
select
  id,
  status,
  aluguel,
  tipo_porteiro,
  rank() over (partition by id order by status_time) as version,
  min_version_time,
  max_version_time,
  nr_renting,
  first_publication_date,
  case
  	when status = 'despublicado' and coalesce(end_version_category <> 'Rented', true) then status_time
  	else null
  end as depublished_date,
  start_version_category,
  end_version_category,
  contract_id,
  is_last_version
from times
where _end is true
;
