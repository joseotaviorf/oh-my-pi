WITH schedule AS
(SELECT
	t.agent_id AS sk_agent,
	COALESCE(to_char(t.slot_dt::DATE,'YYYYMMDD')::INTEGER, -1) AS sk_slot_date,
	date_trunc('h', t.slot_dt) AS ts_slot_hour,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t.available_slot_24h AS INTEGER) else 0 end) AS allocated_slots,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t.specific_slot AS INTEGER) else 0 end) AS allocated_slots_0
 FROM agent.agents_slots t
 WHERE DATE(t.slot_dt) = DATE('{0}') and t.agent_type = 'Visita'
GROUP BY 1, 2, 3
),
first_visits AS
(SELECT
	id_agent,
	min(dt_scheduling) as ts_first_visit
 FROM public.dim_booking db
 WHERE db.type = 'Visita'
 GROUP BY id_agent
),
agent_contract_rank AS (
SELECT
		*,
		RANK() OVER (PARTITION BY agent_id ORDER BY "timestamp" DESC) AS "rank"
	FROM agent.agent_contract
	WHERE "timestamp" <= CAST('{0}' AS TIMESTAMP)
)
SELECT
	s.sk_agent,
	s.sk_slot_date,
	to_char(s.ts_slot_hour,'YYYYMMDDHH24') as sk_slot_date_hour,
	COALESCE(a.sk_agent_region, -1) AS sk_agent_region,
	CAST(CAST(s.sk_date AS VARCHAR) + CAST(s.sk_agent_id AS VARCHAR) AS BIGINT) as sk_slot_date_agent,
	COALESCE(acr.workcontract_id, -1) as sk_contract_type,
	s.ts_slot_hour,
	s.allocated_slots,
	s.allocated_slots_0,
	CASE d.week_day
		WHEN 0 THEN 0	                           -- Sunday
		WHEN 6 THEN                                -- Saturday
            CASE date_part('h', s.slot_hour_ts)
                WHEN  9 THEN coalesce(cast(achd.is_saturday_available_at_09 as integer),0)
                WHEN 10 THEN coalesce(cast(achd.is_saturday_available_at_10 as integer),0)
                WHEN 11 THEN coalesce(cast(achd.is_saturday_available_at_11 as integer),0)
                WHEN 12 THEN coalesce(cast(achd.is_saturday_available_at_12 as integer),0)
                WHEN 13 THEN coalesce(cast(achd.is_saturday_available_at_13 as integer),0)
            END
		ELSE                                       -- Weekdays
		    CASE date_part('h', s.slot_hour_ts)
		        WHEN  8 THEN coalesce(cast(achd.is_weekday_available_at_08 as integer),0)
		        WHEN  9 THEN coalesce(cast(achd.is_weekday_available_at_09 as integer),0)
		        WHEN 10 THEN coalesce(cast(achd.is_weekday_available_at_10 as integer),0)
		        WHEN 11 THEN coalesce(cast(achd.is_weekday_available_at_11 as integer),0)
		        WHEN 12 THEN coalesce(cast(achd.is_weekday_available_at_12 as integer),0)
		        WHEN 13 THEN coalesce(cast(achd.is_weekday_available_at_13 as integer),0)
		        WHEN 14 THEN coalesce(cast(achd.is_weekday_available_at_14 as integer),0)
		        WHEN 15 THEN coalesce(cast(achd.is_weekday_available_at_15 as integer),0)
		        WHEN 16 THEN coalesce(cast(achd.is_weekday_available_at_16 as integer),0)
		        ELSE 0
		    END
	END = 1 AS is_allocation_available,
	COALESCE(a.area, '-1') AS area,
	ts_first_visit,
	getdate() as ts_load
FROM schedule s
JOIN public.dim_date d
	ON d.sk_date = s.sk_date
LEFT JOIN public.dim_agent_region a
	ON a.sk_regions_date = s.sk_date
		AND a.sk_agent = s.sk_agent_id
LEFT JOIN first_visits fv
	ON fv.id_agent = s.sk_agent_id
LEFT JOIN agent_contract_rank acr
    ON acr.agent_id = s.sk_agent_id AND acr."rank" = 1
LEFT JOIN datalake_raw.agent_contract_hours achd
    ON cast(achd.id as integer) = acr.workcontract_id
ORDER BY s.sk_date;