--drop view if exists vw_stranded_house_listings;
--create or replace view vw_stranded_house_listings as
with
status_all as (
--select all status from each listing, calculate date_to_be_stranded using publication_date and find in which status was the stranded date
select
	fhs.id_house_listing as sk_house_listing,
    fhs.status_history,
    fhs.ts_status_start,
    coalesce(fhs.ts_status_end, (current_timestamp - interval '1 day')::timestamp) as ts_status_end,
    hl.ts_listing_version_start,
    hl.ts_listing_version_start + interval '8 week' as ts_to_be_stranded,
    case when hl.ts_listing_version_start + interval '8 week' <= fhs.ts_status_start
          or hl.ts_listing_version_start + interval '8 week' <= coalesce(fhs.ts_status_end, (current_timestamp - interval '1 day')::timestamp)
      then 'stranded' end as type_stranded,
    lag(fhs.status_history) over(partition by fhs.id_house_listing order by fhs.ts_status_start, coalesce(fhs.ts_status_end, (current_timestamp - interval '1 day')::timestamp)) as previous_status_history
from house_listing_status fhs
left join house_listing hl
  on fhs.id_house_listing = hl.id_house_listing
order by fhs.id_house_listing desc, fhs.ts_status_start
),
rank_stranded as (
--select only status where stranded date already happened
select
	  sk_house_listing,
    status_history,
		previous_status_history,
    ts_status_start,
    ts_status_end,
    ts_listing_version_start,
    ts_to_be_stranded,
    type_stranded,
    row_number() over (partition by sk_house_listing, type_stranded order by ts_status_start) as rn,
    --calculate min date of all status, because if it is a valid status that is the date that will be used
    min(case when type_stranded = 'stranded' then ts_status_start end) over (partition by sk_house_listing) as min_ts_all_status,
    --calculate min date of valid status to define stranded
    min(case when type_stranded = 'stranded'
                  and status_history in ('publicado','suspenso','edicao','aguardando_publicacao')
						      and (previous_status_history <> 'alugado' OR previous_status_history is null)
             then ts_status_start end) over (partition by sk_house_listing) as min_ts_valid_status,
    min(case when type_stranded = 'stranded' then ts_to_be_stranded end) over (partition by sk_house_listing) as min_ts_to_be_stranded
from status_all
where type_stranded is not null
order by sk_house_listing desc, ts_status_start
),
stranded_status as (
select
	*,
	case when rn = 1 and status_history = 'alugado' then NULL
	     when rn = 1 and status_history in ('despublicado','excluido')
	       then min(min_ts_valid_status) over (partition by sk_house_listing)
	     when rn = 1 and status_history in ('publicado','suspenso','edicao','aguardando_publicacao')
	       then min(min_ts_valid_status) over (partition by sk_house_listing)
	     end as min_ts_stranded
	    /*
		 * case needed in order to ignore cases where stranded date happened on not valid status
		 * (such as 'alugado', 'despublicado', 'excluido'), but if it was 'despublicado' consider next valid status
		 * example 0:
		 *  -----------------------------------------------------------------------------------------------------------------
		 *  |listing | min_status_date | max_status_date | status    | ts_publication | date_to_be_stranded | stranded_date |
		 *  | 001    |   2018-12-06    |  2018-12-13     | publicado |  2018-12-06    |  2019-01-31         | NULL          |
		 *  | 001    |   2018-12-13    |  2018-12-14     | suspenso  |  2018-12-06    |  2019-01-31         | NULL          |
 		 *  | 001    |   2018-12-14    |  2019-03-19     | alugado   |  2018-12-06    |  2019-01-31         | NULL          |
 		 *  -----------------------------------------------------------------------------------------------------------------
 		 *
		 * 	example 1:
		 *  --------------------------------------------------------------------------------------------------------------------
		 *  |listing | min_status_date | max_status_date | status       | ts_publication | date_to_be_stranded | stranded_date |
		 *  | 002    |   2018-12-05    |  2019-02-12     | publicado    |  2018-12-05    |  2019-01-30         | 2019-01-31    |
		 *  | 002    |   2019-02-12    |  2019-02-19     | suspenso     |  2018-12-05    |  2019-01-30         | 2019-01-31    |
		 *  | 002    |   2019-02-19    |  2019-03-14     | publicado    |  2018-12-05    |  2019-01-30         | 2019-01-31    |
 		 *  | 002    |   2019-03-14    |  2019-03-19     | despublicado |  2018-12-05    |  2019-01-30         | 2019-01-31    |
 		 *  --------------------------------------------------------------------------------------------------------------------
 		 *
 		 * 	example 2:
		 *  --------------------------------------------------------------------------------------------------------------------
		 *  |listing | min_status_date | max_status_date | status       | ts_publication | date_to_be_stranded | stranded_date |
		 *  | 003    |   2018-12-06    |  2018-12-07     | publicado    |  2018-12-06    |  2019-01-31         | 2019-02-11    |
		 *  | 003    |   2018-12-07    |  2019-02-11     | despublicado |  2018-12-06    |  2019-01-31         | 2019-02-11    |
		 *  | 003    |   2019-02-11    |  2019-03-07     | publicado    |  2018-12-06    |  2019-01-31         | 2019-02-11    |
 		 *  | 003    |   2019-03-07    |  2019-03-19     | despublicado |  2018-12-06    |  2019-01-31         | 2019-02-11    |
 		 *  --------------------------------------------------------------------------------------------------------------------
 	     */
from rank_stranded
order by sk_house_listing desc
)
select
	distinct sk_house_listing,
	case when greatest(coalesce(min_ts_stranded,'3000-01-01'), min_ts_to_be_stranded) = '3000-01-01' then NULL
	else greatest(coalesce(min_ts_stranded,'3000-01-01'), min_ts_to_be_stranded)::timestamp::date end as stranded_date
from stranded_status
where rn = 1
;