with tickets_filter as (
	select distinct * from datalake_clean.zendesk_tickets t
    -- we don't track whatsapp notifications
	where (t.ticket_via<>'api' or (t.ticket_via='api' and t.tags not like '%hsm%'))
          and dt_extracted = '{extraction_date}'
),
last_updated_ticket as (
    select id_ticket, max(ts_updated) as ts_last_updated from tickets_filter group by 1
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
    where fl.sk_owner != '-1'
          and fl.sk_client != '-1'
          and fl.sk_house_listing != '-1'
          and fl.sk_contract != '-1'
    group by 1,2,3,4
),
house as (
    select
        cast(coalesce(dhl.sk_house_listing, '-1') as bigint) as sk_house_listing, 
        cast(coalesce(fhl.sk_owner, '-1') as bigint) as sk_owner,
        -- Athena can't convert the format 'yyyy-mm-dd hh:mm:ss.xxxx' to timestamp with time zone
        regexp_extract(dhl.ts_listing_version_start, '\d{{4}}-\d{{2}}-\d{{2}}') as dt_listing_version_start,
        regexp_extract(dhl.ts_listing_version_end, '\d{{4}}-\d{{2}}-\d{{2}}') as dt_listing_version_end,
        cast(dhl.id_house as bigint) as id_house,
        coalesce(try_cast(dhl.version as smallint), 1) as version
    from datalake_clean.ods_dim_house_listing dhl 
    left join datalake_clean.ods_fact_house_listings fhl
    on dhl.sk_house_listing = fhl.sk_house_listing 
    where
        fhl.sk_owner != '-1'
    group by 1,2,3,4,5,6
),
custom_field_ids as (
      select
        c.id_ticket,
        cast(json_extract(c.custom_fields,'$["46785608"]') as varchar) as client_type,
        if(
            length(try_cast(json_extract(c.custom_fields, '$["31646438"]') as varchar)) < 9,
            892700000 + try_cast(json_extract(c.custom_fields, '$["31646438"]') as bigint), 
            try_cast(json_extract(c.custom_fields, '$["31646438"]') as bigint)
        ) as id_house,
        try_cast(json_extract(c.custom_fields, '$["114096515211"]') as bigint) as id_contract,
        try_cast(json_extract(c.custom_fields, '$["360034234371"]') as bigint) as id_session  --Sauron
    from datalake_clean.zendesk_custom_fields c
    where c.dt_extracted = '{extraction_date}'
),
ticket_metrics as (
    with row_n as (
        select
            t.id_ticket, 
            -- it was necessary 2 columns, because there are other update fields,
            -- so, when ts_updated is duplicate, we get data with the last extraction  
            max(dt_extracted) as ts_extracted,
            max(ts_updated) as ts_updated
        from datalake_clean.zendesk_ticket_metrics t
        group by 1
    )
    select
        tm.id_ticket,
        cast(tm.group_stations as smallint) as total_group_stations,
        cast(tm.assignee_stations as smallint) as total_assignee_stations,
        -- (temp) to do: handling in datalake
        cast(nullif(tm.minutes_reply_calendar, 'null') as integer) as minutes_reply_calendar,
        cast(nullif(tm.minutes_reply_business, 'null') as integer) as minutes_reply_business,
        cast(nullif(tm.minutes_first_resolution_business, 'null') as integer) as minutes_first_resolution_business,
        cast(nullif(tm.minutes_first_resolution_calendar, 'null') as integer) as minutes_first_resolution_calendar,
        cast(nullif(tm.minutes_requester_wait_business, 'null') as integer) as minutes_requester_wait_business,
        cast(nullif(tm.minutes_requester_wait_calendar, 'null') as integer) as minutes_requester_wait_calendar,
        cast(nullif(tm.minutes_agent_wait_business, 'null') as integer) as minutes_agent_wait_business,
        cast(nullif(tm.minutes_agent_wait_calendar, 'null') as integer) as minutes_agent_wait_calendar,
        cast(nullif(tm.minutes_on_hold_business, 'null') as integer) as minutes_on_hold_business,
        cast(nullif(tm.minutes_on_hold_calendar, 'null') as integer) as minutes_on_hold_calendar,
        cast(nullif(tm.minutes_full_resolution_business, 'null') as integer) as minutes_full_resolution_business,
        cast(nullif(tm.minutes_full_resolution_calendar, 'null') as integer) as minutes_full_resolution_calendar,
        cast(tm.reopens as smallint) as reopens,
        cast(tm.replies as smallint) as replies,
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
		    cast(tm.ts_solved as timestamp with time zone) at time zone 'Brazil/East') as ts_solved_local
    from row_n 
    inner join datalake_clean.zendesk_ticket_metrics tm
    on row_n.id_ticket = tm.id_ticket 
    and tm.dt_extracted=row_n.ts_extracted
    and tm.ts_updated=row_n.ts_updated
),
tickets as (
    select
        cast(t.id_ticket as bigint) as sk_ticket,
        -- id_contract and id_house may be filled with string (filled wrong)
        -- id_house may be filled with id_house or short_id_house
        cfi.id_house,
        cfi.id_contract,
        cfi.id_session,
        cfi.client_type, -- included to enable sk_owner and sk_client relationship
        tm.*,
        t.tags, -- included to enable sk_user relationship model
        coalesce(cast(t.id_requester as bigint), -1) as sk_zendesk_requester_user,
        coalesce(cast(t.id_submitter as bigint), -1) as sk_zendesk_submitter_user,
        coalesce(cast(t.id_assignee as bigint), -1) as sk_zendesk_assignee_user,
        cast(t.ts_created as timestamp with time zone) as ts_created,
        date_format(cast(t.ts_created as timestamp with time zone), '%Y-%m-%d') as str_created_date,
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
        on t.id_ticket = lt.id_ticket and t.ts_updated=lt.ts_last_updated
    left join ticket_metrics tm
        on t.id_ticket=tm.id_ticket
    left join custom_field_ids cfi
        on t.id_ticket = cfi.id_ticket
),
last_zendesk_user as (
    select 
        id_user, 
        max(ts_updated) as ts_last_updated
    from 
        datalake_clean.zendesk_users 
    group by 1
),
distinct_zendesk_users as (
    select 
        cast(du.id_user as bigint) as sk_zendesk_user,
        du.email,
        regexp_replace(du.phone,'(\D+)','') as phone
    from datalake_clean.zendesk_users du
    inner join last_zendesk_user lu
    on du.id_user=lu.id_user
       and du.ts_updated=lu.ts_last_updated
),
customer_contacts as (
    select
        zu.sk_zendesk_user,
        max(coalesce(cci_e.id_user, cci_p.id_user)) as sk_user,
        max(coalesce(cci_e.cpf,cci_p.cpf)) as sk_personal_document
    from distinct_zendesk_users zu
    left join datalake_ebdb_customer_contact_identification_prod.customer_contact_identification cci_p
        on regexp_replace(cci_p.customer_contact,'(\D+)','') = zu.phone
        and cci_p.channel = 'phone'
    left join datalake_ebdb_customer_contact_identification_prod.customer_contact_identification cci_e
        on cci_e.customer_contact = zu.email
        and cci_e.channel = 'email'
    group by 1
),
-- evaluate funnel keys from each ticket according to business rules
ticket_funnel_keys as (
	select
        t.sk_ticket,
        coalesce(dc.sk_house_listing, dhl.sk_house_listing) as sk_house_listing,
        dc.sk_contract  as sk_contract,
        cc.sk_user as sk_user,
        cc.sk_personal_document,
        -- tickets will only have a valid client key according to its corresponding client type
        case when t.client_type = 'inquilino' then dc.sk_client end as sk_client,
        case when t.client_type in ('proprietário','imobiliária_b2b') then coalesce(dc.sk_owner, dhl.sk_owner) end as sk_owner
    from tickets t
	left join contract dc
        on t.id_contract = dc.sk_contract
    left join house dhl
        on t.id_house = dhl.id_house
        and str_created_date between
            (case when dhl.version = 1 then least(coalesce(dhl.dt_listing_version_start, t.str_created_date), t.str_created_date)
            else dhl.dt_listing_version_start end)
            and date_format(coalesce(cast(dhl.dt_listing_version_end as timestamp), now())  - interval '1' day,'%Y-%m-%d')
	left join customer_contacts cc
		on cc.sk_zendesk_user = t.sk_zendesk_requester_user
)
select
    t.sk_ticket,
    coalesce(fk.sk_house_listing, -1) as sk_house_listing,
    coalesce(fk.sk_contract, -1)  as sk_contract,
    coalesce(fk.sk_user, -1) as sk_user,
    fk.sk_personal_document,
    coalesce(fk.sk_client, -1) as sk_client,
    coalesce(fk.sk_owner, -1) as sk_owner,
    t.sk_zendesk_requester_user,
    t.sk_zendesk_submitter_user,
    t.sk_zendesk_assignee_user,
    coalesce(t.id_session, -1) as sk_session,
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
inner join ticket_funnel_keys fk
	on t.sk_ticket = fk.sk_ticket
