drop view if exists vw_stranded_house_listings;
create or replace view vw_stranded_house_listings as
with
status_all as (
--select all status from each listing, calculate date_to_be_stranded using publication_date and find in which status was the stranded date
select
	fhs.id_house_listing as sk_house,
    fhs.status_history,
    coalesce(to_char(fhs.ts_status_start::date, 'YYYYMMDD')::integer, -1::integer) as sk_status_start_date,
    dmin.date as min_status_date,
    coalesce(to_char(fhs.ts_status_end::date, 'YYYYMMDD')::integer, -1::integer) as sk_status_end_date,
    dmax.date as max_status_date,
    date_trunc('day',hl.ts_listing_version_start) as ts_publication,
    date_trunc('day',hl.ts_listing_version_start)::timestamp::date + interval '8 week' as date_to_be_stranded,
    case when date_trunc('day',hl.ts_listing_version_start) + interval '8 week' <= dmin.date
          or date_trunc('day',hl.ts_listing_version_start) + interval '8 week' <= dmax.date
      then 'stranded' end as type_stranded
from house_listing_status fhs
left join house_listing hl
  on fhs.id_house_listing = hl.id_house_listing
left join dim_date dmin
  on dmin."date" = fhs.ts_status_start::date
left join dim_date dmax
  on dmax."date" = coalesce(fhs.ts_status_end::date, current_date -1)
order by fhs.id_house_listing desc, fhs.ts_status_start
),
rank_stranded as (
--select only status where stranded date already happened
select
	sk_house,
    status_history,
    min_status_date,
    max_status_date,
    ts_publication,
    date_to_be_stranded,
    type_stranded,
    rank() over (partition by sk_house, type_stranded order by max_status_date) as rk,
    --calculate min date of all status, because if it is a valid status that is the date that will be used
    min(case when type_stranded = 'stranded' then min_status_date end) over (partition by sk_house) as min_date_all_status,
    --calculate min date of valid status to define stranded
    min(case when type_stranded = 'stranded'
                  and status_history in ('publicado','suspenso','edicao','aguardando_publicacao')
             then min_status_date end) over (partition by sk_house) as min_date_valid_status,
    min(case when type_stranded = 'stranded' then date_to_be_stranded end) over (partition by sk_house) as min_date_to_be_stranded
from status_all
where type_stranded is not null
order by sk_house desc, min_status_date
),
stranded_status as (
select
	*,
	case when rk = 1 and status_history = 'alugado' then NULL
	     when rk = 1 and status_history in ('despublicado','excluido')
	       then min(min_date_valid_status) over (partition by sk_house)
	     when rk = 1 and status_history in ('publicado','suspenso','edicao','aguardando_publicacao')
	       then min(min_date_valid_status) over (partition by sk_house)
	     end as min_date_stranded
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
order by sk_house desc
)
select
	distinct sk_house,
	case when greatest(coalesce(min_date_stranded,'3000-01-01'), min_date_to_be_stranded) = '3000-01-01' then NULL
	else greatest(coalesce(min_date_stranded,'3000-01-01'), min_date_to_be_stranded)::timestamp::date end as stranded_date
from stranded_status
where rk = 1
;