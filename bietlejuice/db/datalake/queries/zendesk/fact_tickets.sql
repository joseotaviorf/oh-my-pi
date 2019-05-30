with tickets_filter as (
	select distinct * from datalake_clean.zendesk_tickets t
    -- we don't track whatsapp notifications
	where (channel<>'api' or (channel='api' and tags not like '%hsm%'))
          and dt_extracted = '{extraction_date}'
),
last_updated_ticket as (
    select id_ticket, max(ts_updated) from tickets_filter group by 1
),
custom_fields as (
    with parse_fields as (
		select tf.id_ticket,
	        f1.field,
	        regexp_extract(f1.field, '{{\\?"id\\?":"?(\d+)"?', 1) as id_field,
	        nullif(regexp_extract(f1.field, '"value\\?":\\?"?([^\\?"|}}]+)', 1), 'null') as value
	    from tickets_filter tf
        inner join last_updated_ticket l
            on tf.id_ticket=l.id_ticket
	    cross join unnest(regexp_extract_all(tf.custom_fields, '{{[^}}]+[^,]+[^{{]+}}')) as f1(field)
	)
	select f.id_ticket,
        map_agg(cf.raw_title, f.value) as cols
    from parse_fields f
    inner join datalake_clean.zendesk_ticket_fields cf
       on cf.id_ticket_fields = f.id_field
    where f.value is not null
    group by 1
),
contract as (
    select
        cast(coalesce(fl.sk_house_listing, '-1') as bigint) as sk_house_listing,
        cast(coalesce(fl.sk_client, '-1') as bigint) as sk_client,
        cast(coalesce(fl.sk_contract, dc.sk_contract, '-1') as bigint) as sk_contract,
        cast(coalesce(fl.sk_owner, '-1') as bigint) as sk_owner
    from datalake_clean.ods_dim_contract dc 
    left join datalake_clean.ods_fact_listing_rent_flows fl
    on dc.sk_contract = fl.sk_contract 
    group by 1,2,3,4
),
house as (
    select
        cast(coalesce(dhl.sk_house_listing, '-1') as bigint) as sk_house_listing, 
        cast(coalesce(fl.sk_owner, '-1') as bigint) as sk_owner,
        -- Athena can't convert the format 'yyyy-mm-dd hh:mm:ss.xxxx' to timestamp with time zone
        regexp_extract(dhl.ts_listing_version_start, '\d{{4}}-\d{{2}}-\d{{2}}') as ts_listing_version_start,
        regexp_extract(dhl.ts_listing_version_end, '\d{{4}}-\d{{2}}-\d{{2}}') as ts_listing_version_end,
        coalesce(dhl.id_house, dhl.short_id_house) as id_house    
    from datalake_clean.ods_dim_house_listing dhl 
    left join datalake_clean.ods_fact_listing_rent_flows fl
    on dhl.sk_house_listing = fl.sk_house_listing 
    where
        -- Athena has shown that it has problems doing left joins with 'or'
    	dhl.id_house in (select distinct c.cols['Código do Imóvel'] from custom_fields c)
    	or dhl.short_id_house in (select distinct c.cols['Código do Imóvel'] from custom_fields c)
    group by 1,2,3,4,5
),
ticket_metrics as (
    with row_n as (
        select
            t.id_ticket,
            max(ts_updated) as ts_updated 
        from datalake_clean.zendesk_ticket_metrics t
        group by 1
    )
    select
        t.*
    from row_n 
    inner join datalake_clean.zendesk_ticket_metrics t
    on row_n.id_ticket = t.id_ticket and t.ts_updated=row_n.ts_updated
),
tickets as (
    select
        t.id_ticket,
        coalesce(cast(t.id_requester as bigint), -1) as sk_zendesk_requester_user,
        coalesce(cast(t.id_submitter as bigint), -1) as sk_zendesk_submitter_user,
        coalesce(cast(t.id_assignee as bigint), -1) as sk_zendesk_assignee_user,
        cast(tm.group_stations as integer) as total_group_stations,
        cast(tm.assignee_stations as integer) as total_assignee_stations,
        -- (temp) to do: handling in datalake
        cast(coalesce(nullif(tm.minutes_reply_business, 'null'), '0') as integer) as minutes_reply_calendar, 
        cast(coalesce(nullif(tm.minutes_reply_business, 'null'), '0') as integer) as minutes_reply_business,
        cast(coalesce(nullif(tm.minutes_first_resolution_business, 'null'), '0') as integer) as minutes_first_resolution_business,
        cast(coalesce(nullif(tm.minutes_first_resolution_calendar, 'null'), '0') as integer) as minutes_first_resolution_calendar,
        cast(coalesce(nullif(tm.minutes_requester_wait_business, 'null'), '0') as integer) as minutes_requester_wait_business,
        cast(coalesce(nullif(tm.minutes_requester_wait_calendar, 'null'), '0') as integer) as minutes_requester_wait_calendar,
        cast(coalesce(nullif(tm.minutes_agent_wait_business, 'null'), '0') as integer) as minutes_agent_wait_business,
        cast(coalesce(nullif(tm.minutes_agent_wait_calendar, 'null'), '0') as integer) as minutes_agent_wait_calendar,
        cast(coalesce(nullif(tm.minutes_on_hold_business, 'null'), '0') as integer) as minutes_on_hold_business,
        cast(coalesce(nullif(tm.minutes_on_hold_calendar, 'null'), '0') as integer) as minutes_on_hold_calendar,
        cast(coalesce(nullif(tm.minutes_full_resolution_business, 'null'), '0') as integer) as minutes_full_resolution_business,
        cast(coalesce(nullif(tm.minutes_full_resolution_calendar, 'null'), '0') as integer) as minutes_full_resolution_calendar,
        cast(tm.reopens as integer) as reopens,
        cast(tm.replies as integer) as replies,
        cast(tm.ts_initially_assigned as timestamp with time zone) as ts_initially_assigned,
        -- bug caused by start delay of daylight saving time
        if(cast(tm.ts_initially_assigned as timestamp with time zone) >= cast('2018-10-23 02:00:00 UTC' as timestamp with time zone) and 
	    cast(tm.ts_initially_assigned as timestamp with time zone) <= cast('2018-11-04 03:00:00 UTC' as timestamp with time zone),
		    cast(tm.ts_initially_assigned as timestamp with time zone) at time zone 'GMT-3',
		    cast(tm.ts_initially_assigned as timestamp with time zone) at time zone 'Brazil/East') as ts_initially_assigned_local,
        cast(tm.ts_assigned as timestamp with time zone) as ts_last_assigned,
        if(cast(tm.ts_assigned as timestamp with time zone) >= cast('2018-10-23 02:00:00 UTC' as timestamp with time zone) and 
	    cast(tm.ts_assigned as timestamp with time zone) <= cast('2018-11-04 03:00:00 UTC' as timestamp with time zone),
		    cast(tm.ts_assigned as timestamp with time zone) at time zone 'GMT-3',
		    cast(tm.ts_assigned as timestamp with time zone) at time zone 'Brazil/East') as ts_last_assigned_local,
        cast(tm.ts_solved as timestamp with time zone) as ts_solved,
        if(cast(tm.ts_solved as timestamp with time zone) >= cast('2018-10-23 02:00:00 UTC' as timestamp with time zone) and 
	    cast(tm.ts_solved as timestamp with time zone) <= cast('2018-11-04 03:00:00 UTC' as timestamp with time zone),
		    cast(tm.ts_solved as timestamp with time zone) at time zone 'GMT-3',
		    cast(tm.ts_solved as timestamp with time zone) at time zone 'Brazil/East') as ts_solved_local,
        cast(t.ts_created as timestamp with time zone) as ts_created,
        cast(t.ts_created_local as timestamp with time zone) as ts_created_local,
        cast(t.ts_updated as timestamp with time zone) as ts_updated,
        if(cast(t.ts_updated as timestamp with time zone) >= cast('2018-10-23 02:00:00 UTC' as timestamp with time zone) and 
	    cast(t.ts_updated as timestamp with time zone) <= cast('2018-11-04 03:00:00 UTC' as timestamp with time zone),
		    cast(t.ts_updated as timestamp with time zone) at time zone 'GMT-3',
		    cast(t.ts_updated as timestamp with time zone) at time zone 'Brazil/East') as ts_updated_local,
        if(t.status='closed',cast(t.ts_updated as timestamp with time zone), null) as ts_closed,
         if(t.status='closed',    
            if(cast(t.ts_updated as timestamp with time zone) >= cast('2018-10-23 02:00:00 UTC' as timestamp with time zone) and 
	        cast(t.ts_updated as timestamp with time zone) <= cast('2018-11-04 03:00:00 UTC' as timestamp with time zone),
		        cast(t.ts_updated as timestamp with time zone) at time zone 'GMT-3',
		        cast(t.ts_updated as timestamp with time zone) at time zone 'Brazil/East'),
            null) as ts_closed_local,
        t.ts_load as ts_load
    from last_updated_ticket lt 
    inner join tickets_filter t
        on t.id_ticket = lt.id_ticket
    left join ticket_metrics tm
        on t.id_ticket=tm.id_ticket
)
select
    cast(t.id_ticket as bigint) as sk_ticket,
    coalesce(dc.sk_house_listing, dhl.sk_house_listing, -1) as sk_house_listing,
    coalesce(dc.sk_contract, -1)  as sk_contract,
    coalesce(dc.sk_client, -1)  as sk_client,
    coalesce(dc.sk_owner, -1)  as sk_owner,
    t.sk_zendesk_requester_user,
    t.sk_zendesk_submitter_user,
    t.sk_zendesk_assignee_user,
    coalesce(cast(date_format(t.ts_created, '%Y%m%d') as integer), -1) as sk_created_date,
    coalesce(cast(date_format(t.ts_created_local, '%Y%m%d') as integer), -1) as sk_created_date_local,
    coalesce(cast(date_format(t.ts_solved, '%Y%m%d') as integer), -1) as sk_solved_date,
    coalesce(cast(date_format(t.ts_solved_local, '%Y%m%d') as integer), -1) as sk_solved_date_local,
    coalesce(cast(date_format(t.ts_closed, '%Y%m%d') as integer), -1) as sk_closed_date,
    coalesce(cast(date_format(t.ts_closed_local, '%Y%m%d') as integer), -1) as sk_closed_date_local,
    coalesce(cast(date_format(t.ts_initially_assigned, '%Y%m%d') as integer), -1) as sk_initially_assigned,
    coalesce(cast(date_format(t.ts_initially_assigned_local, '%Y%m%d') as integer), -1) as sk_initially_assigned_local,
    coalesce(cast(date_format(t.ts_last_assigned, '%Y%m%d') as integer), -1) as sk_last_assigned,
    coalesce(cast(date_format(t.ts_last_assigned_local, '%Y%m%d') as integer), -1) as sk_last_assigned_local,
    t.total_group_stations,
    t.total_assignee_stations,
    -- temp (I will rename this columns in datalake clean)
    t.minutes_reply_calendar as minutes_first_reply_time_calendar,
	t.minutes_reply_business as minutes_first_reply_time_business,
	t.minutes_first_resolution_calendar as minutes_first_resolution_time_calendar,
	t.minutes_first_resolution_business as minutes_first_resolution_time_business,
	t.minutes_requester_wait_calendar as minutes_requester_wait_time_calendar,
	t.minutes_requester_wait_business as minutes_requester_wait_time_business,
	t.minutes_agent_wait_calendar as minutes_agent_wait_time_calendar,
	t.minutes_agent_wait_business as minutes_agent_wait_time_business,
	t.minutes_on_hold_calendar as minutes_on_hold_time_calendar,
	t.minutes_on_hold_business as minutes_on_hold_time_business,
	t.minutes_full_resolution_calendar as minutes_full_resolution_time_calendar,
	t.minutes_full_resolution_business as minutes_full_resolution_time_business,
    t.reopens,
    t.replies,
    t.ts_initially_assigned,
    t.ts_initially_assigned_local,
    t.ts_last_assigned,
    t.ts_last_assigned_local,
    t.ts_solved,
    t.ts_solved_local,
    t.ts_updated,
    t.ts_updated_local,
    t.ts_closed,
    t.ts_closed_local,
    now() as ts_load
from tickets t
left join custom_fields c 
    on c.id_ticket=t.id_ticket
left join house dhl
	on c.cols['Código do Imóvel'] = dhl.id_house
    and date_format(cast(t.ts_created as timestamp with time zone), '%Y-%m-%d')
    between dhl.ts_listing_version_start
    and coalesce(dhl.ts_listing_version_end, date_format(now() - interval '1' day, '%Y-%m-%d'))         
left join contract dc
    on c.cols['Código do Contrato'] = cast(dc.sk_contract as varchar);