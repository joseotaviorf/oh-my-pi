with schedule_aud as (
-- Filling the missing rows in AUD with the information from the main HorarioSemanalImovel table
	select
	    coalesce(saud.id_house, ws.id_house) as id_house,
	    ws.id,
	    TIMESTAMP 'epoch' + ure.ts_revision/1000 *INTERVAL '1 second' as date_time,
    	saud.rev,
		coalesce(saud.weekday, ws.weekday) as weekday,
		coalesce(saud.is_available_between_08_and_09,ws.is_available_between_08_and_09)  as hours_available_08to09,
		coalesce(saud.is_available_between_09_and_10,ws.is_available_between_09_and_10)  as hours_available_09to10,
		coalesce(saud.is_available_between_10_and_11,ws.is_available_between_10_and_11)  as hours_available_10to11,
		coalesce(saud.is_available_between_11_and_12,ws.is_available_between_11_and_12)  as hours_available_11to12,
		coalesce(saud.is_available_between_12_and_13,ws.is_available_between_12_and_13)  as hours_available_12to13,
		coalesce(saud.is_available_between_13_and_14,ws.is_available_between_13_and_14)  as hours_available_13to14,
		coalesce(saud.is_available_between_14_and_15,ws.is_available_between_14_and_15)  as hours_available_14to15,
		coalesce(saud.is_available_between_15_and_16,ws.is_available_between_15_and_16)  as hours_available_15to16,
		coalesce(saud.is_available_between_16_and_17,ws.is_available_between_16_and_17)  as hours_available_16to17,
		coalesce(saud.is_available_between_17_and_18,ws.is_available_between_17_and_18)  as hours_available_17to18,
		coalesce(saud.is_available_between_18_and_19,ws.is_available_between_18_and_19)  as hours_available_18to19,
		coalesce(saud.is_available_between_19_and_20,ws.is_available_between_19_and_20)  as hours_available_19to20,
		ws.ts_created,
		ws.ts_updated
	from datalake_ebdb_clean_prod.house_weekly_schedule ws
	left join datalake_ebdb_clean_prod.house_weekly_schedule_aud saud
	    on saud.id = ws.id
	left join datalake_ebdb_clean_prod.user_revision_entity ure
			on saud.rev = ure.id
	-- remove lines with registries out of the 7 possible weekdays
	where coalesce(saud.weekday, ws.weekday) between 1 and 7
)
, house_default_schedule as (
-- if the house doesn't appear in house_weekly_schedule then it has the default schedule
-- 8h-19h from Monday to Friday and 8h-17h in Saturday
    with default_schedule_base as (
        select
            h.id as id_house,
            h.dt_creation
        from datalake_ebdb_clean_prod.house h
        left join schedule_aud sa
            on h.id = sa.id_house
        where
            sa.id_house is null
    )
       select
        id_house,
        dt_creation,
        1 as weekday,
        true as hours_available_08to09,
		true as hours_available_09to10,
		true as hours_available_10to11,
		true as hours_available_11to12,
		true as hours_available_12to13,
		true as hours_available_13to14,
		true as hours_available_14to15,
		true as hours_available_15to16,
		true as hours_available_16to17,
		true as hours_available_17to18,
		true as hours_available_18to19,
		false as hours_available_19to20
	from default_schedule_base
	UNION ALL
	select
        id_house,
        dt_creation,
        2 as weekday,
        true as hours_available_08to09,
		true as hours_available_09to10,
		true as hours_available_10to11,
		true as hours_available_11to12,
		true as hours_available_12to13,
		true as hours_available_13to14,
		true as hours_available_14to15,
		true as hours_available_15to16,
		true as hours_available_16to17,
		true as hours_available_17to18,
		true as hours_available_18to19,
		false as hours_available_19to20
	from default_schedule_base
	UNION ALL
	select
        id_house,
        dt_creation,
        3 as weekday,
        true as hours_available_08to09,
		true as hours_available_09to10,
		true as hours_available_10to11,
		true as hours_available_11to12,
		true as hours_available_12to13,
		true as hours_available_13to14,
		true as hours_available_14to15,
		true as hours_available_15to16,
		true as hours_available_16to17,
		true as hours_available_17to18,
		true as hours_available_18to19,
		false as hours_available_19to20
	from default_schedule_base
	UNION ALL
	select
        id_house,
        dt_creation,
        4 as weekday,
        true as hours_available_08to09,
		true as hours_available_09to10,
		true as hours_available_10to11,
		true as hours_available_11to12,
		true as hours_available_12to13,
		true as hours_available_13to14,
		true as hours_available_14to15,
		true as hours_available_15to16,
		true as hours_available_16to17,
		true as hours_available_17to18,
		true as hours_available_18to19,
		false as hours_available_19to20
	from default_schedule_base
	UNION ALL
	select
        id_house,
        dt_creation,
        5 as weekday,
        true as hours_available_08to09,
		true as hours_available_09to10,
		true as hours_available_10to11,
		true as hours_available_11to12,
		true as hours_available_12to13,
		true as hours_available_13to14,
		true as hours_available_14to15,
		true as hours_available_15to16,
		true as hours_available_16to17,
		true as hours_available_17to18,
		true as hours_available_18to19,
		false as hours_available_19to20
	from default_schedule_base
	UNION ALL
	select
        id_house,
        dt_creation,
        6 as weekday,
        true as hours_available_08to09,
		true as hours_available_09to10,
		true as hours_available_10to11,
		true as hours_available_11to12,
		true as hours_available_12to13,
		true as hours_available_13to14,
		true as hours_available_14to15,
		true as hours_available_15to16,
		true as hours_available_16to17,
		false as hours_available_17to18,
		false as hours_available_18to19,
		false as hours_available_19to20
	from default_schedule_base
	UNION ALL
	select
        id_house,
        dt_creation,
        7 as weekday,
        false as hours_available_08to09,
		false as hours_available_09to10,
		false as hours_available_10to11,
		false as hours_available_11to12,
		false as hours_available_12to13,
		false as hours_available_13to14,
		false as hours_available_14to15,
		false as hours_available_15to16,
		false as hours_available_16to17,
		false as hours_available_17to18,
		false as hours_available_18to19,
		false as hours_available_19to20
	from default_schedule_base
)
, house_available_hours as (
	select
		coalesce(sa.id_house, hd.id_house) as id_house,
		coalesce(sa.date_time, sa.ts_created, hd.dt_creation) as available_started_date,
		lead(sa.date_time) over(partition by sa.id_house, sa.weekday order by sa.rev) as available_ended_date,
		coalesce(sa.weekday, hd.weekday) as day_of_week,
		coalesce(sa.hours_available_08to09, hd.hours_available_08to09, false) as hours_available_08to09,
		coalesce(sa.hours_available_09to10, hd.hours_available_09to10, false) as hours_available_09to10,
		coalesce(sa.hours_available_10to11, hd.hours_available_10to11, false) as hours_available_10to11,
		coalesce(sa.hours_available_11to12, hd.hours_available_11to12, false) as hours_available_11to12,
		coalesce(sa.hours_available_12to13, hd.hours_available_12to13, false) as hours_available_12to13,
		coalesce(sa.hours_available_13to14, hd.hours_available_13to14, false) as hours_available_13to14,
		coalesce(sa.hours_available_14to15, hd.hours_available_14to15, false) as hours_available_14to15,
		coalesce(sa.hours_available_15to16, hd.hours_available_15to16, false) as hours_available_15to16,
		coalesce(sa.hours_available_16to17, hd.hours_available_16to17, false) as hours_available_16to17,
		coalesce(sa.hours_available_17to18, hd.hours_available_17to18, false) as hours_available_17to18,
		coalesce(sa.hours_available_18to19, hd.hours_available_18to19, false) as hours_available_18to19,
		coalesce(sa.hours_available_19to20, hd.hours_available_19to20, false) as hours_available_19to20
	from schedule_aud sa
	full outer join house_default_schedule hd
	    on hd.id_house = sa.id_house
	    and hd.weekday = sa.weekday
)
select
	id_house,
	coalesce(cast(to_char(available_started_date, 'YYYYMMDD') as bigint),-1) as sk_available_started_date,
	coalesce(cast(to_char(available_ended_date, 'YYYYMMDD') as bigint),-1) as sk_available_ended_date,
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
	hours_available_19to20,
	case when id_house is not null then
        case when hours_available_08to09 is true then 1 else 0 end + case when hours_available_09to10 is true then 1 else 0 end + case when hours_available_10to11 is true then 1 else 0 end +
        case when hours_available_11to12 is true then 1 else 0 end + case when hours_available_12to13 is true then 1 else 0 end + case when hours_available_13to14 is true then 1 else 0 end +
        case when hours_available_14to15 is true then 1 else 0 end + case when hours_available_15to16 is true then 1 else 0 end + case when hours_available_16to17 is true then 1 else 0 end +
        case when hours_available_17to18 is true then 1 else 0 end + case when hours_available_18to19 is true then 1 else 0 end + case when hours_available_19to20 is true then 1 else 0 end
    end as day_hours_available,
	current_timestamp as ts_load
from house_available_hours
