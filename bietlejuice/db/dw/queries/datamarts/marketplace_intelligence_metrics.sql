with
daily_published_listings as (
  select
      f.sk_house_listing,
      substring(f.sk_house_listing,1,9) as sk_house,
      f.status_history,
      date(f.sk_status_start_date) as status_start_date,
      f.status_change_reason,
      d.date,
      row_number() over(partition by f.sk_house_listing, d.date order by f.ts_status_start desc) as order_status -- daily order status
  from fact_house_listing_status f
  join dim_date d
    on d.sk_date between nullif(f.sk_status_start_date,-1) and coalesce(to_char(to_date(nullif(sk_status_end_date, -1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
  where substring(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
    and d.date between date('2019-01-01') and current_date
),
daily_published_listings_adjusted as (
  select
    fhs.sk_house_listing,
    fhs.sk_house,
    fhs.status_start_date,
    dhl.house_unpublished_reason,
    case
            when fhs.status_history != 'suspenso' then fhs.status_history
            when (lower(fhs.status_change_reason) like '%reserv%' or lower(fhs.status_change_reason) like '%negocia%'
                or lower(fhs.status_change_reason) like '%proposta%') then 'suspended_in_negotiation'
            else 'suspended_other'
        end status_history_v2,
    dhl.house_bedrooms,
    fhs.date,
    fhs.order_status,
    fhs.status_history,
    fhl.sk_region
  from daily_published_listings fhs
  left join fact_house_listings fhl
    on fhs.sk_house_listing = fhl.sk_house_listing
  left join dim_region dr
    on fhl.sk_region = dr.sk_region
  left join dim_house_listing dhl
    on fhs.sk_house_listing = dhl.sk_house_listing
  where fhs.order_status = 1
    and dr.city_group is not null
),
last_version_listings as (
select
  id_house,
  sk_house_listing,
  ts_listing_version_start,
  ts_listing_version_end
from datalake_clean.ods_dim_house_listing
where version > 0
),
events as (
  select
      date(ts_event) as event_date,
    ts_event as event_timestamp,
    ev.id_user,
    lvl.sk_house_listing,
    case when trim(event_type) = 'listing_page_viewed' then 1 else 0 end as listing_page_viewed,
    case when trim(event_type) = 'piloto_cw_message_sent' then 1 else 0 end as talk_to_agent_message_sent,
    case when trim(event_type) = 'offer_submitted' then 1 else 0 end as offer_submitted,
    case when trim(event_type) = 'visit_schedule_confirmed' then 1 else 0 end as visit_booked,
    case when trim(event_type) = 'contract_docusign_signed' then 1 else 0 end as contract_signed
  from datalake_amplitude_clean_prod.events ev
  left join last_version_listings lvl
    on trim(json_extract_path_text(ev.event_properties, 'house_id'))  = lvl.id_house
    and ev.ts_event between lvl.ts_listing_version_start and (coalesce(lvl.ts_listing_version_end, current_timestamp) - interval '1 second')
  where
    date(ev.ts_event) >= date('2019-01-01')
    and trim(ev.event_type) in (
      'listing_page_viewed',
      'piloto_cw_message_sent',
      'offer_submitted',
      'visit_schedule_confirmed',
      'contract_docusign_signed'
    )
)
select
  dpl.date as base_date,
  dpl.sk_house_listing,
  dpl.sk_house,
  dpl.house_bedrooms,
  datediff(week, dpl.status_start_date, dpl.date) as age_weeks,
  dpl.status_start_date as publication_date,
  dpl.house_unpublished_reason,
  dpl.sk_region,
  dpl.status_history,
  dpl.status_history_v2,
  evt.id_user,
  coalesce(sum(evt.listing_page_viewed), 0) as listing_page_viewed,
  coalesce(sum(evt.talk_to_agent_message_sent), 0) as talk_to_agent_message_sent,
  coalesce(sum(evt.offer_submitted), 0) as offer_submitted,
  coalesce(sum(evt.visit_booked), 0) as visit_booked,
  coalesce(sum(evt.contract_signed), 0) as contract_signed
from daily_published_listings_adjusted dpl
left join events evt
  on dpl.sk_house_listing = evt.sk_house_listing
  and dpl.date = evt.event_date
group by 1,2,3,4,5,6,7,8,9,10,11