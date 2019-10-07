WITH
imovel_aud as (
	select
    	from_unixtime(cast(timestamp as bigint)/1000) as date_time,
		hou.*
	from datalake_ebdb_raw_prod.horariosemanalimovel_aud hou
		join datalake_ebdb_raw_prod.usuariorevisionentity ure
			on hou.rev = ure.id
),
house_available as (
	select 
		ia.imovel_id as house_id,
		ia.date_time as available_start_date,
		lead(date_time) over(partition by imovel_id, diadasemana order by rev) as available_end_date,
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
	house_id,
	to_char(available_start_date, 'YYYYMMDD')::bigint as sk_available_started_date,
	to_char(available_end_date, 'YYYYMMDD')::bigint as sk_available_ended_date,
	available_started_date,
	available_end_date,
	day_of_week,
	hours_available_08to09
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
	
