drop view if exists vw_fact_house_status;
create or replace view vw_fact_house_status as
with distinct_status as (
	-- select different house statuses with their status and next status dates
	select distinct
		id,
		status_history,
		status_time::date as dt_min_status,
		next_status_date as dt_max_status
	from imovel_status_full_history
	where status_time::date != next_status_date
		or status_time::date is null
		or next_status_date is null
),
min_max_prev as (
	-- consolidate house status in a range (min and max)
	select distinct
	  row_number() over (partition by id order by dt_min_status) as rn,
		id,
		status_history,
		dt_min_status,
		/*
		 * case needed for the same status occurring twice in a row, but with the max date of row 'n' = min date of row 'n+1'
		 * example:
		 *  --------------------------------------------------------------------
		 * 	|rn | min_status_date |          max_status_date       | status    |
		 *  | 0 |   2018-05-01    |  2018-06-01   ->   2018-07-01  | publicado |
		 *  | 1 |   2018-06-01    |           2018-07-01           | publicado | ## later this row can be removed by the flag 'valid'
		 *  --------------------------------------------------------------------
		 */
		case
			when dt_max_status = lead(dt_min_status) over (partition by id order by dt_min_status)
						and status_history = lead(status_history) over (partition by id order by dt_min_status)
				then lead(dt_max_status) over (partition by id order by dt_min_status)
			else dt_max_status
		end as dt_max_status,
		/*
		 * coalesce needed for invalidating current rows with previous ones with the same status and min_status_date = max_status_date
		 * in that case, the first row will already contain the wider range of the status date
		 * example:
		 *  -------------------------------------------------------------
		 * 	|rn | min_status_date | max_status_date | status    | valid |
	   *  | 0 |   2018-05-01    |  2018-06-01     | publicado | true  |
	   *  | 1 |   2018-06-01    |  2018-07-01     | publicado | false |
		 *  -------------------------------------------------------------
		 */
		coalesce(not(dt_min_status = lag(dt_max_status) over (partition by id order by dt_min_status)
					and status_history = lag(status_history) over (partition by id order by dt_min_status)), true) as valid
	from distinct_status
),
min_max as (
  -- finished validating remaining unvalid rows that are still status-active for the house
	select
		rn,
		id,
		status_history,
		dt_min_status,
		dt_max_status,
		/*
		 * case need then the last row with no max_status_date (active row) doesn't has the valid flag set to 'true'
		 * 	and when there are two equal statuses with the same (or greater) max_status_date
		 * example 0:
		 *  -----------------------------------------------------------------------------
		 *  |rn | min_status_date | max_status_date | status    |           valid       |
		 *  | 0 |   2018-05-01    |  2018-06-01     | publicado |           true        |
		 *  | 1 |   2018-05-12    |  2018-07-18     | suspenso  |           true        |
 		 *  | 2 |   2018-06-01    |     null        | publicado | when(false)  ->  true |
 		 *  -----------------------------------------------------------------------------
 		 *
		 * 	example 1:
		 *  -----------------------------------------------------------------------------
		 *  |rn | min_status_date | max_status_date | status    |           valid       |
		 *  | 0 |   2018-05-01    |  2018-06-01     | publicado |           true        |
		 *  | 1 |   2018-05-12    |  2018-06-01     | publicado | when(true)  ->  false |
 		 *  | 2 |   2018-06-01    |     null        | suspenso  |           true        |
 		 *  -----------------------------------------------------------------------------
 		 *
 		 * 	example 2:
		 *  ---------------------------------------------------------------------------------
		 *  |rn | min_status_date | max_status_date | status        |           valid       |
		 *  | 0 |   2018-05-15    |  2018-07-02     | publicado     |           true        |
		 *  | 1 |   2018-05-17    |  2018-07-02     | publicado     |           false       |
 		 *  | 2 |   2018-07-02    |     null        | despublicado  | when(false)  ->  true |
 		 *  ---------------------------------------------------------------------------------
 		 *
 		 * 	example 3:
		 *  -----------------------------------------------------------------------------
		 *  |rn | min_status_date | max_status_date | status    |           valid       |
		 *  | 0 |   2018-01-26    |  2018-09-29     | publicado |           true        |
		 *  | 1 |   2018-09-25    |     null        | publicado | when(true)  ->  false |
 		 *  | 2 |   2018-09-29    |     null        | publicado |           true        |
 		 *  -----------------------------------------------------------------------------
 		 *
		 */
		case
			when dt_max_status is null
				then coalesce(dt_min_status >= lag(dt_max_status) over (partition by id order by dt_min_status), true)
			when status_history = lag(status_history) over (partition by id order by dt_min_status)
					and dt_max_status = lag(dt_max_status) over (partition by id order by dt_min_status)
				then false
			else coalesce(valid, true)
		end as valid
	from min_max_prev
),
_result as (
  -- joining status result with the house dimension to get the sk through min_version_time and max_version_time
	select
	  -- if no house is found in the dimension table, the sk gets concatenated with '000' so there will always be a "valid" integer sk
		coalesce(sdp.sk_house_listing, rpad(mm.id::varchar, 12, case when mm.status_history = 'publicado' then '001' else '0' end)::bigint) as sk_house_listing,
		coalesce(vfhl.sk_region, -1) as sk_region,
		-- there are some cases where the house history says, for example, status = 'despublicado', but the house dimension/ebdb says the house is in another status
		case
			when mm.dt_max_status is null
				then coalesce(sdp.status, mm.status_history)
			else mm.status_history
		end as status_history,
		to_char(mm.dt_min_status, 'YYYYMMDD')::integer as sk_min_status_date,
		to_char(mm.dt_max_status, 'YYYYMMDD')::integer as sk_max_status_date
	from min_max mm
	left join staging.dim_house_listing sdp
		on sdp.id_house = mm.id
			and mm.dt_min_status >= sdp.ts_listing_version_start::date
			and coalesce(mm.dt_max_status, now()) <= coalesce(sdp.ts_listing_version_end::date, now())
    join vw_fact_house_listings vfhl
        on vfhl.sk_house_listing = sdp.sk_house_listing
	where mm.valid is true
)
select
	sk_house_listing,
	sk_region,
	status_history,
	/*
	 * because the same version can have multiple status dates for the same status, for counts and cohorts the min_status_date for each version must be calculated
	 * example 0:
   * ---------------------------------------------------------------------------------------
	 * 	| min_status_date | max_status_date | status    |   sk   |  min_version_status_date  |
	 * 	|   2018-05-01    |  2018-06-01     | publicado | 123001 |       2018-05-01          |
	 *  |   2018-06-01    |  2018-07-18     | publicado | 123001 |       2018-05-01          |
	 *  |   2018-07-18    |     null        | publicado | 123001 |       2018-05-01          |
	 * ---------------------------------------------------------------------------------------
	 *
 	 * example 1:
	 * ---------------------------------------------------------------------------------------
	 *  | min_status_date | max_status_date | status    |   sk   |  min_version_status_date  |
	 *  |   2018-05-01    |  2018-06-01     | publicado | 123001 |       2018-05-01          |
	 *  |   2018-06-01    |  2018-07-18     | suspenso  | 123001 |       2018-06-01          |
	 *  |   2018-07-18    |     null        | publicado | 123001 |       2018-05-01          |
	 * ---------------------------------------------------------------------------------------
	 *
 	 * example 2:
	 * ---------------------------------------------------------------------------------------
	 * 	| min_status_date | max_status_date | status    |   sk   |  min_version_status_date  |
	 * 	|   2018-05-01    |  2018-06-01     | publicado | 123001 |       2018-05-01          |
	 * 	|   2018-06-01    |  2018-07-18     | suspenso  | 123001 |       2018-06-01          |
	 *  |   2018-07-18    |     null        | publicado | 123002 |       2018-07-18          |
	 * ---------------------------------------------------------------------------------------
	 */
	min(sk_min_status_date) over (partition by sk_house_listing, status_history order by sk_min_status_date) as sk_min_version_status_date,
	sk_min_status_date,
	sk_max_status_date,
	now() as dt_timestamp
from _result
;