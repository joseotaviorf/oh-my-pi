drop view if exists vw_property_listing;

create view vw_property_listing as
with ish as
(
  select
	status_history,
    status_time,
    id,
    row_number() over (partition by id order by status_time) as rn,
    row_number() over (partition by id, status_history order by status_time) as rn_status
  from
	imovel_status_history
  where
    status_history in ('alugado', 'publicado')
)
,diff_status as
(
  select
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
)
,check_status as
(
  select
    *,
    status = 'alugado'
      and next_different_status_time is not null
      and next_different_status_time - status_time >= INTERVAL '90 days'
    as new_version_alugado,

    status = 'publicado'
      and next_different_status is null
      and next_status_time is not null
      and next_status_time - status_time >= INTERVAL '14 days'
    as new_version_publicado

  from
    diff_status
)
,times as
(
  select distinct
  	id,
    status,
    row_number() over w as rn,
    lag(status_time) over w as min_version_time,
    max(status_time) over w as max_version_time
  from
    check_status
  where
    (new_version_alugado or new_version_publicado)
  window
  	w as (partition by id order by status_time)  
)
,history_times as
(
  select
    i.id,
    i.status_history,
    i.status_time,
    t.min_version_time,
    t.max_version_time,
    case
      when t.min_version_time is null and t.max_version_time is null then NULL
      when (i.status_time > t.min_version_time or t.min_version_time is null) then t.rn
      else t.rn + 1
    end as version
  from
    imovel_status_history i
  left join
    times t
    on t.id = i.id
    and (i.status_time > t.min_version_time or t.min_version_time is null)
    and (i.status_time <= t.max_version_time or t.max_version_time is null)
),
result_version as
(
  select
  	id,
    status_history,
    status_time,
    min_version_time,
    max_version_time,
    coalesce(
      version,
      coalesce(max(version) over (partition by id order by status_time),0) + 1
    ) as version
  from
  	history_times
),
prev_listing as
(
  select
    id,
    status_history,
    status_time,
    case
      when version = 1 then NULL
      else
        coalesce(
          min_version_time,
          max(max_version_time) over (partition by id order by status_time) -- get the max of previous version
        )
    end  as min_version_time,
    max_version_time,
    version,
    row_number() over (partition by id, version order by status_time desc) as rn,
    min(status_time) 
    	filter (where status_history in ('publicado', 'alugado')) 
    	over (partition by id, version order by status_time) as publication_date
  from
    result_version
)
-- select * from prev_listing where id = 892779727
,last_version as
(
	select distinct
	  id,
	  version,
	  min_version_time,
	  max_version_time,
	  publication_date,
	  last_value(status_history) 
	  	over (
	  		partition by id, version
	  		order by status_time
	  		RANGE BETWEEN current row AND unbounded following
	  	) as last_status_version
	from
	  prev_listing
	-- where rn = 1
)
,prev as
(
	select	
		*,
		lag(last_status_version) over (partition by id order by version) prev_status	
	from
		last_version	
	where 
		publication_date is not null 
),
rent as
(
	select
		id,
		version,
		min_version_time,
		max_version_time,
		last_status_version,
		coalesce(publication_date, max_version_time) as publication_date,
		case coalesce(prev_status, 'alugado') when 'alugado' then 1 else 0 end as prev_rented,
		case coalesce(last_status_version, 'alugado') when 'alugado' then 1 else 0 end as rented
	from
		prev
	
),
relisting as
(
	select distinct
		*,
		sum(prev_rented) over (partition by id order by version) as nr_listing,
		sum(rented) over (partition by id order by version) as nr_renting
	from
		rent
)
select
	id,
	version,
	min_version_time,
	max_version_time,
	last_status_version,
	nr_listing,
	nr_renting,
	min(publication_date) over (partition by id,nr_listing order by version) as publication_date -- considering nr_relisting rule instead of version!
from
	relisting
-- where
	--  id = 892763624
  --  id = 892779727 -- 892797518 -- 892798596 -- 892779727
	--  id in(892797518, 892798596, 892779727)
order by
  id,
  version
  
  
