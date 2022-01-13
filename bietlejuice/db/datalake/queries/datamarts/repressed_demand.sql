with house_available_hours as (
	with imovel_aud as (
		select
        	from_unixtime(cast(timestamp as bigint)/1000) as date_time,
        	hou.*
		from datalake_ebdb_raw_prod.horariosemanalimovel_aud hou
			join datalake_ebdb_raw_prod.usuariorevisionentity ure
				on hou.rev = ure.id
	),
	house_available as (
		select
        	ia.imovel_id as id_house,
			ia.date_time as available_started_date,
			lead(date_time) over(partition by imovel_id, diadasemana order by rev) as available_ended_date,
			ia.diadasemana as day_of_week,
			horarios_disponivel08as09 as hours_available_08to09,
			horarios_disponivel09as10 as hours_available_09to10,
			horarios_disponivel10as11 as hours_available_10to11,
			horarios_disponivel11as12 as hours_available_11to12,
			horarios_disponivel12as13 as hours_available_12to13,
			horarios_disponivel13as14 as hours_available_13to14,
			horarios_disponivel14as15 as hours_available_14to15,
			horarios_disponivel15as16 as hours_available_15to16,
			horarios_disponivel16as17 as hours_available_16to17,
			horarios_disponivel17as18 as hours_available_17to18,
			horarios_disponivel18as19 as hours_available_18to19,
			horarios_disponivel19as20 as hours_available_19to20
		from imovel_aud ia
	)
	select
   		id_house,
		cast(replace(cast(date(available_started_date) as varchar),'-','')as bigint) as sk_available_started_date,
		cast(replace(cast(date(available_ended_date) as varchar),'-','')as bigint) as sk_available_ended_date,
		available_started_date,
		available_ended_date,
		day_of_week,
		hours_available_08to09,
		hours_available_09to10,
		hours_available_10to11,
		hours_available_11to12,
		hours_available_12to13,
		hours_available_13to14,
		hours_available_14to15,
		hours_available_15to16,
		hours_available_16to17,
		hours_available_17to18,
		hours_available_18to19,
		hours_available_19to20
	from house_available
)
, date_series as (
	select
		date(date) as date,
		cast(week_day as integer) as week_day,
		weekday_name,
		week_start,
		case 
		    when week_day = '6' then 'Saturday' 
			when week_day = '0' then 'Sunday' 
			else 'Weekday' 
		end as week_day_type
	from datalake_clean.ods_dim_date dd
	where date(date) >= date('2019-01-01') and date(week_start) <= current_date - interval '1' day
		and date != ''
)
, regions as (
	select distinct
		dr.id as region_id,
		dr.region_code,
		dr.city_group,
		dr.city_name
	from datalake_clean.ods_dim_region dr
	where dr.region_code != '-1'
)
, slot_series as (
	select slot 
	from unnest(sequence(0, 100)) seq (slot)
)
, dimensions as (
	select
	r.region_id,
	r.region_code,
	r.city_name,
	r.city_group as city_group,
	ds.date,
	ds.week_start,
	ss.slot,
	case
		when ss.slot between 0 and 3 then 8
        when ss.slot between 4 and 7 then 9
        when ss.slot between 8 and 11 then 10
        when ss.slot between 12 and 15 then 11
        when ss.slot between 16 and 19 then 12
        when ss.slot between 20 and 23 then 13
        when ss.slot between 24 and 27 then 14
        when ss.slot between 28 and 31 then 15
        when ss.slot between 32 and 35 then 16
        when ss.slot between 36 and 39 then 17
        when ss.slot between 40 and 43 then 18
	end as hour,
	case 
		when ds.week_day between 1 and 5 and ss.slot between 0 and 3 then '1) Weekday 8-9h'
        when ds.week_day between 1 and 5 and ss.slot between 4 and 19 then  '2) Weekday 9-13h'
        when ds.week_day between 1 and 5 and ss.slot between 20 and 31 then  '3) Weekday 13-16h'
        when ds.week_day between 1 and 5 and ss.slot between 32 and 35 then  '4) Weekday 16-17h'
        when ds.week_day between 1 and 5 and ss.slot between 36 and 43 then '5) Extended hours'
        when ds.week_day = 6 then '6) Saturday all hours'
		when ds.week_day = 0 then '7) Sunday all hours'
    end as faixa      		
	from regions r
      cross join date_series ds
      cross join slot_series ss
)
, encaixe_to_booking as (
	select distinct
		id_visitor as user_id,
        id_property as house_id
	from datalake_clean.ods_dim_booking
	where type = 'Visita'
		and visit_intent = 'RENT'
)
, booking_for_sale as (
	select distinct
		id_visitor as user_id,
        id_property as house_id,
        cast(slot_dia as bigint) as slot_dia,
        dt_scheduling,
        date(dt_scheduling) as visit_date,
        visit_intent,
        status
	from datalake_clean.ods_dim_booking
	where type = 'Visita'
		and visit_intent = 'SALE'
		and (status = 'Realizado' OR status = 'Marcado' OR            
                    (status = 'Cancelado' and date(dt_scheduling) = DATE(dt_cancel)))
)
, encaixes_raw as (
    select
        evt.ts_event as event_date,
        trim(evt.id_user) as user_id,
        trim(coalesce(evt.ep_house_id, null)) as house_id,
        cast(date_parse(evt.ep_alert_target_date, '%a, %d %b %Y %T GMT') as date) as target_date,
        cast(trim(evt.ep_alert_slot_from) as double) alert_slot_from,
        cast(trim(evt.ep_alert_slot_to) as double) alert_slot_to,
        case when etb.user_id is not null then 1 else 0 end as encaixe_realizado,
        rank() over (partition by trim(evt.id_user), trim(coalesce(evt.ep_house_id, '')) order by evt.ts_event desc) as rank_enc
        from datalake_amplitude_clean_prod."170698_visit_hoursalert_confirmed_events" as evt
    left join encaixe_to_booking etb on etb.user_id = CAST(trim(evt.id_user) AS bigint) and CAST(etb.house_id AS varchar) = trim(coalesce(evt.ep_house_id, ''))
    where cast(evt.year as varchar) || '-' || lpad(cast(evt.month as varchar), 2 , '0') >= '2019-01'
    	and cast(json_extract(event_properties, '$.business_context') as varchar) != 'sale'
)
, encaixes_temp as (
	select distinct
		encaixe_realizado,
		user_id,
		house_id,
		i.regiao_id as region_id,
		target_date,
		event_date,
		slot,
		1 / cast(count(slot) over (partition by enc.user_id, enc.house_id, enc.target_date) as double) as slot_share_encaixe
	from encaixes_raw enc
	left join slot_series ss on ss.slot between enc.alert_slot_from and enc.alert_slot_to
    join datalake_ebdb_raw_prod.imovel i on i.id = cast(enc.house_id as bigint)
    where enc.rank_enc = 1
    	and enc.user_id != ''
        and i.regiao_id is not null
)
, blocked_houses as (
	select 
		*
	from (
			select
            	imovel_id as house_id,
              	status,
              	from_unixtime(cast(timestamp as bigint)/1000) as init,
            	coalesce(from_unixtime(cast(lead(timestamp) over (partition by imovel_id order by timestamp)as bigint)/1000), current_date) as "end"
          	from datalake_ebdb_raw_prod.housevisitstatus_aud vs
            join datalake_ebdb_raw_prod.usuariorevisionentity r on vs.REV = r.id and status_mod = true
      	)
  where status = 'BLOCKED'
)
, suspended_houses as (
	select
		*
    from (
          	select
            	i.id as house_id,
            	status,
            	from_unixtime(cast(timestamp as bigint)/1000) as init,
            	coalesce(from_unixtime(cast(lead(timestamp) over (partition by i.id order by timestamp)as bigint)/1000), current_date) as "end"
      		from datalake_ebdb_raw_prod.imovel_aud i
      		join datalake_ebdb_raw_prod.usuariorevisionentity r 
      			on i.rev = r.id 
      			and status_mod = true
      	)
  where status = 'suspenso'
)
 -- !! NEW canceled bookings that are considered repressed demand
, cant_find_another_agent as (
	select distinct
		id_visitor as user_id,
		id_property as house_id,
		cast(slot_dia as bigint) as slot_dia,
		dt_scheduling,
		date(dt_scheduling) as visit_date,
		status
	from datalake_clean.ods_dim_booking
		where type = 'Visita'
			and status = 'Cancelado'
			and cancellation_reason = 'CANCELED_CANT_FIND_ANOTHER_AGENT'
)
, encaixes_clean as (
	select
    	region_id,
        target_date,
        slot,
        slot_share_encaixe, 
        case when encaixe_realizado = 0 and (t.event_date between bh.init and bh."end") and bh.status = 'BLOCKED' then slot_share_encaixe end as slot_share_nao_realizados_por_bloqueio,
      	case when encaixe_realizado = 0 and (t.event_date between sh.init and sh."end") and sh.status = 'suspenso' then slot_share_encaixe end as slot_share_nao_realizados_por_suspensao,
      	case when encaixe_realizado = 0 and (((t.event_date between sh.init and sh."end") and sh.status = 'suspenso') or ((t.event_date between bh.init and bh."end") and bh.status = 'BLOCKED')) then slot_share_encaixe end as slot_share_nao_realizados_por_bloqueio_suspensao,
      	case when encaixe_realizado = 1 then slot_share_encaixe end as slot_share_encaixe_realizado,
      	case when encaixe_realizado = 0 then slot_share_encaixe end as slot_share_encaixe_nao_realizado,
      	case when encaixe_realizado = 0
        	      and ((cast(slot as bigint) between  0 and  3 and hs.hours_available_08to09 = false)
        	      	or (cast(slot as bigint) between  4 and  7 and hs.hours_available_09to10 = false)
                    or (cast(slot as bigint) between  8 and 11 and hs.hours_available_10to11 = false)
                    or (cast(slot as bigint) between 12 and 15 and hs.hours_available_11to12 = false)
                    or (cast(slot as bigint) between 16 and 19 and hs.hours_available_12to13 = false)
                    or (cast(slot as bigint) between 20 and 23 and hs.hours_available_13to14 = false)
                    or (cast(slot as bigint) between 24 and 27 and hs.hours_available_14to15 = false)
                    or (cast(slot as bigint) between 28 and 31 and hs.hours_available_15to16 = false)
                    or (cast(slot as bigint) between 32 and 35 and hs.hours_available_16to17 = false)
                	or (cast(slot as bigint) between 36 and 39 and hs.hours_available_17to18 = false)
                	or (cast(slot as bigint) between 40 and 43 and hs.hours_available_18to19 = false))
        then slot_share_encaixe
        end as slot_share_nao_realizados_por_agenda,
      	case when encaixe_realizado = 0 and (((t.event_date between sh.init and sh."end") and sh.status = 'suspenso') or ((t.event_date between bh.init and bh."end") and bh.status = 'BLOCKED')
					or ((cast(slot as bigint) between  0 and  3 and hs.hours_available_08to09 = false)
                    or (cast(slot as bigint) between  4 and  7 and hs.hours_available_09to10 = false)
                    or (cast(slot as bigint) between  8 and 11 and hs.hours_available_10to11 = false)
                    or (cast(slot as bigint) between 12 and 15 and hs.hours_available_11to12 = false)
                    or (cast(slot as bigint) between 16 and 19 and hs.hours_available_12to13 = false)
                    or (cast(slot as bigint) between 20 and 23 and hs.hours_available_13to14 = false)
                    or (cast(slot as bigint) between 24 and 27 and hs.hours_available_14to15 = false)
                    or (cast(slot as bigint) between 28 and 31 and hs.hours_available_15to16 = false)
                    or (cast(slot as bigint) between 32 and 35 and hs.hours_available_16to17 = false)
					or (cast(slot as bigint) between 36 and 39 and hs.hours_available_17to18 = false)
					or (cast(slot as bigint) between 40 and 43 and hs.hours_available_18to19 = false)))
		then slot_share_encaixe end as slot_share_nao_realizados_por_bloqueio_suspensao_agenda,
		case when encaixe_realizado = 1 and cfaa.status = 'Cancelado' then slot_share_encaixe end as slot_share_nao_realizado_cant_find_another_agent,--NOVIDADE!! NOVIDADE!! NOVIDADE!! NOVIDADE!! NOVIDADE!!
        cast(hs.hours_available_08to09 as bigint) + cast(hs.hours_available_09to10 as bigint) + cast(hs.hours_available_10to11 as bigint) +
        cast(hs.hours_available_11to12 as bigint) + cast(hs.hours_available_12to13 as bigint) + cast(hs.hours_available_13to14 as bigint) +
        cast(hs.hours_available_14to15 as bigint) + cast(hs.hours_available_15to16 as bigint) + cast(hs.hours_available_16to17 as bigint) +
		cast(hs.hours_available_17to18 as bigint) + cast(hs.hours_available_18to19 as bigint) as slots_disponiveis_target_date,
		case when encaixe_realizado = 0 and visit_intent = 'SALE' then slot_share_encaixe else null end as slot_share_ocupado_por_visita_sale--NOVIDADE!! NOVIDADE!! NOVIDADE!! NOVIDADE!! NOVIDADE!!
	from encaixes_temp t
    left join house_available_hours hs
    	on cast(t.house_id as bigint) = hs.id_house
        and cast(hs.day_of_week as bigint) = dow(t.target_date)
        and t.event_date between hs.available_started_date and coalesce(hs.available_ended_date, (date_add('day',2,current_date)))
    left join blocked_houses bh
		on (cast(t.house_id as bigint) = bh.house_id
		and t.event_date between bh.init and bh."end")
	left join suspended_houses sh
    	on (cast(t.house_id as bigint) = sh.house_id
		and t.event_date between sh.init and sh."end")
	left join booking_for_sale bfs
		on cast(t.house_id as bigint) = cast(bfs.house_id as bigint)
		and t.target_date = bfs.visit_date
		and t.slot = bfs.slot_dia
	left join cant_find_another_agent cfaa
		on cast(t.house_id as bigint) = cast(cfaa.house_id as bigint)
		and t.target_date = cfaa.visit_date
		and t.slot = cfaa.slot_dia
)
, encaixes_agg as (
	select
		region_id,
        target_date,
        slot,
        sum(slot_share_encaixe) as share_encaixes_total,
        sum(coalesce(slot_share_encaixe_realizado,0) - coalesce(slot_share_nao_realizado_cant_find_another_agent,0)) as share_encaixes_realizados, -- removing referring slots from bookings cancelled with CANT FIND ANOTHER AGENT reason
        sum(coalesce(slot_share_encaixe_nao_realizado,0) + coalesce(slot_share_nao_realizado_cant_find_another_agent,0)) as share_encaixes_nao_realizados,
        sum(slot_share_nao_realizados_por_agenda) as share_encaixes_nao_realizados_por_agenda,
        sum(slot_share_nao_realizados_por_bloqueio) as share_encaixes_nao_realizados_por_bloqueio,
        sum(slot_share_nao_realizados_por_suspensao) as share_encaixes_nao_realizados_por_suspensao,
        sum(slot_share_nao_realizados_por_bloqueio_suspensao) as share_encaixes_nao_realizados_por_bloqueio_suspensao,
        sum(slot_share_nao_realizados_por_bloqueio_suspensao_agenda) as share_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
        sum(case when slots_disponiveis_target_date = 0 then slot_share_encaixe end) as encaixes_em_imovel_sem_slot_disponivel_target_date,
        sum(slot_share_ocupado_por_visita_sale) as share_encaixes_nao_realizados_por_visita_sale,
        sum(slot_share_nao_realizado_cant_find_another_agent) as share_nao_realizado_cant_find_another_agent,
        sum(coalesce(slot_share_encaixe_nao_realizado,0) + coalesce(slot_share_nao_realizado_cant_find_another_agent,0) - (coalesce(slot_share_nao_realizados_por_bloqueio_suspensao_agenda,0) + coalesce(slot_share_ocupado_por_visita_sale,0))) as share_encaixes_nao_realizados_por_agent
	from encaixes_clean
    group by 1, 2, 3
)
, bookings_raw as (
	select
		bk.id_visitor as user_id,
       	bk.id_property as house_id,
       	date(bk.dt_scheduling) as visit_date,
       	cast(bk.slot_dia as integer) as slot,
       	i.regiao_id as region_id,
       	rank() over (partition by bk.id_visitor, bk.id_property order by bk.dt_created desc) as rank_bkg
	from datalake_clean.ods_dim_booking bk
  	join datalake_ebdb_raw_prod.imovel i on i.id = cast(bk.id_property as bigint)
  	where type = 'Visita'
		and visit_intent = 'RENT'
		and cancellation_reason != 'CANCELED_CANT_FIND_ANOTHER_AGENT' -- removing all bookings that were cancelled with this reason, so we can count them as still repressed demand
)
, bookings_clean as (
	select
    	region_id,
        visit_date,
        slot,
        count(distinct CAST(user_id AS varchar) || CAST(house_id AS varchar)) as unique_bookings
    from bookings_raw
    where rank_bkg = 1
    	and user_id IS NOT NULL
        and region_id is not null
	group by 1, 2, 3
)
select
	d.region_code,
    d.city_name,
    d.city_group as city_group,
    cast(d.date as timestamp) as date,
    d.week_start,
    d.slot,
    d.hour,
    d.faixa,
    sum(unique_bookings) as sum_bookings,
    sum(enc.share_encaixes_total) as sum_encaixes,
    sum(enc.share_encaixes_realizados) as sum_encaixes_realized,
    sum(enc.share_encaixes_nao_realizados) as sum_encaixes_not_realized,
    sum(enc.share_nao_realizado_cant_find_another_agent) as sum_encaixes_nao_realizado_cant_find_another_agent,
    sum(enc.share_encaixes_nao_realizados_por_agenda) as sum_encaixes_nao_realizados_por_agenda,
    sum(enc.share_encaixes_nao_realizados_por_bloqueio) as sum_encaixes_nao_realizados_por_bloqueio,
    sum(enc.share_encaixes_nao_realizados_por_suspensao) as sum_encaixes_nao_realizados_por_suspensao,
    sum(enc.share_encaixes_nao_realizados_por_bloqueio_suspensao) as sum_encaixes_nao_realizados_por_bloqueio_suspensao,
    sum(enc.share_encaixes_nao_realizados_por_bloqueio_suspensao_agenda) as sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
    sum(enc.encaixes_em_imovel_sem_slot_disponivel_target_date) as sum_encaixes_em_imovel_sem_slot_disponivel_target_date,
    sum(enc.share_encaixes_nao_realizados_por_visita_sale) as sum_encaixes_nao_realizados_por_visita_sale,
	sum(enc.share_encaixes_nao_realizados_por_agent) as sum_encaixes_nao_realizados_por_agent
from dimensions d
left join bookings_clean bk
	on bk.region_id = cast(d.region_id as bigint)
	and bk.visit_date = d.date
    and bk.slot = d.slot
left join encaixes_agg enc
	on enc.region_id = cast(d.region_id as bigint)
    and enc.target_date = d.date
    and enc.slot = d.slot
where true
    and faixa is not null
    and coalesce(bk.slot, enc.slot) is not null
group by 1, 2, 3, 4, 5, 6, 7, 8

