-- FIRSTLY WE ORGANIZE THE STRUCTURES
-- (1) BOOKINGS, (2) TALK TO AGENT and (3) OFFER

-- BOOKINGS
with fb as (
    select 
        sk_rent_flow,
        sk_house_listing,
    	sk_client,
    	count(distinct sk_booking) as visits_booked,
    	count(distinct case when flg_visit_completed then sk_booking end) as visits_completed,
        min(db.dt_created) as dt_first_visit_booked,
        min(case when rf.flg_visit_completed then db.dt_created end) as dt_first_visit_completed,
        min(case when fup.visit_type='PRESENTIAL' or (rf.flg_visit_completed and fup.visit_type<>'VIDEO') then db.dt_created end) as dt_first_presential_visit,
        count(distinct case when rf.sk_booking >0 then rf.sk_booking end) as nbr_visit_booked,
        count(distinct case when rf.flg_visit_completed then rf.sk_booking end) as nbr_visit_completed,
        count(distinct case when fup.visit_type='PRESENTIAL' or (rf.flg_visit_completed and fup.visit_type<>'VIDEO') then rf.sk_booking end) as nbr_presential_visit
    from fact_listing_rent_flows rf
    join dim_booking db
        using(sk_booking)
    left join datalake_ebdb_clean_prod.booking 
        on booking.id=db.sk_booking
    left join datalake_ebdb_clean_prod.follow_up_details fup
        on fup.id = booking.id_fup_details 
    left join dim_tenant_booking_review
        using(sk_tenant_booking_review)
    where sk_booking > 0
    group by 1,2,3
),

-- (2) TALK TO AGENT
-- Users who started attendance (PS: this is temporary until we have product dev. and a dim_ model)
ft as(
    select sk_house_listing,
        tenant_id,
        min(first_message_ts)::timestamp as dt_tta,
        sum(msg_sent) as msg_sent
    from datamarts.talk_to_agent
    group by 1,2
),

--OFFERS
fo as (
	select 
	    distinct rf.sk_offer,
        rf.sk_client,
        rf.sk_house_listing,
        o.type,
        o.dt_first_sent as dt_offer,
		case
			when visits_completed>0 and dt_first_visit_booked <= o.dt_first_sent then 'OS_VC'
			when visits_completed=0 and dt_first_visit_booked <= o.dt_first_sent then 'OS_WITH_VB'
			when visits_completed is null then 'OS_DIRECT'
			when visits_completed=0 and dt_first_visit_booked > o.dt_first_sent then 'OS_DIRECT_VB_LATER'
			when visits_completed>0 and dt_first_visit_booked > o.dt_first_sent then 'OS_DIRECT_VC_LATER'
		end	as offer_type,
		((visits_completed is null) or (dt_first_visit_booked > o.dt_first_sent)) as direct_offer
	from fact_listing_rent_flows rf
	join dim_offer o
	    using(sk_offer)
	left join fb
		on (fb.sk_client=rf.sk_client and fb.sk_house_listing=rf.sk_house_listing)
	where rf.sk_offer > 0
	group by 1,2,3,4,5,visits_completed,dt_first_visit_booked,o.dt_first_sent
),


-- NOW WE CLASSIFY THE RENTFLOWS
-- Criterea: flow (highest touchpoint), first_touchpoint (where it started), had_[do,tta,pv] (where it passed)

flows_class as (

    select
        r.sk_rent_flow,
        r.sk_house_listing,
        r.sk_client,
        
        least(min(fo.dt_offer),min(ft.dt_tta),min(fb.dt_first_visit_booked)) as first_ts,
        
        --flow highest intent flow
        case  
             when max(case when fb.visits_booked>0 then 1 else 0 end)> 0 then 'VISIT'
             when max(case when msg_sent>0 then 1 else 0 end) > 0 then 'TTA'
             when max(case when fo.sk_offer>0 then 1 else 0 end) > 0 then 'DIRECT'
          else 'UNKNOWN' end as funnel_flow, 
    
        case
            when min(fb.dt_first_visit_booked) < least(min(ft.dt_tta),min(fo.dt_offer),current_timestamp) then 'VISIT'
            when min(ft.dt_tta)  < least(min(fb.dt_first_visit_booked),min(fo.dt_offer),current_timestamp) then 'TTA'
            when min(fo.dt_offer) < least(min(ft.dt_tta),min(fb.dt_first_visit_booked),current_timestamp) then 'DIRECT'
        else 'UNKNOWN' end as funnel_first_touchpoint,
    
        bool_or(case when fo.direct_offer=true then 1 else 0 end) as had_flow_direct,
        bool_or(case when ft.msg_sent>0 then 1 else 0 end) as had_flow_tta,
        bool_or(case when fb.visits_booked>0 then 1 else 0 end) as had_flow_visit,
    
        count(distinct case when fo.direct_offer then fo.sk_offer end) as nbr_direct_offer,
        count(distinct case when fo.sk_offer>0 then fo.sk_offer end) as nbr_offer,
        count(distinct case when ft.dt_tta >0 then ft.dt_tta end) as nbr_tta,
        min(fb.nbr_visit_booked) as nbr_visit_booked,
        min(fb.nbr_visit_completed) as nbr_visit_completed,
        min(fb.nbr_presential_visit) as nbr_presential_visit,
    
        min(case when fo.direct_offer then fo.dt_offer end) as dt_first_direct_offer,
        min(fo.dt_offer) as dt_first_offer,
        min(ft.dt_tta) as dt_first_tta,
        min(fb.dt_first_visit_booked) as dt_first_visit_booked,
        min(dt_first_visit_completed) as dt_first_visit_completed,
        min(dt_first_presential_visit) as dt_first_presential_visit,
    
        min(case when fo.direct_offer then fo.dt_offer end) as dt_flow_direct,
        min(case when msg_sent>0 then ft.dt_tta end) as dt_flow_tta,
        min(fb.dt_first_visit_booked) as dt_flow_visit,
        bool_or(sk_contract_signed_date>0) as cs,
    
        count(*) as lines
    
    from fact_listing_rent_flows r
    
    left join fo
        on fo.sk_client = r.sk_client
            and fo.sk_house_listing = r.sk_house_listing

    left join ft
        on ft.tenant_id = r.sk_client
            and ft.sk_house_listing = r.sk_house_listing
    
    left join fb
        on fb.sk_client = r.sk_client
            and fb.sk_house_listing = r.sk_house_listing

    group by 1,2,3
),

final as (

    select 
        sk_rent_flow,
        sk_house_listing,
        sk_client,
        first_ts,
        funnel_flow,
        funnel_first_touchpoint,
        
        had_flow_direct,
        had_flow_tta,
        had_flow_visit,
        
        nbr_direct_offer,
        nbr_tta,
        nbr_offer,
        nbr_visit_booked,
        nbr_visit_completed,
        nbr_presential_visit,
        
        dt_first_direct_offer,
        dt_first_offer,
        dt_first_tta,
        dt_first_visit_booked,
        dt_first_visit_completed,
        dt_first_presential_visit,
    
        --Sankey Flows
        cast(case
            when dt_flow_direct>0 and ((dt_flow_tta is null and dt_flow_visit is null) or (dt_flow_direct<(least(dt_flow_visit,dt_flow_tta)))) then '1'
            when dt_flow_tta>0 and ((dt_flow_direct is null and dt_flow_visit is null) or (dt_flow_tta<(least(dt_flow_direct,dt_flow_visit)))) then '2'
            when dt_flow_visit>0 and ((dt_flow_tta is null and dt_flow_direct is null) or (dt_flow_visit<(least(dt_flow_tta,dt_flow_direct)))) then '3'
            else '-'
        end as varchar)
        ||
        cast(case
            when (dt_flow_direct> dt_flow_tta) and (dt_flow_direct < dt_flow_visit or dt_flow_visit is null)  then '1'
            when (dt_flow_direct> dt_flow_visit) and (dt_flow_direct < dt_flow_tta or dt_flow_tta is null)  then '1'
            when (dt_flow_tta> dt_flow_direct) and (dt_flow_tta < dt_flow_visit or dt_flow_visit is null)  then '2'
            when (dt_flow_tta> dt_flow_visit) and (dt_flow_tta < dt_flow_direct or dt_flow_direct is null)  then '2'
            when (dt_flow_visit> dt_flow_direct) and (dt_flow_visit < dt_flow_tta or dt_flow_tta is null)  then '3'
            when (dt_flow_visit> dt_flow_tta) and (dt_flow_visit < dt_flow_direct or dt_flow_direct is null)  then '3'
            else '-'
        end as varchar)
        ||
        cast(case
            when dt_flow_direct> greatest(dt_flow_tta,dt_flow_visit) and dt_flow_tta is not null and dt_flow_visit is not null then '1'
            when dt_flow_tta> greatest(dt_flow_visit,dt_flow_direct) and dt_flow_visit is not null and dt_flow_direct is not null then '2'
            when dt_flow_visit> greatest(dt_flow_tta,dt_flow_direct) and dt_flow_tta is not null and dt_flow_direct is not null then '3'
            else '-'
        end as varchar)
        as sankey_flows,
    
        --Combined Flows
        case 
            when had_flow_visit=0 and had_flow_direct=1 and had_flow_tta=0 then '(1) ONLY DIRECT OFFER'
            when had_flow_visit=0 and had_flow_direct=0 and had_flow_tta=1 then '(2) ONLY TALK TO AGENT'
            when had_flow_visit=1 and had_flow_direct=0 and had_flow_tta=0 then '(3) ONLY VISIT'
            when had_flow_visit=0 and had_flow_direct=1 and had_flow_tta=1 then '(1) DIRECT OFFER + (2) TALK TO AGENT'
            when had_flow_visit=1 and had_flow_direct=1 and had_flow_tta=0 then '(1) DIRECT OFFER + (3) VISIT'
            when had_flow_visit=1 and had_flow_direct=0 and had_flow_tta=1 then '(2) TALK TO AGENT + (3) VISIT'
            when had_flow_visit=1 and had_flow_direct=1 and had_flow_tta=1 then '(1) DO + (2) TTA + (3) VISIT'
            when had_flow_visit=0 and had_flow_direct=0 and had_flow_tta=0 then 'NO ONE'
            else 'UNK' end as flow_type,
    
        --Sankey Journey
        cast(case
            when dt_first_offer>0 and ((dt_first_tta is null and dt_first_visit_completed is null) or (dt_first_offer<(least(dt_first_visit_completed,dt_first_tta)))) then '1'
            when dt_first_tta>0 and ((dt_first_offer is null and dt_first_visit_completed is null) or (dt_first_tta<(least(dt_first_offer,dt_first_visit_completed)))) then '2'
            when dt_first_visit_completed>0 and ((dt_first_tta is null and dt_first_offer is null) or (dt_first_visit_completed<(least(dt_first_tta,dt_first_offer)))) then '3'
            else '-'
        end as varchar)
        ||
        cast(case
            when (dt_first_offer> dt_first_tta) and (dt_first_offer < dt_first_visit_completed or dt_first_visit_completed is null)  then '1'
            when (dt_first_offer> dt_first_visit_completed) and (dt_first_offer < dt_first_tta or dt_first_tta is null)  then '1'
            when (dt_first_tta> dt_first_offer) and (dt_first_tta < dt_first_visit_completed or dt_first_visit_completed is null)  then '2'
            when (dt_first_tta> dt_first_visit_completed) and (dt_first_tta < dt_first_offer or dt_first_offer is null)  then '2'
            when (dt_first_visit_completed> dt_first_offer) and (dt_first_visit_completed < dt_first_tta or dt_first_tta is null)  then '3'
            when (dt_first_visit_completed> dt_first_tta) and (dt_first_visit_completed < dt_first_offer or dt_first_offer is null)  then '3'
            else '-'
        end as varchar)
        ||
        cast(case
            when dt_first_offer> greatest(dt_first_tta,dt_first_visit_completed) and dt_first_tta is not null and dt_first_visit_completed is not null then '1'
            when dt_first_tta> greatest(dt_first_visit_completed,dt_first_offer) and dt_first_visit_completed is not null and dt_first_offer is not null then '2'
            when dt_first_visit_completed> greatest(dt_first_tta,dt_first_offer) and dt_first_tta is not null and dt_first_offer is not null then '3'
            else '-'
        end as varchar)
        as sankey_journey,
        cs,
        lines
        
    from flows_class
)

select * from final
