with
imovel_aud as (
--------------------------------------------------------------------------------------------------------
-- Bring to IMOVEL_AUD datetime for each revision made 	        				    				  --
-- Also creates previous_status column so we can identify status changes		    				  --
-- (status_MOD = 1 may not work sometimes)  	        				            				  --
-------------------------------------------------------------------------------------------------------- 
	select 
		from_unixtime(cast(rev.timestamp as bigint)/1000) as status_time, -- datetime status started
		cast(from_unixtime(cast(rev.timestamp as bigint)/1000) as date) as status_date, -- date status started
		rev.usuario_id, -- user responsible to change status
		rev.motivo, -- reason status changed
		lag(i.status) over(partition by i.id order by i.rev) as previous_status, -- previous status ordered by the datetime that happened
		-- since there's manual updates in the Imovel table that mismatches the last value of Imovel_AUD, we need to consider the current region value.
		im.regiao_id as id_region,
		-- all information from Imovel table
		i.id,
		i.rev,
		i.status,
		i.status_mod,
		i.firstPublication
    from datalake_ebdb_raw_prod.imovel_aud i
    join datalake_ebdb_raw_prod.imovel im
      on i.id = im.id
	inner join datalake_ebdb_raw_prod.usuariorevisionentity rev 
	  on rev.id = i.rev  
--    order by i.id, i.rev
),
house_status_history as (
--------------------------------------------------------------------------------------------------------
-- Create status_history: for each house show all status changes, with start and end of each status   --
--------------------------------------------------------------------------------------------------------
select 
	id as id_house,
	id_region,
	rev, 
	status_mod,
	max(from_iso8601_timestamp(firstpublication)) over(partition by id) as ts_first_publication,
	status_time as ts_status_changed,
	status as status_history,
	lead(status_time) over(partition by id order by rev) as next_status_change_time,
	-- last_value(status) over(partition by id rows between unbounded preceding and unbounded following) as current_status,
	row_number() over(partition by id order by rev) as order_status,
	motivo as reason
from imovel_aud 
where (status <> previous_status or previous_status is null)
--order by id, rev
),
house_new_status_new_date as (
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Create column to identify how long the house is in the status unpublished                          																   --
-- We will use this column to check if a new version will be created to this house (a new version will be created when the house is unpublished for 12 weeks or more)  --  	        		
-- Since we will count from the day it turns 12 weeks, there's no need to extract 1 day from the end_date in date_diff                                                 --
-- Since we are using date_diff, we are considering the whole part of the number, so if the difference is 83.7, it won't consider as recovered                         --
-- For the older houses there are cases of status_history blank, so we have to input status_history = 'publicado' (this happens to status from 2015)                   --
-- In these cases of status_history_blank we also update the status changed date to the first_publication_date                                                         --
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
select 
	*, 
	case when status_history = 'despublicado' then date_diff('day',ts_status_changed,coalesce(next_status_change_time,now())) end as days_unpublished,
	case when status_history is null then 'publicado' else status_history end as new_status_history,
    case when status_history is null then ts_first_publication else ts_status_changed end as new_ts_status_changed,
    max(order_status) over(partition by id_house) as max_order_status
from house_status_history
--order by id_house, rev
),
house_status_version_changes as (
--------------------------------------------------------------------------------------------------------
-- Create column to identify moments where house changed status would create a new version/listing    --
-- The moments are: when there is a status rented or a status unpublished with days_unpublished >= 84 --
-- With a cumulative sum we can identify when a new change of status happens                          --
--------------------------------------------------------------------------------------------------------
select
	*,
	--mr_status.current_status,
	case when new_status_history = 'alugado' or 
	          (new_status_history = 'despublicado' and days_unpublished >= 84) then 1 
         else 0 end as events_change_version,
	case when new_status_history = 'alugado' or 
	          (new_status_history = 'despublicado' and days_unpublished >= 84) then new_status_history 
	     end as events_change_status,          
	sum(case when new_status_history = 'alugado' or 
	              (new_status_history = 'despublicado' and days_unpublished >= 84) then 1 
             else 0 end) over (partition by id_house order by rev rows unbounded preceding) as sum_events_change_version
from house_new_status_new_date h_new
--order by id_house, rev
),
house_status_version_first_publi as (
------------------------------------------------------------------------------------------------------------------------------------
-- Although a rented status is a trigger to a new version, the new version will only starts when there is a new published status  --
-- The rented status will still be a part of previous status and the new published status will be the start of the new version    --
------------------------------------------------------------------------------------------------------------------------------------
select
	*,
	min(case when new_status_history = 'publicado' then new_ts_status_changed 
	         end) over(partition by id_house, sum_events_change_version order by rev) as first_publication_change_version
from house_status_version_changes
--order by id_house, rev
),
house_status_version_publications as (
------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- The rented status will still be a part of previous status, and so will be all status different from published after rental                                   --
-- All versions begin with a date from published status, without a published status there will not be a version_start_date                                      --
------------------------------------------------------------------------------------------------------------------------------------------------------------------
select
	*,
	max(first_publication_change_version) over (partition by id_house order by rev rows unbounded preceding) as publication_version_date
from house_status_version_first_publi
--order by id_house, rev
),
house_status_version_order as (
--------------------------------------------------------------------------------------------------------
-- Define order version based on publication dates							                          --
--------------------------------------------------------------------------------------------------------
select
	*,
	case when publication_version_date is null then 0 else dense_rank() over(partition by id_house order by publication_version_date) end as order_version
from house_status_version_publications
--order by id_house, rev
)--,
select 
	cast(cast(id_house as varchar)||'00'||cast(order_version as varchar) as bigint) as id_house_listing,
	id_region,
	new_status_history as status_history,
	regexp_replace(reason, '\n', '') as status_change_reason,
	ts_first_publication,
	cast(new_ts_status_changed as timestamp) as ts_status_start,
	next_status_change_time as ts_status_end
from house_status_version_order
;
