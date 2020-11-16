--drop view if exists vw_dim_booking;
--create or replace view vw_dim_booking as
with bms as (
    select
        row_number() over(partition by bms.visita_id order by bms.event_time) as rn,
        bms.*
    from public.booking_media_sources bms
),
taxonomy_demand as (
-- removing duplicates rows due to case difference in the taxonomy
/* ex:
	id    |    app_type    |    utm_medium
	123   |    android     |       CPC
	456   |    android     |       cpc -- to be removed
*/
	 with taxonomy_min_ids as (
		select
		  min(id) as id
		from gsheets.taxonomy_demand
		group by
			lower(app_type),
			lower(utm_source),
			lower(utm_medium),
			lower(branded),
			lower(first_update_source),
		        flg_via_reschedule
	)
	 select
	    cast(td.id as bigint) as id,
			td.app_type,
			td.utm_source,
			td.utm_medium,
			td.branded,
			td.first_update_source,
			td.flg_via_reschedule::boolean,
			td.Category as mkt_category,
			td.Flow as mkt_flow,
			td.Completion as mkt_completion,
			td.Channel as mkt_channel,
			td.Medium as mkt_medium,
			td.Origin as mkt_origin,
			td.Source as mkt_source,
			td.Platform as mkt_platform
    from gsheets.taxonomy_demand td
    join taxonomy_min_ids td_min
    	on td.id = td_min.id
),
reschedules as (
    select "reagendadoDe_id" as id_reschedule
    from booking
    where "reagendadoDe_id" is not null
    group by 1 -- guaranteeing there are no future duplication on Product
),
bookings as (
	select
	    s.id as sk_booking,
	    s.id as id_booking,
	    r.id_reschedule is not null as is_rescheduled,
	    -- Standardizing date columns as UTC
	    timezone('Brazil/East',
	        s.data
            + (("slotDia" * 15 / 60)+8) * interval '1 hour'
            + ("slotDia" * 15 % 60) * interval '1 minute')
            at time zone ('UTC')
		as dt_booking,
		s.visit_intent,
	    s.tipo as type,
	    s."fupVisita" is not null
	      and s."fupVisita" in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
	    as confirmed,
	    s."fupVisita" is not null
	      and agent_missing_reason = 'Absent'
	    as performed,
	    s.encerrado as closed,
	    nullif(s."fupVisita", '') as visit_follow_up,
	    s."dataFupVisita" as dt_visit_follow_up,
	    s."reagendadoDe_id" as rescheduled_from_id,
	    s.visitante_id as id_visitor,
	    s.visita_id as id_visit,
	    s.imovel_id as id_property,
	    s.agente_id as id_agent,
	    s.atendente_id as id_attendant,
	    s."fluxoLocacao_id" as id_rental_flow,
	    s.status,
	    s."slotDia" as slot_dia,
	    s.reason::varchar(200) as reason,
	    s.is_visit_created_from_app,
	    s.is_visit_last_updated_from_app,
	    case
            when s.status = 'Cancelado' then s.reason_enum
        end as cancellation_reason,
	    case
	        when s.status = 'Cancelado' then
	            case
                    when s.reason_enum = 'CANCELED_HOUSE_RESERVED' then 'House Reserved'
                    when s.reason_enum = 'OTHER' then 'Other'
                    when s.reason_enum = 'CANCELED_CLIENT_GAVE_UP' then 'Tenant'
                    when s.reason_enum = 'PROPERTY_UNPUBLISHED' then 'House Unlisted'
                    when s.reason_enum = 'AGENT_SCHEDULE_REALIZED' then 'Agent'
                    when s.reason_enum = 'CANCELED_PROPERTY_SUSPENDED_ADVANCED_NEGOTIATIONS' then 'House Suspended'
                    when s.reason_enum = 'CANCELED_OWNER_SUSPENDED' then 'Consequence Management'
                    when s.reason_enum = 'CANCELED_OTHER_CLIENT' then 'Tenant'
                    when s.reason_enum = 'CANCELED_AGENT_CAN_NOT_JOIN' then 'Agent'
                    when s.reason_enum = 'CANCELED_INCORRECT_SCHEDULE' then 'Tenant'
                    when s.reason_enum = 'CANCELED_CLIENT_GAVE_UP_APARTMENT' then 'Tenant'
                    when s.reason_enum = 'CANCELED_AGENT_LATE_POOL' then 'Agent'
                    when s.reason_enum = 'AGENT_TRANSFER' then 'Agent'
                    when s.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT' then 'Consequence Management'
                    when s.reason_enum = 'CANCELED_BY_TENANT_FROM_APP' then 'Tenant'
                    when s.reason_enum = 'CANCELED_OWNER_CAN_NOT_ATTEND' then 'Owner'
                    when s.reason_enum = 'SCHEDULE_CHANGE' then 'Reschedule_Tenant'
                    when s.reason_enum = 'CANCELED_CANT_FIND_ANOTHER_AGENT' then 'Agent'
                    when s.reason_enum = 'CANCELED_CLIENT_NOT_RENTING' then 'Tenant'
                    when s.reason_enum = 'CANCELED_OWNER_PROPERTY_ALREADY_RENTED_5A' then 'Owner'
                    when s.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_SUSPENDED' then 'Consequence Management'
                    when s.reason_enum = 'CANCELED_BY_TENANT_FROM_CHECK_IN' then 'Tenant'
                    when s.reason_enum = 'CANCELED_OWNER_PROPERTY_ALREADY_RENTED_OTHER' then 'Owner'
                    when s.reason_enum = 'CANCELED_OWNER_UNREACHABLE' then 'Owner'
                    when s.reason_enum = 'CANCELED_OWNER_UNREACHABLE_UNPUBLISHED' then 'Owner'
                    when s.reason_enum = 'CANCELED_CLIENT_CAN_NOT_ATTEND' then 'Tenant'
                    when s.reason_enum = 'CANCELED_AGENT_CAN_NOT_ATTEND' then 'Agent'
                    when s.reason_enum = 'CANCELED_BLOCKED_SCHEDULE' then 'Agent'
                    when s.reason_enum = 'CANCELED_SCHEDULED_OTHER_TIME' then 'Reschedule_Agent'
                    when s.reason_enum = 'CANCELED_OWNER_NO_RETURN_NEGOTIATIONS' then 'Owner'
                    when s.reason_enum = 'CANCELED_AUTOMATICALLY_PROPERTY_UNPUBLISHED' then 'House Unlisted'
                    when s.reason_enum = 'CANCELED_OWNER_NOT_RENTING' then 'Owner'
                    when s.reason_enum = 'CANCELED_CHECKIN_NOT_DONE' then 'Tenant'
                    when s.reason_enum = 'CANCELED_PROPERTY_UNAVAILABLE' then 'Owner'
                    when s.reason_enum = 'CANCELED_BY_OWNER_FROM_APP' then 'Owner'
                    when s.reason_enum = 'CANCELED_AGENT_DEACTIVATED' then 'Agent'
                    when s.reason_enum = 'CANCELED_OTHER_OWNER' then 'Owner'
                    when s.reason_enum = 'CANCELED_PROPERTY_SUSPENDED_UNAVAILABLE' then 'House Suspended'
                    when s.reason_enum = 'CANCELED_AGENT_VISIT_TOO_FAR' then 'Agent'
                    when s.reason_enum = 'CANCELED_BY_TENANT_CAN_NOT_ATTEND' then 'Tenant'
                    when s.reason_enum = 'CANCELED_BY_TENANT_NOT_INTERESTED' then 'Tenant'
                    when s.reason_enum = 'CANCELED_BY_TENANT_NOT_RENTING' then 'Tenant'
                    when s.reason_enum = 'CANCELED_BY_TENANT_NOT_RENTING_BY_5A' then 'Tenant'
                    when s.reason_enum = 'CANCELED_BY_TENANT_OTHER_REASON' then 'Tenant'
                    when s.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_REACTION_DUE_VISIT_CANCELATION' then 'Consequence Management'
                    when s.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_REACTION_DUE_NO_SHOW' then 'Consequence Management'
                    else 'Unknown'
                end
	    end as cancellation_reason_category,
	    coalesce(
	    	nullif(d."new reason",'CHECK ORIGEM'),
	    	case
	    		when s.last_update_source in ('Inquilinos', 'SelfServiceWeb') then 'Tenant'
	    		when s.last_update_source in ('Proprietarios', 'ProprietariosEmail') then 'Owner'
	    	end,
	    	case
                when s.reason_enum = 'CANCELED_BY_OWNER_FROM_APP' then 'Owner'
                when s.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_SUSPENDED' then 'Consequence Management'
                when s.reason_enum = 'CANCELED_HOUSE_RESERVED' then 'House Reserved'
                when s.reason_enum = 'AGENT_TRANSFER' then 'Agent'
            end,
	    	s.reason_category
	   	) as reason_category,
	   	coalesce(
	   		nullif(responsible, ''),
	    	nullif(d."new reason",'CHECK ORIGEM'),
	    	case
	    		when s.last_update_source in ('Inquilinos', 'SelfServiceWeb') then 'Tenant'
	    		when s.last_update_source in ('Proprietarios', 'ProprietariosEmail') then 'Owner'
	    	end,
	    	s.reason_category
	   	) as responsible,
        s.last_update_source,
        s.first_update_source,
	   	s.cancel_timestamp,
	   	s."criadoEm" as dt_created,
		s."atualizadoEm" as dt_updated,
		sources.app_type,
		coalesce(sources.media_source, 'Unknown') as media_source,
		sources.adjust_network,
		sources.utm_source,
		sources.utm_medium,
		sources.utm_campaign,
		sources.utm_content,
		sources.utm_term,
		s.visitor_arrived,
        s.visitor_missing_reason,
        s.agent_arrived,
        s.agent_missing_reason,
        case when s.troublesome_entrance = 'LandlordNoShow' then false else true end as owner_arrived,
        case when s.troublesome_entrance = 'LandlordNoShow' then 'Absent' end as owner_missing_reason,
        s.successful_entrance,
        s.troublesome_entrance,
        s.checkin_status,
        case when (UPPER(sources.utm_campaign) like '%BRANDED%'
                    or UPPER(sources.utm_campaign) like '%INSTITUCIONAL%')
                    and lower(sources.utm_campaign) not like '%non-branded%' then 'Branded'
    		else 'Outro'
    	end as branded,
    	(s."reagendadoDe_id" IS NOT NULL) as flg_via_reschedule
	from
		public.booking s
	left join
		files.de_para_cancelamento d
		on d.reason = s.reason
	left join
		visit v
		on s.visita_id = v.id
	left join
		(
			select * from bms
			where rn = 1
			and bms.visita_id is not null
		) sources
		on v.codigo = sources.visita_id
	left join reschedules r
	    on s.id = id_reschedule
)
select
	b.sk_booking,
	b.id_booking,
	b.is_rescheduled,
	b.dt_booking,
	b.visit_intent,
	b.type,
	b.confirmed,
	b.performed,
	b.closed,
	b.visit_follow_up,
	b.dt_visit_follow_up,
	b.rescheduled_from_id,
	b.id_visitor,
	b.id_visit,
	b.id_property,
	b.id_agent,
	b.id_attendant,
	b.id_rental_flow,
	b.status,
	b.slot_dia,
	b.reason,
	b.cancellation_reason,
	b.cancellation_reason_category,
	coalesce
	(
		nullif(b.reason_category, 'Other'),
		'Unknown'
	) as reason_category,
	case
		when b.cancellation_reason_category in ('Agent','House Suspended','House Reserved','House Unlisted','Consequence Management') then 'QuintoAndar'
		when b.cancellation_reason_category in ('Reschedule_Tenant','Reschedule_Agent') then 'Reschedule'
		else b.cancellation_reason_category
	end as responsible,
	b.app_type,
  	b.media_source,
  	b.adjust_network,
  	b.utm_source,
  	b.utm_medium,
  	b.utm_campaign,
  	b.utm_content,
  	b.utm_term,
	b.cancel_timestamp,
	b.dt_created,
	b.dt_updated,
	b.last_update_source,
	b.first_update_source,
	b.visitor_arrived,
    b.visitor_missing_reason,
    b.agent_arrived,
    b.agent_missing_reason,
    b.owner_arrived,
    b.owner_missing_reason,
    b.successful_entrance,
    b.troublesome_entrance,
    b.checkin_status,
    -- Columns in local time
    TIMEZONE('UTC', b.dt_booking) at time zone 'Brazil/East' as ts_scheduling_local,
    TIMEZONE('UTC', b.cancel_timestamp) at time zone 'Brazil/East'  as ts_cancel_local,
    TIMEZONE('UTC', b.dt_created) at time zone 'Brazil/East' as ts_created_local,
    TIMEZONE('UTC', b.dt_visit_follow_up) at time zone 'Brazil/East' as ts_visit_follow_up_local,
    -- Columns used in demand taxonomy
    b.is_visit_created_from_app,
    b.is_visit_last_updated_from_app,
    b.branded = 'Branded' as flg_branded,
    b.flg_via_reschedule,
    -- Demand taxonomy
    case when td.mkt_flow is null then -1 else td.id end as sk_rent_flow_taxonomy,
    case when td.mkt_flow is null then 'Not Mapped' else td.mkt_category end as mkt_category,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_flow end as mkt_flow,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_completion end as mkt_completion,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_origin end as mkt_origin,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_channel end as mkt_channel,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_medium end as mkt_medium,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_source end as mkt_source,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_platform end as mkt_platform,
    now()::timestamp as ts_load
from
	bookings b
left join taxonomy_demand td
on
    lower(coalesce(td.app_type,'')) = lower(coalesce(b.app_type,''))
	and lower(coalesce(td.utm_source,'')) = lower(coalesce(b.utm_source,''))
	and lower(coalesce(td.utm_medium,'')) = lower(coalesce(b.utm_medium,''))
	and lower(coalesce(td.branded,'')) = lower(coalesce(b.branded,''))
	and lower(coalesce(td.first_update_source,'')) = lower(coalesce(b.first_update_source,''))
	and coalesce(td.flg_via_reschedule,false) = coalesce(b.flg_via_reschedule,false)
;
