drop view if exists public.vw_property_listing;
create or replace view public.vw_property_listing as
with filt as (
  select
	id,
	status_time,
	status_history,
	row_number() over (partition by id order by status_time) as rn
	from imovel_status_history
	where status_history in ('despublicado', 'publicado', 'alugado')
), not_pub as (
  select
    filt.id,
    'publicado'::varchar(255) as status_history,
    i.first_publication as status_time
  from
    filt
  left join
    imovel i
   on i.id = filt.id
  where filt.rn = 1
    and i.first_publication != filt.status_time
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
  where status_history in ('alugado', 'publicado', 'despublicado')
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
), diff_check_status as (
  select
    *,
    min(dr_status) over (partition by id, status) as min_status
  from
    diff_status
), check_status as (
  select
    ds.*,
    r.id as r_id,
    ds.status = 'alugado'
    and r.id is not null
    as new_version_alugado,

    ds.status = 'alugado'
      and r.id is not null
      and lead(ds.status) over (partition by ds.id) = 'publicado'
    as new_version_pub_rent,

    status = 'publicado'
    and ( (lag(ds.status) over (partition by ds.id) = 'despublicado'
          and ds.status_time - lag(ds.status_time) over (partition by ds.id) >= interval '90 days')
          or
          dr_status = min_status
        )
    as new_version_publicado
  from
    diff_check_status ds
  left join rent r
   on ds.id = r.id
    and ds.status_time = r.status_time
), aux_times as (
  select distinct
    id,
    status,
    case
        when new_version_publicado is true
            then status_time
        when new_version_pub_rent is true
            then next_different_status_time
        else null
    end as min_version_time,
    status_time,
    new_version_alugado,
    new_version_pub_rent,
    new_version_publicado
  from
    check_status
  window
  	w as (partition by id order by status_time)
), times as (
  select distinct
    id,
    status,
    row_number() over w as version,
    min_version_time,
    lead(min_version_time) over w as max_version_time
  from
    aux_times
  where new_version_pub_rent
        or new_version_publicado
  window
  	w as (partition by id order by status_time)
), renting as (
    select
        id,
        version,
        row_number() over (partition by id order by min_version_time asc) as nr_renting
    from times
    where status = 'alugado'
)
select
  t.*,
  coalesce(r.nr_renting, 0) as nr_renting,
  min(t.min_version_time) over (partition by t.id) as first_publication_date
from times t
left join renting r
  on t.id = r.id
     and t.version = r.version
;