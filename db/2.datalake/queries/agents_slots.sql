with weekly_schedule as (
	select
		cast(hsa.atualizadoem as timestamp) as dt_update,
		agente_id as agent_id,
		diadasemana as dow,
		value as available_slot,
		key as slot_number,
		lead(cast(hsa.atualizadoem as timestamp)) over (partition by agente_id, diadasemana, key order by cast(hsa.atualizadoem as timestamp)) as dt_next_update,
		lag(value) over (partition by agente_id, diadasemana, key order by cast(hsa.atualizadoem as timestamp)) as previous_status
	from
		datalake_raw.ebdb_horariosemanalagente_aud hsa
	cross join
		unnest(
			sequence(0,47),
			array[
				horarios_disponivel08as09,horarios_disponivel08as09,horarios_disponivel08as09,horarios_disponivel08as09,
				horarios_disponivel09as10,horarios_disponivel09as10,horarios_disponivel09as10,horarios_disponivel09as10,
				horarios_disponivel10as11,horarios_disponivel10as11,horarios_disponivel10as11,horarios_disponivel10as11,
				horarios_disponivel11as12,horarios_disponivel11as12,horarios_disponivel11as12,horarios_disponivel11as12,
				horarios_disponivel12as13,horarios_disponivel12as13,horarios_disponivel12as13,horarios_disponivel12as13,
				horarios_disponivel13as14,horarios_disponivel13as14,horarios_disponivel13as14,horarios_disponivel13as14,
				horarios_disponivel14as15,horarios_disponivel14as15,horarios_disponivel14as15,horarios_disponivel14as15,
				horarios_disponivel15as16,horarios_disponivel15as16,horarios_disponivel15as16,horarios_disponivel15as16,
				horarios_disponivel16as17,horarios_disponivel16as17,horarios_disponivel16as17,horarios_disponivel16as17,
				horarios_disponivel17as18,horarios_disponivel17as18,horarios_disponivel17as18,horarios_disponivel17as18,
				horarios_disponivel18as19,horarios_disponivel18as19,horarios_disponivel18as19,horarios_disponivel18as19,
				horarios_disponivel19as20,horarios_disponivel19as20,horarios_disponivel19as20,horarios_disponivel19as20
			]
		) as t(key, value)
), specific_schedule as (
	select distinct
		agente_id as agent_id,
		cast(nullif(trim(atualizadoem),'') as timestamp) as dt_update,
		max_by(folga, cast(nullif(trim(atualizadoem),'') as timestamp)) over (partition by agente_id, "data", key) as folga,
		date_add('minute',15 * key, date_add('hour',8, cast(cast(nullif(trim("data"),'') as date) as timestamp))) as slot_dt,
		key as slot_number,
		max_by(value, cast(nullif(trim(atualizadoem),'') as timestamp)) over (partition by agente_id, "data", key) as available_slot
	from
		datalake_raw.ebdb_horarioespecificoagente_aud
	cross join
		unnest(
			sequence(0,47),
			array[
				disponivel08as09,disponivel08as09,disponivel08as09,disponivel08as09,
				disponivel09as10,disponivel09as10,disponivel09as10,disponivel09as10,
				disponivel10as11,disponivel10as11,disponivel10as11,disponivel10as11,
				disponivel11as12,disponivel11as12,disponivel11as12,disponivel11as12,
				disponivel12as13,disponivel12as13,disponivel12as13,disponivel12as13,
				disponivel13as14,disponivel13as14,disponivel13as14,disponivel13as14,
				disponivel14as15,disponivel14as15,disponivel14as15,disponivel14as15,
				disponivel15as16,disponivel15as16,disponivel15as16,disponivel15as16,
				disponivel16as17,disponivel16as17,disponivel16as17,disponivel16as17,
				disponivel17as18,disponivel17as18,disponivel17as18,disponivel17as18,
				disponivel18as19,disponivel18as19,disponivel18as19,disponivel18as19,
				disponivel19as20,disponivel19as20,disponivel19as20,disponivel19as20
			]
		) as t(key, value)
), visits as (
	select distinct
		a.agente_id as agent_id,
		date_add('minute',15 * cast(a.slotdia as integer), date_add('hour',8, cast(cast(nullif(trim(a."data"),'') as date) as timestamp))) as slot_dt
	from
		datalake_raw.ebdb_agendamento a
	left join
		datalake_raw.ebdb_agendamento_aud aa
		on aa.id = a.id
		and aa.revtype='0'
	left join
		datalake_raw.ebdb_visitaorigem vo
		on vo.id = aa.origemultimaatualizacao_id
	where a.status='Realizado' and vo.nome in ('Inquilinos', 'SelfServiceWeb')
), base_time as (
	select
    cast(date_column AS timestamp) as dt,
    dow(cast(date_column AS timestamp)) as dow,
		date_diff('minute', date_trunc('day', cast(date_column AS timestamp)) + interval '8' hour, cast(date_column AS timestamp))/15 as slot_number
	from
		(
			values(sequence(from_iso8601_date('2015-01-01'),current_date + interval '2' month, interval '15' minute))
		) AS t1(date_array)
	cross join
	    unnest(date_array) as t2(date_column)
	where
		hour(cast(date_column AS timestamp)) between 7 and 21
		and cast(date_column AS timestamp) >= cast('2017-01-01' AS timestamp)
), schedule_versions as (
	select
		agent_id,
		dt_update,
		cast(dow as bigint) as dow,
		available_slot,
		case when dt_next_update = max(dt_next_update) over ( partition by agent_id, dow, slot_number, coalesce((previous_status <> available_slot), true))
			then null
			else dt_next_update
		end as dt_next_update,
		slot_number
	from
		weekly_schedule
	where
		coalesce((previous_status <> available_slot), true) = true
), base_schedule as (
	select
		agent_id,
		su.dt_update,
		dd.dt as slot_dt,
		su.dow,
		su.slot_number,
		su.available_slot
	from
		schedule_versions su
	left join
		base_time dd
		on dd.dt > date_trunc('minute', dt_update)
		and dd.dt <= date_trunc('minute',coalesce(su.dt_next_update, current_date + interval '1' month))
		and dd.slot_number = su.slot_number
		and dd.dow = su.dow
	where
		dd.dt is not null
	order by su.dt_update, su.dow, su.slot_number
), specific_updates as (
	select
		bs.agent_id,
		bs.dt_update as last_weekly_update,
		ss.dt_update as last_specific_update,
		bs.slot_dt,
		bs.dow,
		bs.slot_number,
		bs.available_slot as weekly_slot,
		case
			when ss.folga = '1' and ss.available_slot <> bs.available_slot then '0'
			when ss.available_slot is not null and ss.available_slot <> bs.available_slot then ss.available_slot
			else bs.available_slot
		end as specific_slot,
		case
			when ss.folga = '1' and ss.available_slot <> bs.available_slot then 'day off'
			when ss.available_slot is not null and ss.available_slot <> bs.available_slot then 'specific'
			else null
		end as change_reason
	from
		base_schedule bs
	left join
		specific_schedule ss
		on bs.agent_id = ss.agent_id
		and bs.slot_dt = ss.slot_dt
	order by bs.slot_dt
), time_window_updates as (
	select
		sc.agent_id,
		sc.last_weekly_update,
		sc.last_specific_update,
		sc.slot_dt,
		sc.dow,
		sc.slot_number,
		sc.weekly_slot,
		sc.specific_slot,
		case
			when specific_slot = '1' and date_diff('hour', coalesce(last_specific_update, last_weekly_update), slot_dt) < 96
			then '0'
			else specific_slot
		end as time_window_slot,
		case
			when specific_slot = '1' and date_diff('hour', coalesce(last_specific_update, last_weekly_update), slot_dt) < 96
			then '96 hours'
			else sc.change_reason
		end as change_reason
	from
		specific_updates sc
), visits_updates as (
	select
		tw.agent_id,
		tw.last_weekly_update,
		tw.last_specific_update,
		tw.slot_dt,
		tw.dow,
		tw.slot_number,
		tw.weekly_slot,
		tw.specific_slot,
		tw.time_window_slot,
		case
			when (v.agent_id is not null) then '1'
			when lag((v.agent_id is not null)) over (partition by tw.agent_id order by tw.slot_dt) then '1'
			else tw.time_window_slot
		end as agent_slot,
		(v.agent_id is not null) as has_visit,
		case
			when (v.agent_id is not null) and tw.time_window_slot = '0' then 'visit'
			when lag((v.agent_id is not null)) over (partition by tw.agent_id order by tw.slot_dt) and tw.time_window_slot = '0' then 'visit'
			else tw.change_reason
		end as change_reason
	from
		time_window_updates tw
	left join
		visits v
		on v.agent_id = tw.agent_id
		and v.slot_dt = tw.slot_dt
), active_history_mod as (
	select distinct
		from_unixtime(cast(ure."timestamp" as bigint)/1000) as dt_status,
		coalesce(lag(ativo) over (partition by da.id order by rev)<>ativo,true) as status_mod,
		da.id,
		da.ativo as status
	from
		datalake_raw.ebdb_dadosagente_aud da
	left join
		datalake_raw.ebdb_usuario_revision_entity ure
		on da.rev = ure.id
), active_history as (
	select
		dt_status as min_version_time,
		coalesce(lead(dt_status) over (partition by id order by dt_status),date('2300-01-01')) as max_version_time,
		status,
		id as agent_id
	from
		active_history_mod ahm
	where ahm.status_mod = true
), planner_active as (
	select
		u.dadosagente_id as agent_id,
		date(available_date) as dt_active,
		count(distinct(region_name)) as _count
	from
		datalake_raw.agents_schedule a
	left join
		datalake_raw.ebdb_usuario u
		on u.id = a.agent_user_id
	where cast(available_date as date) >= date('2017-07-01')
	group by u.dadosagente_id, available_date
)
select
	vu.*,
	ah.status as history_status,
	case when pa._count > 0 then '1' else '0' end as planner_status
from
	visits_updates vu
left join
	active_history ah
	on ah.agent_id = vu.agent_id
	and vu.slot_dt between ah.min_version_time and ah.max_version_time
left join
	planner_active pa
	on pa.agent_id = vu.agent_id
	and pa.dt_active = date(slot_dt)
order by slot_dt