drop view if exists public.vw_dim_booking;

create view public.vw_dim_booking
as
with bookings as
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
	    s."fupVisita" as visit_follow_up,
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
	   	cancel_timestamp,
	   	
	   	s."criadoEm" as dt_created,
			s."atualizadoEm" as dt_updated,
			now()::timestamp as dt_timestamp
	    
	from
		public.booking s
		
	left join
		files.de_para_cancelamento d
		on d.reason = s.reason
)
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
  
  dt_created,
  dt_updated,
  dt_timestamp
   
	
from
	bookings;

/*
left join
(
	select distinct
        "reagendadoDe_id",
        id
    from
    	booking
    where
    	"reagendadoDe_id" is not null
) r
on r."reagendadoDe_id" = s."reagendadoDe_id"

left join
(
	select distinct
        "reagendadoDe_id",
        id
    from
    	booking
    where
    	"reagendadoDe_id" is not null
) r2
on r2."reagendadoDe_id" = s.id
*/

-- where  s.id in (145513, 146371, 146372)


