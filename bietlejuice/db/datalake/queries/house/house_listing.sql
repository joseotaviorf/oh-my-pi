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
	  i.* -- all information from Imovel table
    from datalake_ebdb_raw_prod.imovel_aud i
	inner join datalake_ebdb_raw_prod.usuariorevisionentity rev
	  on rev.id = i.rev
    order by i.id, i.rev
),
house_status_history as (
--------------------------------------------------------------------------------------------------------
-- Create status_history: for each house show all status changes, with start and end of each status   --
--------------------------------------------------------------------------------------------------------
select
	id as id_house,
	rev,
	status_mod,
	max(from_iso8601_timestamp(firstpublication)) over(partition by id) as ts_first_publication,
	status_time as ts_status_changed,
	status as status_history,
	lead(status_time) over(partition by id order by rev) as next_status_change_time,
	-- last_value(status) over(partition by id rows between unbounded preceding and unbounded following) as current_status,
	row_number() over(partition by id order by rev) as order_status
from imovel_aud
where (status <> previous_status or previous_status is null)
order by id, rev
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
order by id_house, rev
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
order by id_house, rev
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
order by id_house, rev
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
order by id_house, rev
),
house_status_version_order as (
--------------------------------------------------------------------------------------------------------
-- Define order version based on publication dates							                          --
--------------------------------------------------------------------------------------------------------
select
	*,
	case when publication_version_date is null then 0 else dense_rank() over(partition by id_house order by publication_version_date) end as order_version
from house_status_version_publications
order by id_house, rev
),
house_status_version_last_status as (
--------------------------------------------------------------------------------------------------------
-- Identify the last status to each version                                                           --
--------------------------------------------------------------------------------------------------------
	with
	max_status_order as (
		select
			id_house,
			order_version,
			max(order_status) as max_order_status
		from house_status_version_order
		group by id_house, order_version
	)
	select
	   hs_vo.*,
	   case when ms_o.max_order_status is not null then hs_vo.new_status_history end as last_status
    from house_status_version_order hs_vo
    left join max_status_order ms_o
      on hs_vo.id_house = ms_o.id_house
      and hs_vo.order_version = ms_o.order_version
      and hs_vo.order_status = ms_o.max_order_status
),
status_change_version as (
--------------------------------------------------------------------------------------------------------
-- Identify the status that made it changes to a new version                                          --
-- This status is important to define which category the listing will have                            --
--------------------------------------------------------------------------------------------------------
select
	id_house,
	order_version,
	max(events_change_status) as category_change
from house_status_version_last_status
where events_change_status is not null
group by 1, 2
),
house_listing_plain as (
--------------------------------------------------------------------------------------------------------
-- Create listings column according to version                                                        --
-- Create column to identify category (using column from join with status_change_version              --
-- Keep only the version changes                                                                      --
--------------------------------------------------------------------------------------------------------
select
	hs_v.id_house,
	hs_v.order_version as version,
	sc_v.category_change as change_version_status,
	max(hs_v.last_status) as status,
	min(cast(hs_v.publication_version_date as timestamp)) as ts_listing_version_start,
	max(coalesce(hs_v.next_status_change_time,cast('2200-01-01 12:00:00' as timestamp))) as ts_listing_version_end
from house_status_version_last_status hs_v
left join status_change_version sc_v
  on hs_v.id_house = sc_v.id_house
  and hs_v.order_version = sc_v.order_version
group by 1, 2, 3
order by hs_v.id_house, hs_v.order_version
),
house_listing_full as (
--------------------------------------------------------------------------------------------------------
-- Create category                                                                                    --
--------------------------------------------------------------------------------------------------------
select
	cast(cast(id_house as varchar)||'00'||cast(version as varchar) as bigint) as sk_house_listing,
	id_house,
	version,
	case when version = 0 then NULL
	     when version = 1 then 'First Listing'
	     when version <> 0 and lag(change_version_status) over(partition by id_house order by version) = 'alugado' then 'Re-Listing'
	     when version <> 0 and lag(change_version_status) over(partition by id_house order by version) in ('despublicado') then 'Recovered'
	     else NULL end as listing_category_start,
	status,
	ts_listing_version_start,
	nullif(cast(ts_listing_version_end as timestamp),cast('2200-01-01 12:00:00' as timestamp)) as ts_listing_version_end
from house_listing_plain
),
special_conditions as (
--------------------------------------------------------------------------------------------------------
-- Include flags of special condition (exclusivity and originals)                                     --
--------------------------------------------------------------------------------------------------------
  with special_conditions_prev as (
  -- filter multiple changes in a single day
  -- example:
  -- ----------------------------------------------------------------------------------------------------------------------------------
  -- |     id      |  special_condition_type  |       ts_opted_in      |       ts_opted_out      |    special_condition_status_mod    |
  -- ----------------------------------------------------------------------------------------------------------------------------------
  -- |    33713	   |       Exclusivity	      |   2019-04-24 21:01:08	 |           null          |                1 (opt-in)          | -> will be removed
  -- |    33713	   |       Exclusivity	      |   2019-04-24 21:01:08	 |    2019-04-24 21:01:10  |                1 (opt-out)         | -> will be removed
  -- |    33713	   |       Exclusivity	      |   2019-04-24 21:05:17	 |           null          |                1 (opt-in)          | -> will be removed
  -- |    33713	   |       Exclusivity	      |   2019-04-24 21:05:17	 |    2019-04-24 21:05:35  |                1 (opt-out)         |
  -- ----------------------------------------------------------------------------------------------------------------------------------
    select
      id,
      specialconditiontype,
      date(from_iso8601_timestamp(optedinat)) as in_,
      max(date(from_iso8601_timestamp(optedoutat))) as out_
    from datalake_ebdb_raw_prod.specialcondition_aud
    where specialconditionstatus in ('OptedIn', 'OptedOut')
      and specialconditiontype in ('Exclusivity', 'OriginalsReady', 'OriginalsReno')
      -- TODO: check special_condition_mod = 0 and revType = 1 conditions
      -- to avoid excessive data scan
    group by 1, 2, 3
  )
  select
    hsc.house_id,
    scp.specialconditiontype,
    scp.in_,
    max(scp.out_) as out_
  from datalake_ebdb_raw_prod.housespecialcondition hsc
  join datalake_ebdb_raw_prod.specialcondition sc
    on hsc.specialcondition_id = sc.id
  join special_conditions_prev scp
    on scp.id = sc.id
  group by 1, 2, 3
),
listing_special_conditions as (
-- selecting the last time a listing had its special condition changed on its version
-- example:
-- ----------------------------------------------------------------------------------
-- |  sk_house_listing  |  special_condition_type  |  dt_opted_in  |  dt_opted_out  |
-- ----------------------------------------------------------------------------------
-- |    892812943001    |      OriginalsReady      |   2019-03-04  |   2019-05-12   | -> will be removed
-- |    892812943001    |      OriginalsReady      |   2019-05-13  |      null      |
-- ----------------------------------------------------------------------------------
  select
    hl.sk_house_listing,
    sc.specialconditiontype,
    max(sc.in_) as dt_opted_in,
    max(sc.out_) as dt_opted_out
  from house_listing_full hl
  join special_conditions sc
    on hl.id_house = sc.house_id
      and greatest(sc.in_, date(hl.ts_listing_version_start)) >= date(hl.ts_listing_version_start)
      and greatest(sc.in_, date(hl.ts_listing_version_start)) < coalesce(date(hl.ts_listing_version_end), date(now() - interval '1' day))
      and greatest(coalesce(sc.out_, date(now() - interval '1' day)), coalesce(date(hl.ts_listing_version_end), date((now() - interval '1' day)))) >= coalesce(date(hl.ts_listing_version_end), date(now() - interval '1' day))
      and greatest(coalesce(sc.out_, date(now() - interval '1' day)), coalesce(date(hl.ts_listing_version_end), date((now() - interval '1' day)))) >= date(hl.ts_listing_version_start)
  group by 1, 2
),
listing_special_conditions_dates as (
	with multiple_special_conditions as (
	-- in case a house listing has more than one Special Condition types: exclusivity, ready and reno on the same version
  	  select
  		sk_house_listing,
  		specialconditiontype,
  		dt_opted_in,
  		dt_opted_out,
  		-- selecting the maximum opt-in/out of a house listing, not considering the Originals' type
  		row_number() over (partition by sk_house_listing, case when specialconditiontype like 'Originals%' then 'Originals' else specialconditiontype end order by dt_opted_in desc, coalesce(dt_opted_out, date('2100-01-01')) desc) as rn_last,
  		row_number() over (partition by sk_house_listing, case when specialconditiontype like 'Originals%' then 'Originals' else specialconditiontype end order by dt_opted_in asc, coalesce(dt_opted_out, date('2100-01-01')) asc) as rn_first
  	  from listing_special_conditions
    ),
    last_opt as (
    -- select the latest Special Condition type a house listing has entered
      select
        sk_house_listing,
        specialconditiontype,
        dt_opted_in,
        dt_opted_out
      from multiple_special_conditions
      where rn_last = 1
    ),
    first_opt as (
    -- select the oldest Special Condition type a house listing has entered
      select
        sk_house_listing,
        specialconditiontype,
        dt_opted_in,
        dt_opted_out
      from multiple_special_conditions
      where rn_first = 1
    )
     select
        fo.sk_house_listing,
        lo.specialconditiontype, -- important to select special_condition_type from last_op since we want to show LAST special condition type
        fo.dt_opted_in as dt_first_opted_in,
        fo.dt_opted_out as dt_first_opted_out,
        lo.dt_opted_in as dt_last_opted_in,
        lo.dt_opted_out as dt_last_opted_out
     from last_opt lo
     join first_opt fo
       on lo.sk_house_listing = fo.sk_house_listing
       and (case when lo.specialconditiontype like 'Originals%' then 'Originals' else lo.specialconditiontype end) = (case when fo.specialconditiontype like 'Originals%' then 'Originals' else fo.specialconditiontype end)
)
select
  hl.sk_house_listing,
  hl.id_house,
  hl.version,
  hl.status,
  hl.ts_listing_version_start,
  hl.ts_listing_version_end,
  hl.listing_category_start,
  lsc_exclusivity.dt_first_opted_in is not null as is_exclusive,
  lsc_exclusivity.dt_last_opted_in as dt_last_exclusive_opted_in,
  lsc_exclusivity.dt_last_opted_out as dt_last_exclusive_opted_out,
  lsc_originals.dt_last_opted_in is not null
    and lsc_originals.dt_last_opted_out is null as is_originals_active,
  lsc_originals.specialconditiontype as last_originals_type,
  lsc_originals.dt_last_opted_in as dt_last_originals_opted_in,
  lsc_originals.dt_last_opted_out as dt_last_originals_opted_out,
  cast(now() as timestamp) as ts_load
from house_listing_full hl
left join listing_special_conditions_dates lsc_originals
  on hl.sk_house_listing = lsc_originals.sk_house_listing
    and lsc_originals.specialconditiontype like 'Originals%'
left join listing_special_conditions_dates lsc_exclusivity
  on hl.sk_house_listing = lsc_exclusivity.sk_house_listing
    and lsc_exclusivity.specialconditiontype = 'Exclusivity';