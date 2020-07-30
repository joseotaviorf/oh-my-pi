with house_aud as (
    select
      from_unixtime(cast(rev.ts_revision as bigint)/1000) as revision_time, 
      lag(i.status) over(partition by i.id_house order by i.rev) as previous_status, -- previous status ordered by the datetime that happened
      i.status,
      i.id_house,
      i.rev,
      i.dt_first_publication
    from datalake_ebdb_clean.house_aud i
    inner join datalake_ebdb_clean.user_revision_entity rev
      on rev.id = i.rev
    ),
house_status_history as (
select
    id_house,
    rev,
    max(dt_first_publication) over(partition by id_house) as ts_first_publication,
    revision_time as ts_status_changed,
    status as status_history,
    lead(revision_time) over(partition by id_house order by rev) as next_status_change_time,
    row_number() over(partition by id_house order by rev) as order_status
from house_aud
where (status <> previous_status or previous_status is null)
),
house_new_status_new_date as (
select
    id_house,
    rev,
    next_status_change_time,
    order_status,
    case when status_history = 'despublicado' then datediff(coalesce(next_status_change_time,now()),ts_status_changed) end as days_unpublished,
    case when status_history is null then 'publicado' else status_history end as new_status_history,
    case when status_history is null then ts_first_publication else ts_status_changed end as new_ts_status_changed
from house_status_history
),
house_status_version_changes as (
select
    id_house,
    rev,
    new_status_history,
    next_status_change_time,
    new_ts_status_changed,
    order_status,
    case when new_status_history = 'alugado' or
              (new_status_history = 'despublicado' and days_unpublished >= 84) then new_status_history
         end as events_change_status,
    sum(case when new_status_history = 'alugado' or
                  (new_status_history = 'despublicado' and days_unpublished >= 84) then 1
             else 0 end) over (partition by id_house order by rev rows unbounded preceding) as sum_events_change_version
from house_new_status_new_date h_new
),
house_status_version_first_publi as (
select
    id_house,
    rev,
    min(case when new_status_history = 'publicado' then new_ts_status_changed end) over(partition by id_house, sum_events_change_version order by rev) as first_publication_change_version,
    order_status,
    next_status_change_time
from house_status_version_changes
),
house_status_version_publications as (
select
    id_house,
    max(first_publication_change_version) over (partition by id_house order by rev rows unbounded preceding) as publication_version_date,
    order_status,
    next_status_change_time
from house_status_version_first_publi
),
house_status_version_order_null_publi_date as (
--------------------------------------------------------------------------------------------------------
-- Define order version based on null publication dates                                                    --
--------------------------------------------------------------------------------------------------------
    select
        *,
        0 as order_version
    from house_status_version_publications
    where publication_version_date is null
),
house_status_version_order_not_null_publi_date as (
--------------------------------------------------------------------------------------------------------
-- Define order version based on non null publication dates                                                    --
--------------------------------------------------------------------------------------------------------
    select
        *,
        dense_rank() over(partition by id_house order by publication_version_date) as order_version
    from house_status_version_publications
    where publication_version_date is not null
),
house_status_version_order as (
--------------------------------------------------------------------------------------------------------
-- Define order version as union all both above                                                   --
--------------------------------------------------------------------------------------------------------
    select * from house_status_version_order_null_publi_date
    union all
    select * from house_status_version_order_not_null_publi_date
),
max_status_order as (
        select
            id_house,
            order_version,
            max(order_status) as max_order_status
        from house_status_version_order
        group by id_house, order_version
),
house_status_version_last_status as (
    select
       hs_vo.id_house,
       hs_vo.order_version,
       hs_vo.publication_version_date,
       hs_vo.next_status_change_time
    from house_status_version_order hs_vo
    left join max_status_order ms_o
      on hs_vo.id_house = ms_o.id_house
      and hs_vo.order_version = ms_o.order_version
      and hs_vo.order_status = ms_o.max_order_status      
  ),
house_listing_plain as (
select
    hs_v.id_house,
    hs_v.order_version as version,
    min(cast(hs_v.publication_version_date as timestamp)) as ts_listing_version_start,
    max(coalesce(hs_v.next_status_change_time,cast('2200-01-01 12:00:00' as timestamp))) as ts_listing_version_end
from house_status_version_last_status hs_v
group by 1, 2
),
house_listing_full as (
select
    cast(cast(id_house as STRING)||'00'||cast(version as STRING) as bigint) as id_house_listing,
    id_house,
    ts_listing_version_start,
    nullif(cast(ts_listing_version_end as timestamp),cast('2200-01-01 12:00:00' as timestamp)) as ts_listing_version_end
from house_listing_plain
),
smp_version as (
select
    id_smart_price,
    id_house_listing,
    id_house,
    min(ts_start_status) as ts_start_smp,
    max(ts_end_status) as ts_end_smp
from datalake_ebdb_smart_price.smart_price_versioning spv
group by 1,2,3
),
price_changes_aud as (
select
    cast(from_unixtime(cast(ts_revision as bigint)/1000) as timestamp) as date_time,
    aud.id_house as sk_house,
    aud.rent,
    dpa.is_enabled,
    aud.rev,
    case 
        when (mod_price_changes_occurred = true 
              or (reason = 'Valor alterado pela feature de preço dinâmico.' and ts_revision < 108635451 ) ) then 'smart price' 
    end as reason,
    case 
        when lag(aud.rent) over (partition by aud.id_house order by ure.id) = aud.rent then false 
        else true 
    end as true_mod_pred
from datalake_ebdb_clean.house_aud aud
join datalake_ebdb_clean.user_revision_entity ure on aud.rev = ure.id
left join datalake_ebdb_clean.dynamic_pricing_house_aud dpa on ure.id = dpa.rev
where true and aud.rent is not null
),
price_changes as (
select
    id_smart_price,
    hlf.id_house_listing,
    sk_house as id_house,
    date_time as ts_started_status,
    lead(date_time) over(partition by sk_house order by rev) as ts_ended_status,
    is_enabled,
    rent,
    reason
from price_changes_aud pca
join house_listing_full hlf on hlf.id_house = pca.sk_house and pca.date_time between coalesce(hlf.ts_listing_version_start, cast('1900-01-01' as timestamp)) and coalesce(hlf.ts_listing_version_end, now())
left join smp_version spv on hlf.id_house_listing = spv.id_house_listing and pca.date_time between spv.ts_start_smp and spv.ts_end_smp
where pca.sk_house is not null and pca.true_mod_pred = true
)
select
    coalesce(id_smart_price,-1) as sk_smart_price,
    id_house_listing as sk_house_listing,
    cast(date_format(ts_started_status, 'yyyyMMdd') as bigint) as sk_price_started_date,
    coalesce(cast(date_format(ts_ended_status,'yyyyMMdd') as bigint),-1) as sk_price_ended_date,
    is_enabled as is_smart_pricing_enabled, 
    reason as price_change_reason,
    rent,
    rank() over(partition by id_smart_price, reason order by ts_started_status) as rent_changes,
    datediff(ts_ended_status, ts_started_status) as days_with_same_rent,
    ts_started_status as ts_price_started,
    ts_ended_status as ts_price_ended,
    now() ts_load
from price_changes