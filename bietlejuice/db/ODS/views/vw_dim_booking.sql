drop view if exists public.vw_dim_booking;

create or replace view public.vw_dim_booking
as
with bms as (
    select
        row_number() over(partition by bms.visita_id order by bms.event_time) as rn,
        bms.*
    from public.booking_media_sources bms
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
        s.checkin_status
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
),
taxonomy_flow as
(
select
	sk_booking,
	id_booking,
	valid_bookings_not_rescheduled,
	dt_booking,
	type,
	confirmed,
	closed,
	visit_follow_up,
	dt_visit_follow_up,
	rescheduled_from_id,
	id_visitor,
	id_visit,
	id_property,
	id_agent,
	id_attendant,
	id_rental_flow,
	status,
	slot_dia,
	reason,
	coalesce
	(
		nullif(reason_category, 'Other'), 
		'Unknown'
	) as reason_category,
	case 
		when nullif(responsible, 'Other') is null then 'Unknown'
		when responsible = 'Agent' then 'QuintoAndar'
		else responsible
	end as responsible,
	app_type,
  	media_source,
  	adjust_network,
  	utm_source,
  	utm_medium,
  	utm_campaign,
	cancel_timestamp,
	dt_created,
	dt_updated,
	dt_timestamp,
	last_update_source,
	first_update_source,
	visitor_arrived,
    visitor_missing_reason,
    agent_arrived,
    agent_missing_reason,
    owner_arrived,
    owner_missing_reason,
    successful_entrance,
    troublesome_entrance,
    checkin_status,
    -- Demand Taxonomy
    case when UPPER(utm_campaign) like '%BRANDED%' or UPPER(utm_campaign) like '%INSTITUCIONAL%' then true
    	else false
    end as flg_branded,
    (rescheduled_from_id IS NOT NULL) as flg_via_reschedule,
	cast('Inbound' as varchar(10)) as mkt_category,
    case when lower(first_update_source) in ('admin', 'corretores') then 'Non Self-Service'
    	 when lower(first_update_source) in ('cidadealerta', 'inquilinos', 'proprietarios', 'selfserviceweb') then 'Self-Service'
    	 else 'Other'
    end as mkt_flow
from
	bookings
),
taxonomy_channel_type as
(
select
	*,
	case when mkt_flow = 'Self-Service' then 'Full Self-Service'
    	 else mkt_flow
    end as mkt_completion,
    case when mkt_flow in ('Non Self-Service', 'Other') then null
    	 when lower(app_type) = 'ios' then 'App iOS'
    	 when lower(app_type) = 'android' then 'App Android'
    	 when lower(app_type) = 'web_desktop' then 'Web Desktop'
    	 when lower(app_type) = 'web_mobile' then 'Web Mobile'
    	 when app_type is null then 'Lost Tracking'
    	 else 'Other'
    end as mkt_device,
    case when lower(first_update_source) = 'corretores' then 'Agents'
    	 when mkt_flow in ('Non Self-Service', 'Other') then 'Other'
    	 -- Configuring Others - Lost Tracking
    	 when lower(utm_source) = 'landing_prop' or lower(utm_medium) = 'header' then 'Other'
    	 when flg_branded and app_type is null then 'Other'
    	 when app_type is null and utm_source is null and utm_medium is null then 'Other'
    	 -- Configuring Classifieds and one exception to Organics
    	 when utm_medium like ('classified%') then 'Online Classifieds'
    	 when lower(utm_medium) = 'cpc' and lower(utm_source) in ('mitulagroup', 'trovit', 'zap', 'vivareal') then 'Online Classifieds'
    	 when lower(utm_medium) = 'email' and lower(utm_source) in ('email', 'quintoandar', 'emkt_visita') then 'Organic'
    	 when lower(utm_medium) = 'email' then 'Online Classifieds'
    	 -- Configuring Online Paid
    	 when lower(utm_source) in ('facebook_post', 'email') then 'Organic'
    	 when flg_branded and lower(utm_medium) = 'retargeting' then 'Online Paid'
    	 when flg_branded and lower(utm_medium) = 'cpc' then 'Organic'
    	 when not flg_branded and lower(utm_medium) in ('cpc', 'display', 'remarketing', 'retargeting') then 'Online Paid'
    	 when not flg_branded and utm_medium is null and utm_source = 'google' then 'Online Paid'
    	 -- Configuring Organics
    	 when not flg_branded and utm_medium is null and utm_source is null then 'Organic'
    	 when lower(utm_source) = 'alerta' then 'Organic'
    	 when lower(utm_source) like 'facebook%' then 'Organic'
    	 else 'Other'
    end as mkt_channel_type
from
	taxonomy_flow
),
 taxonomy_channel as
 (
select
	*,
	case
		when lower(mkt_channel_type) in ('agents', 'online classifieds') then mkt_channel_type
		when lower(mkt_channel_type) = 'organic' and utm_source is null then 'Direct'
		when lower(utm_medium) = 'display' then 'Display'
		when lower(utm_source) in ('alerta', 'email', 'emkt_visita', 'quintoandar') then 'Notifications'
		when lower(mkt_channel_type) = 'organic' and lower(utm_medium) = 'cpc' and flg_branded then 'SEM branded'
		when lower(mkt_channel_type) = 'online paid' and lower(coalesce(utm_medium, 'cpc')) = 'cpc' and coalesce(utm_source, '') in ('', 'bing', 'google') then 'SEM non-branded'
		when lower(mkt_channel_type) = 'organic' and lower(utm_source) like 'facebook%' then 'Social'
		when lower(mkt_channel_type) = 'online paid' and lower(utm_medium) in ('cpc', 'remarketing', 'retargeting') then 'Retargeting'
		-- Configuring Others
		when lower(mkt_channel_type) = 'other' and lower(first_update_source) in ('admin', 'cidadealerta', 'inquilinos', 'proprietarios', 'selfserviceweb') then 'Lost Tracking'
		when lower(mkt_channel_type) = 'other' and lower(coalesce(first_update_source, '')) in ('', 'proprietariosemail', 'sistema') then 'Other'
		else 'Other'
	end as mkt_channel
from
	taxonomy_channel_type
)
select
	*,
	case
		when lower(first_update_source) = 'admin' and lower(mkt_channel) = 'lost tracking' then 'CX'
		else mkt_channel
	end as mkt_medium,
	case
		when lower(first_update_source) = 'admin' and lower(mkt_channel) = 'lost tracking' then 'CX'
		when lower(mkt_channel) in ('agents', 'direct', 'lost tracking', 'other', '') then mkt_channel
		when lower(utm_source) like 'fac%' then 'Facebook'
		when lower(utm_source) like 'google%' then 'Google'
		when lower(utm_source) in ('emkt_visita', 'quintoandar') then 'Non-subscribed'
		when lower(utm_source) in ('alerta', 'email') then 'Subscribed'
		when lower(mkt_channel) in ('sem branded', 'sem non-branded') then initcap(coalesce(utm_source,'google'))
		when lower(utm_source) like ('ads%') then 'Other'
		when lower(utm_source) in ('imovelweb') then initcap(utm_source)
		when right(lower(utm_source), 1) = 'b' then initcap(regexp_replace(lower(utm_source), 'b$', ''))
		when utm_source is not null then initcap(utm_source)
		when utm_source is null then 'Other'
		else 'Other'
	end as mkt_source
from
	taxonomy_channel;
