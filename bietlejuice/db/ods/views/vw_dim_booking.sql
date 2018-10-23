drop view if exists public.vw_dim_booking;

create or replace view public.vw_dim_booking
as
with bms as (
    select
        row_number() over(partition by bms.visita_id order by bms.event_time) as rn,
        bms.*
    from public.booking_media_sources bms
),
taxonomy_demand as (
	 select
		td.app_type,
		td.utm_source,
		td.utm_medium,
		td.branded,
		td.first_update_source,
		td.flg_via_reschedule::boolean,
		td."Category" as mkt_category,
		td."Flow" as mkt_flow,
		td."Completion" as mkt_completion,
		td."Channel" as mkt_channel,
		td."Medium" as mkt_medium,
		td."Source" as mkt_source,
		td."Platform" as mkt_platform
    from
        files.taxonomy_demand td
),
bookings as
(
	select 
		  s.id as sk_booking,
	    -- coalesce(r2.id, r.id, s.id) as id_booking,
	    coalesce(s."reagendadoDe_id", s.id) as id_booking,
	    -- coalesce(r2.id, r.id, s.id) = s.id as valid_bookings_not_rescheduled,
	    max(s.id) over (partition by coalesce(s."reagendadoDe_id", s.id)) = s.id as valid_bookings_not_rescheduled,
	    s.data 
				+ (("slotDia" * 15 / 60)+8) * interval '1 hour' 
				+ ("slotDia" * 15 % 60) * interval '1 minute' 				
			as dt_booking,
	    s.tipo as type,
	    s."fupVisita" is not null
	      and s."fupVisita" in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho')
	    as confirmed,
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
	    coalesce(
	    	nullif(d."new reason",'CHECK ORIGEM'), 
	    	case  
	    		when s.last_update_source in ('Inquilinos', 'SelfServiceWeb') then 'Tenant'
	    		when s.last_update_source in ('Proprietarios', 'ProprietariosEmail') then 'Owner'
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
		now()::timestamp as dt_timestamp,
		sources.app_type,
		coalesce(sources.media_source, 'Unknown') as media_source,
		sources.adjust_network,
		sources.utm_source,
		sources.utm_medium,
		sources.utm_campaign,
		s.visitor_arrived,
        s.visitor_missing_reason,
        s.agent_arrived,
        s.agent_missing_reason,
        s.owner_arrived,
        s.owner_missing_reason,
        s.successful_entrance,
        s.troublesome_entrance,
        s.checkin_status,
        case when UPPER(sources.utm_campaign) like '%BRANDED%' or UPPER(sources.utm_campaign) like '%INSTITUCIONAL%' then 'Branded'
    		else 'Other'
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
)
select
	b.sk_booking,
	b.id_booking,
	b.valid_bookings_not_rescheduled,
	b.dt_booking,
	b.type,
	b.confirmed,
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
	coalesce
	(
		nullif(b.reason_category, 'Other'),
		'Unknown'
	) as reason_category,
	case
		when nullif(b.responsible, 'Other') is null then 'Unknown'
		when b.responsible = 'Agent' then 'QuintoAndar'
		else b.responsible
	end as responsible,
	b.app_type,
  	b.media_source,
  	b.adjust_network,
  	b.utm_source,
  	b.utm_medium,
  	b.utm_campaign,
	b.cancel_timestamp,
	b.dt_created,
	b.dt_updated,
	b.dt_timestamp,
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
    b.branded = 'Branded' as flg_branded,
    b.flg_via_reschedule,
    case when td.mkt_flow is null then 'Not Mapped' else td.mkt_category end as mkt_category,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_flow end as mkt_flow,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_completion end as mkt_completion,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_channel end as mkt_channel,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_medium end as mkt_medium,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_source end as mkt_source,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_platform end as mkt_platform
from
	bookings b
left join taxonomy_demand td
on
    coalesce(td.app_type,'') = coalesce(b.app_type,'')
	and coalesce(td.utm_source,'') = coalesce(b.utm_source,'')
	and coalesce(td.utm_medium,'') = coalesce(b.utm_medium,'')
	and coalesce(td.branded,'') = coalesce(b.branded,'')
	and coalesce(td.first_update_source,'') = coalesce(b.first_update_source,'')
	and coalesce(td.flg_via_reschedule,false) = coalesce(b.flg_via_reschedule,false)