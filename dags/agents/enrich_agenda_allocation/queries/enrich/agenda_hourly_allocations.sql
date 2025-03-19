WITH agents_slots_hourly AS (
    SELECT
        ash.id_agent,
        COALESCE(CAST(DATE_FORMAT(ash.ts_slot_hour,'yyyyMMdd') AS INT), -1) AS id_slot_date,
        ash.agent_type,
        ash.day_of_week,
        ash.allocated_slots,
        ash.specific_allocated_slots,
        ash.ts_slot_hour,
        ash.year,
        ash.month,
        ash.day
    FROM
        datalake_agenda_allocation.agents_slots_hourly AS ash
    WHERE
        MAKE_DATE(ash.year, ash.month, ash.day) BETWEEN '{load_start_date}' AND ('{load_end_date}' + INTERVAL 21 DAYS)
),
first_booking AS (
    SELECT
        b.id_agent,
        MIN(b.ts_booking_utc) FILTER (WHERE b.type = 'Visita') AS ts_first_visit_booked,
        MIN(b.ts_booking_utc) FILTER (WHERE b.type IN ('Vistoria', 'VistoriaQuarteirizada')) AS ts_first_inspection_booked,
        MIN(b.ts_booking_utc) FILTER (WHERE b.type = 'SessaoFotos') AS ts_first_photo_job_booked
    FROM 
        datalake_booking.booking AS b
    WHERE
        DATE(b.ts_booking_utc) <= '{load_end_date}' + INTERVAL 21 DAYS
    GROUP BY ALL
),
agent_work_contract AS (
    SELECT 
        aud.id AS id_agent,
        aud.id_work_contract,
        aud.rev_type,
        ure.ts_revision AS ts_started,
        LEAD(ure.ts_revision) OVER (PARTITION BY aud.id, aud.id_work_contract ORDER BY ure.ts_revision) AS ts_ended
    FROM
        datalake_ebdb_clean.agent_data_aud AS aud
    JOIN 
        datalake_ebdb_user.user_revision_entity AS ure 
            ON aud.rev = ure.id
),
daily_agent_work_contract AS (
    SELECT 
        ad.date AS dt_reference,
        awc.id_agent,
        awc.id_work_contract
    FROM
        agent_work_contract AS awc
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN awc.ts_started AND COALESCE(awc.ts_ended, '{load_end_date}' + INTERVAL 21 DAYS)
    WHERE 
        awc.rev_type <> 2
        AND ad.date BETWEEN '{load_start_date}' AND '{load_end_date}' + INTERVAL 21 DAYS
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY awc.id_agent, ad.date ORDER BY awc.ts_started DESC)
),
-- A few percentage of agents has two business lines at the same period. 
-- But for the OPS team these cases should be ignored
daily_agent_business_context AS (
    SELECT 
        ad.date AS dt_reference,
        abch.id_agent_data AS id_agent,
        abch.agent_business_context
    FROM
        datalake_ebdb_agents.agent_business_context_history AS abch
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN abch.ts_agent_business_context_started AND COALESCE(abch.ts_agent_business_context_ended, '{load_end_date}' + INTERVAL 21 DAYS)
    WHERE 
        ad.date BETWEEN '{load_start_date}' AND '{load_end_date}' + INTERVAL 21 DAYS
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY abch.id_agent_data, ad.date ORDER BY abch.ts_agent_business_context_started DESC)
),
agents_region AS (
    SELECT 
        ag.id_agent,
        ag.id_region,
        ag.rev_type,
        ag.ts_revision AS ts_started,
        LEAD(ag.ts_revision) OVER (PARTITION BY ag.id_agent, ag.id_region ORDER BY ag.ts_revision) AS ts_ended
    FROM
        datalake_ebdb_agents.agents_region AS ag
),
daily_agents_region AS (
    SELECT 
        ad.date AS dt_reference,
        ag.id_agent,
        ag.id_region
    FROM
        agents_region AS ag
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN ag.ts_started AND COALESCE(ag.ts_ended, '{load_end_date}' + INTERVAL 21 DAYS)
    WHERE 
        ag.rev_type <> 2
        AND ad.date BETWEEN '{load_start_date}' AND '{load_end_date}' + INTERVAL 21 DAYS
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY ag.id_agent, ad.date ORDER BY ag.ts_started DESC)
),
daily_agent_region_group AS (
    SELECT
        arg.dadosagente_id AS id_agent,
        arg.area,
        arg.area_deprecated,
        arg.dt AS dt_reference
    FROM
        datalake_ebdb_agents.agent_region_group AS arg
    WHERE
        arg.dt BETWEEN '{load_start_date}' AND '{load_end_date}' + INTERVAL 21 DAYS
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY arg.dadosagente_id, DATE(arg.dt) ORDER BY arg.dt DESC)
)
SELECT
    ash.id_agent,
    ash.id_slot_date,
    CAST(DATE_FORMAT(ash.ts_slot_hour, 'yyyyMMddHH') AS BIGINT) AS id_slot_date_hour, 
    COALESCE(
        CAST(DATE_FORMAT(arg.dt_reference, 'yyyyMMddHH') || ash.id_agent AS BIGINT)
        , -1
    ) AS id_agent_region,
    CAST(ash.id_slot_date || ash.id_agent AS BIGINT) AS id_slot_date_agent,
    COALESCE(acr.id_work_contract, -1) AS id_work_contract,
    COALESCE(ar.id_region, -1) AS id_region,
    ash.agent_type,
    ash.allocated_slots,
    ash.specific_allocated_slots,
    abc.agent_business_context,
    COALESCE(arg.area, '-1') AS area,
    COALESCE(arg.area_deprecated, '-1') AS area_deprecated,
    COALESCE(
        CASE HOUR(ash.ts_slot_hour)
            WHEN 8 THEN mwh.has_hours_between_08_and_09_available
            WHEN 9 THEN mwh.has_hours_between_09_and_10_available
            WHEN 10 THEN mwh.has_hours_between_10_and_11_available
            WHEN 11 THEN mwh.has_hours_between_11_and_12_available
            WHEN 12 THEN mwh.has_hours_between_12_and_13_available
            WHEN 13 THEN mwh.has_hours_between_13_and_14_available
            WHEN 14 THEN mwh.has_hours_between_14_and_15_available
            WHEN 15 THEN mwh.has_hours_between_15_and_16_available
            WHEN 16 THEN mwh.has_hours_between_16_and_17_available
            WHEN 17 THEN mwh.has_hours_between_17_and_18_available
            WHEN 18 THEN mwh.has_hours_between_18_and_19_available
            WHEN 19 THEN mwh.has_hours_between_19_and_20_available
        END,
        FALSE
    ) AS is_allocation_available,
    fb.ts_first_visit_booked,
    fb.ts_first_inspection_booked,
    fb.ts_first_photo_job_booked,
    ash.ts_slot_hour,
    ash.year,
    ash.month,
    ash.day,
    NOW() AS ts_load
FROM 
    agents_slots_hourly AS ash
JOIN 
    datalake_quintoandar.aux_date AS d
        ON d.year = ash.year
        AND d.month = ash.month
        AND d.day = ash.day
LEFT JOIN 
    daily_agent_region_group AS arg
        ON arg.id_agent = ash.id_agent
        AND arg.dt_reference = d.date
LEFT JOIN 
    first_booking AS fb
        ON fb.id_agent = ash.id_agent
LEFT JOIN
    daily_agent_business_context AS abc
        ON abc.id_agent = ash.id_agent
        AND abc.dt_reference = d.date
LEFT JOIN 
    daily_agent_work_contract AS acr
        ON acr.id_agent = ash.id_agent 
        AND acr.dt_reference = d.date
LEFT JOIN 
    daily_agents_region AS ar 
        ON ar.id_agent = ash.id_agent
        AND ar.dt_reference = d.date
LEFT JOIN 
    datalake_ebdb_clean.mask_weekly_hour AS mwh
        ON mwh.id_work_contract  = acr.id_work_contract 
        AND MOD(mwh.day_of_week, 7) = MOD(d.week_day, 7)