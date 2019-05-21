with tickets_filter as (
	select distinct * from datalake_clean.zendesk_tickets t
	where (channel<>'api' or (channel='api' and tags not like '%hsm%'))
          and dt_extracted = '{partition_date}'
),
custom_fields as (
    with parse_fields as (
		select tf.id_ticket,
	        f1.field,
	        regexp_extract(f1.field, '{\\?"id\\?":"?(\d+)"?', 1) as id_field,
	        nullif(regexp_extract(f1.field, '"value\\?":\\?"?([^\\?"|}]+)', 1), 'null') as value
	    from tickets_filter tf
	    cross join unnest(regexp_extract_all(tf.custom_fields, '{[^}]+[^,]+[^{]+}')) as f1(field)
	)
	select f.id_ticket,
        map_agg(cf.raw_title, f.value) as cols
    from parse_fields f
    left join datalake_clean.zendesk_ticket_fields cf
       on cf.id_ticket_fields = f.id_field
    where f.value is not null
    group by 1
),
contract as (
    select
    cast(sk_house_listing as bigint) as sk_house_listing,
    cast(sk_client as bigint) as sk_client,
    cast(sk_contract as bigint) as sk_contract,
    cast(sk_owner as bigint) as sk_owner
  from datalake_clean.ods_fact_listing_rent_flows
  where sk_contract != '-1'
    and sk_client != '-1'
    and sk_owner != '-1'
    and sk_house_listing != '-1'
  group by 1, 2, 3, 4
),
house as (
    select
    cast(sk_house_listing as bigint) as sk_house_listing,
    cast(sk_owner as bigint) as sk_owner
  from datalake_clean.ods_fact_listing_rent_flows
  where sk_owner != '-1'
    and sk_house_listing != '-1'
  group by 1,2
),
tickets as (
    select
        t.id_ticket as sk_ticket,
        coalesce(cast(dhl.sk_house_listing as bigint), -1)  as sk_house_listing,
        coalesce(cast(dc.sk_contract as bigint), -1)  as sk_contract,
        coalesce(cast(t.id_requester as bigint), -1) as sk_zendesk_requester_user,
        coalesce(cast(t.id_submitter as bigint), -1) as sk_zendesk_submitter_user,
        coalesce(cast(t.id_assignee as bigint), -1) as sk_zendesk_assignee_user,
        coalesce(cast(date_format(cast(tm.ts_created as timestamp), '%Y%m%d') as integer), -1) as sk_created_date,
        coalesce(cast(date_format(cast(tm.ts_created_local as timestamp), '%Y%m%d') as integer), -1) as sk_created_date_local,
        coalesce(cast(date_format(cast(tm.ts_solved as timestamp), '%Y%m%d') as integer), -1) as sk_solved_date,
        coalesce('to do', '-1') as sk_closed_date,
        coalesce(cast(date_format(cast(tm.ts_initially_assigned as timestamp), '%Y%m%d') as integer), -1) as sk_initially_assigned,
        coalesce(cast(date_format(cast(tm.ts_assigned as timestamp), '%Y%m%d') as integer), -1) as sk_last_assigned,
        coalesce(cast(date_format(cast(t.dt_extracted as date), '%Y%m%d') as integer), -1) as sk_extraction_date,
        tm.group_stations as total_group_stations,
        tm.assignee_stations as total_assignee_stations,
        'to do' as minutes_first_reply_time_business,
        'to do' as minutes_first_reply_time_calendar,
        tm.minutes_first_business_resolution as minutes_first_resolution_time_business,
        tm.minutes_first_calendar_resolution as minutes_first_resolution_time_calendar,
        tm.minutes_business_requester_wait as minutes_requester_wait_time_business,
        tm.minutes_calendar_requester_wait as minutes_requester_wait_time_calendar,
        tm.minutes_business_agent_wait as minutes_agent_wait_time_business,
        tm.minutes_calendar_agent_wait as minutes_agent_wait_time_calendar,
        tm.minutes_business_on_hold as minutes_on_hold_time_business,
        tm.minutes_calendar_on_hold as minutes_on_hold_time_calendar,
        tm.minutes_full_business_resolution as minutes_full_resolution_time_business,
        tm.minutes_full_calendar_resolution as minutes_full_resolution_time_calendar,
        tm.reopens as reopens,
        tm.replies as replies,
        tm.ts_assigned as ts_last_assigned,
        tm.ts_solved as ts_solved,
        t.ts_updated as ts_updated,
        'to do' as ts_closed,
        t.ts_load
    from tickets_filter t
    left join datalake_clean.zendesk_ticket_metrics tm
        on t.id_ticket=tm.id_ticket
    left join custom_fields c 
        on c.id_ticket=t.id_ticket
    left join datalake_clean.ods_dim_house_listing dhl
        on c.cols['Código do Imóvel'] = dhl.short_id_house
        and cast(t.ts_created as timestamp)
        between cast(regexp_extract(dhl.ts_listing_version_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
        and (case
                when dhl.ts_listing_version_end='' then now()
                else cast(regexp_extract(dhl.ts_listing_version_end, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
            end)
    left join datalake_clean.ods_dim_contract dc
        on c.cols['Código do Contrato'] = dc.sk_contract
)
select
    t.sk_ticket,
    coalesce(c.sk_house_listing, t.sk_house_listing) as sk_house_listing,
    coalesce(c.sk_contract, t.sk_contract) as sk_contract,
    coalesce(c.sk_client, -1) as sk_client,
    coalesce(c.sk_owner, h.sk_owner, -1) as sk_owner,
    t.sk_zendesk_requester_user,
    t.sk_zendesk_submitter_user,
    t.sk_zendesk_assignee_user,
    t.sk_created_date,
    t.sk_created_date_local,
    t.sk_solved_date,
    'to do' as sk_solved_date_local,
    t.sk_extraction_date,
    t.minutes_first_reply_time_calendar,
	t.minutes_first_reply_time_business,
	t.minutes_first_resolution_time_calendar,
	t.minutes_first_resolution_time_business,
	t.minutes_requester_wait_time_calendar,
	t.minutes_requester_wait_time_business,
	t.minutes_agent_wait_time_calendar,
	t.minutes_agent_wait_time_business,
	t.minutes_on_hold_time_calendar,
	t.minutes_on_hold_time_business,
	t.minutes_full_resolution_time_calendar,
	t.minutes_full_resolution_time_business,
    t.reopens,
    t.replies,
    t.ts_updated,
    'to do' as ts_updated_local,
    t.ts_solved,
    'to do' as ts_solved_local,
    t.ts_closed,
    'to do' as ts_closed_local,
    now() as ts_load
from tickets t
left join contract c
    on t.sk_contract = c.sk_contract
left join house h
on t.sk_house_listing = h.sk_house_listing;