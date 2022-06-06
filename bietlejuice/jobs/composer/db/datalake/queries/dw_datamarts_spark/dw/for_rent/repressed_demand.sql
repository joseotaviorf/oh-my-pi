with house_available_hours as (
	with imovel_aud as (
		select
        	ure.ts_revision as date_time,
        	hou.*
		from datalake_ebdb_clean.house_weekly_schedule_aud hou
			join datalake_ebdb_user_revision_entity.user_revision_entity ure
				on hou.rev = ure.id
	),
 	house_available as (
		select
        	ia.*,
            ia.date_time as available_started_date,
			lead(date_time) over(partition by ia.id_house, ia.weekday order by ia.rev) as available_ended_date
		from imovel_aud ia
 	)
	select
   		id_house,
		cast(replace(cast(date(available_started_date) as string),'-','') as bigint) as sk_available_started_date,
		cast(replace(cast(date(available_ended_date) as string),'-','') as bigint) as sk_available_ended_date,
		available_started_date,
		available_ended_date,
		weekday, -- (1-mon/7-sun)
        case when weekday = 7 then 1 -- adjust sunday to 1
             when weekday = 0 then 0 -- do not add 1 to problematic rows
             else weekday + 1 end -- adjust all others by adding 1
        as adapted_weekday, -- (1-sun/7-sat)
		is_available_between_08_and_09,
		is_available_between_09_and_10,
		is_available_between_10_and_11,
		is_available_between_11_and_12,
		is_available_between_12_and_13,
		is_available_between_13_and_14,
		is_available_between_14_and_15,
		is_available_between_15_and_16,
		is_available_between_16_and_17,
		is_available_between_17_and_18,
		is_available_between_18_and_19,
		is_available_between_19_and_20
	from house_available
),
date_series as (
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
	from dw_public.dim_date dd
	where date(date) >= date('2019-01-01') and date(week_start) <= current_date - interval '1' day
		and date is not null
)
, regions as (
	select distinct
		dr.id as region_id,
		dr.region_code,
		dr.city_group,
		dr.city_name
	from dw_public.dim_region dr
	where dr.region_code <> '-1'
)
, slot_series as (
      select explode(sequence(0, 100)) as slot
)
, dimensions as (
	select
	r.region_id,
	r.region_code,
	r.city_name,
	r.city_group,
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
	from dw_public.dim_booking
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
	from dw_public.dim_booking
	where type = 'Visita'
		and visit_intent = 'SALE'
		and (status = 'Realizado'
          or status = 'Marcado'
          or (status = 'Cancelado' and date(dt_scheduling) = date(dt_cancel))
        )
)
, encaixes_raw as (
    select
        evt.ts_event as event_date,
        trim(evt.id_user) as user_id,
        trim(coalesce(evt.ep_house_id, null)) as house_id,
        coalesce(
          to_date(substr(ep_alert_target_date FROM 6), "dd MMM yyyy HH:mm:ss 'GMT'"),
          date(ep_alert_target_date)
        ) as target_date,
        cast(trim(evt.ep_alert_slot_from) as double) alert_slot_from,
        cast(trim(evt.ep_alert_slot_to) as double) alert_slot_to,
        case when etb.user_id is not null then 1 else 0 end as encaixe_realizado,
        rank() over (partition by trim(evt.id_user), trim(coalesce(evt.ep_house_id, '')) order by evt.ts_event desc) as rank_enc
    from datalake_amplitude_clean.170698_visit_hoursalert_confirmed_events as evt
    left join encaixe_to_booking etb
      on etb.user_id = CAST(trim(evt.id_user) AS bigint)
      and CAST(etb.house_id AS string) = trim(coalesce(evt.ep_house_id, ''))
    where cast(evt.year as string) || '-' || lpad(cast(evt.month as string), 2 , '0') >= '2019-01'
    	and ep_business_context != 'sale'
)
, encaixes_temp as (
	select distinct
		encaixe_realizado,
		user_id,
		house_id,
		h.id_region,
		target_date,
		event_date,
		slot,
		1 / cast(count(slot) over (partition by enc.user_id, enc.house_id, enc.target_date) as double) as slot_share_encaixe
	from encaixes_raw enc
	left join slot_series ss on ss.slot between enc.alert_slot_from and enc.alert_slot_to
    join datalake_ebdb_clean.house h on h.id = cast(enc.house_id as bigint)
    where enc.rank_enc = 1
    	and enc.user_id != ''
        and h.id_region is not null
)
, blocked_houses as (
	select
		*
	from (
			select
                id_house,
                status,
                ure.ts_revision as init_rev,
                coalesce(lead(ts_revision) over (partition by id_house order by ts_revision), current_date) as end_rev
            from datalake_ebdb_clean.house_visit_status_aud vs
                join datalake_ebdb_user_revision_entity.user_revision_entity ure
                    on vs.rev = ure.id
                    and mod_status = true
      	)
    where status = 'BLOCKED'
)
, suspended_houses as (
	select
		*
    from (
          	select
                id_house,
                status,
                ure.ts_revision as init_rev,
                coalesce(lead(ts_revision) over (partition by id_house order by ts_revision), current_date) as end_rev
            from datalake_ebdb_clean.house_aud vs
                join datalake_ebdb_user_revision_entity.user_revision_entity ure
                    on vs.rev = ure.id
                    and mod_status = true
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
	from dw_public.dim_booking
		where type = 'Visita'
			and status = 'Cancelado'
			and cancellation_reason = 'CANCELED_CANT_FIND_ANOTHER_AGENT'
)
, encaixes_clean as (
	select
    	t.id_region as region_id,
        t.target_date,
        t.slot,
        t.slot_share_encaixe,
        case when encaixe_realizado = 0 and (t.event_date between bh.init_rev and bh.end_rev) and bh.status = 'BLOCKED' then t.slot_share_encaixe end as slot_share_nao_realizados_por_bloqueio,
      	case when encaixe_realizado = 0 and (t.event_date between sh.init_rev and sh.end_rev) and sh.status = 'suspenso' then t.slot_share_encaixe end as slot_share_nao_realizados_por_suspensao,
      	case when encaixe_realizado = 0 and (((t.event_date between sh.init_rev and sh.end_rev) and sh.status = 'suspenso') or ((t.event_date between bh.init_rev and bh.end_rev) and bh.status = 'BLOCKED')) then t.slot_share_encaixe end as slot_share_nao_realizados_por_bloqueio_suspensao,
      	case when encaixe_realizado = 1 then t.slot_share_encaixe end as slot_share_encaixe_realizado,
      	case when encaixe_realizado = 0 then t.slot_share_encaixe end as slot_share_encaixe_nao_realizado,
      	case when encaixe_realizado = 0
        	      and ((cast(slot as bigint) between  0 and  3 and hs.is_available_between_08_and_09 = false)
        	      	or (cast(slot as bigint) between  4 and  7 and hs.is_available_between_09_and_10 = false)
                    or (cast(slot as bigint) between  8 and 11 and hs.is_available_between_10_and_11 = false)
                    or (cast(slot as bigint) between 12 and 15 and hs.is_available_between_11_and_12 = false)
                    or (cast(slot as bigint) between 16 and 19 and hs.is_available_between_12_and_13 = false)
                    or (cast(slot as bigint) between 20 and 23 and hs.is_available_between_13_and_14 = false)
                    or (cast(slot as bigint) between 24 and 27 and hs.is_available_between_14_and_15 = false)
                    or (cast(slot as bigint) between 28 and 31 and hs.is_available_between_15_and_16 = false)
                    or (cast(slot as bigint) between 32 and 35 and hs.is_available_between_16_and_17 = false)
                	or (cast(slot as bigint) between 36 and 39 and hs.is_available_between_17_and_18 = false)
                	or (cast(slot as bigint) between 40 and 43 and hs.is_available_between_18_and_19 = false))
          then t.slot_share_encaixe end as slot_share_nao_realizados_por_agenda,
      	case when encaixe_realizado = 0 and (((t.event_date between sh.init_rev and sh.end_rev) and sh.status = 'suspenso') or ((t.event_date between bh.init_rev and bh.end_rev) and bh.status = 'BLOCKED')
					or ((cast(slot as bigint) between  0 and  3 and hs.is_available_between_08_and_09 = false)
                    or (cast(slot as bigint) between  4 and  7 and hs.is_available_between_09_and_10 = false)
                    or (cast(slot as bigint) between  8 and 11 and hs.is_available_between_10_and_11 = false)
                    or (cast(slot as bigint) between 12 and 15 and hs.is_available_between_11_and_12 = false)
                    or (cast(slot as bigint) between 16 and 19 and hs.is_available_between_12_and_13 = false)
                    or (cast(slot as bigint) between 20 and 23 and hs.is_available_between_13_and_14 = false)
                    or (cast(slot as bigint) between 24 and 27 and hs.is_available_between_14_and_15 = false)
                    or (cast(slot as bigint) between 28 and 31 and hs.is_available_between_15_and_16 = false)
                    or (cast(slot as bigint) between 32 and 35 and hs.is_available_between_16_and_17 = false)
					or (cast(slot as bigint) between 36 and 39 and hs.is_available_between_17_and_18 = false)
					or (cast(slot as bigint) between 40 and 43 and hs.is_available_between_18_and_19 = false)))
          then t.slot_share_encaixe end as slot_share_nao_realizados_por_bloqueio_suspensao_agenda,
		case when encaixe_realizado = 1 and cfaa.status = 'Cancelado' then t.slot_share_encaixe end as slot_share_nao_realizado_cant_find_another_agent,
        cast(hs.is_available_between_08_and_09 as bigint) +
          cast(hs.is_available_between_09_and_10 as bigint) +
          cast(hs.is_available_between_10_and_11 as bigint) +
          cast(hs.is_available_between_11_and_12 as bigint) +
          cast(hs.is_available_between_12_and_13 as bigint) +
          cast(hs.is_available_between_13_and_14 as bigint) +
          cast(hs.is_available_between_14_and_15 as bigint) +
          cast(hs.is_available_between_15_and_16 as bigint) +
          cast(hs.is_available_between_16_and_17 as bigint) +
          cast(hs.is_available_between_17_and_18 as bigint) +
          cast(hs.is_available_between_18_and_19 as bigint) as slots_disponiveis_target_date,
		case when encaixe_realizado = 0 and visit_intent = 'SALE' then slot_share_encaixe else null end as slot_share_ocupado_por_visita_sale
	from encaixes_temp t
    left join house_available_hours hs
    	on cast(t.house_id as bigint) = hs.id_house
        and cast(hs.adapted_weekday as bigint) = dayofweek(t.target_date)
        and t.event_date between hs.available_started_date and coalesce(hs.available_ended_date, (date_add(current_date,2)))
    left join blocked_houses bh
		on (cast(t.house_id as bigint) = bh.id_house
		and t.event_date between bh.init_rev and bh.end_rev)
	left join suspended_houses sh
    	on (cast(t.house_id as bigint) = sh.id_house
		and t.event_date between sh.init_rev and sh.end_rev)
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
       	h.id_region as region_id,
       	rank() over (partition by bk.id_visitor, bk.id_property order by bk.dt_created desc) as rank_bkg
	from dw_public.dim_booking bk
  	join datalake_ebdb_clean.house h on h.id = cast(bk.id_property as bigint)
  	where bk.type = 'Visita'
		and visit_intent = 'RENT'
		and (cancellation_reason IS NULL OR cancellation_reason != 'CANCELED_CANT_FIND_ANOTHER_AGENT') -- removing all bookings that were cancelled with this reason, so we can count them as still repressed demand
)
, bookings_clean as (
	select
    	region_id,
        visit_date,
        slot,
        count(distinct CAST(user_id AS string) || CAST(house_id AS string)) as unique_bookings
    from bookings_raw
    where rank_bkg = 1
    	and user_id IS NOT NULL
        and region_id is not null
	group by 1, 2, 3
)
select
	CAST(d.region_code AS string) AS region_code,
    CAST(d.city_name AS string) AS city_name,
    CAST(d.city_group AS string) AS city_group,
    CAST(date_format(cast(d.date as timestamp), 'yyyy-MM-dd HH:mm:ss.SSS') as string) AS date,
    CAST(d.week_start AS string) AS week_start,
    CAST(d.slot AS string) AS slot,
    CAST(d.hour AS string) AS hour,
    CAST(d.faixa AS string) AS faixa,
    CAST(sum(unique_bookings) AS string) as sum_bookings,
    CAST(sum(enc.share_encaixes_total) AS string) as sum_encaixes,
    CAST(sum(enc.share_encaixes_realizados) AS string) as sum_encaixes_realized,
    CAST(sum(enc.share_encaixes_nao_realizados) AS string) as sum_encaixes_not_realized,
    CAST(sum(enc.share_nao_realizado_cant_find_another_agent) AS string) as sum_encaixes_nao_realizado_cant_find_another_agent,
    CAST(sum(enc.share_encaixes_nao_realizados_por_agenda) AS string) as sum_encaixes_nao_realizados_por_agenda,
    CAST(sum(enc.share_encaixes_nao_realizados_por_bloqueio) AS string) as sum_encaixes_nao_realizados_por_bloqueio,
    CAST(sum(enc.share_encaixes_nao_realizados_por_suspensao) AS string) as sum_encaixes_nao_realizados_por_suspensao,
    CAST(sum(enc.share_encaixes_nao_realizados_por_bloqueio_suspensao) AS string) as sum_encaixes_nao_realizados_por_bloqueio_suspensao,
    CAST(sum(enc.share_encaixes_nao_realizados_por_bloqueio_suspensao_agenda) AS string) as sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
    CAST(sum(enc.encaixes_em_imovel_sem_slot_disponivel_target_date) AS string) as sum_encaixes_em_imovel_sem_slot_disponivel_target_date,
    CAST(sum(enc.share_encaixes_nao_realizados_por_visita_sale) AS string) as sum_encaixes_nao_realizados_por_visita_sale,
	CAST(sum(enc.share_encaixes_nao_realizados_por_agent) AS string) as sum_encaixes_nao_realizados_por_agent,
	MAX(CAST(NOW() AS string)) AS ts_load
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
