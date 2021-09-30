WITH agents_slots_daily AS (
    SELECT
        sk_agent,
        sk_agent_region,
        sk_agent_slot_date,
        sk_region,
        sk_slot_date,
        sk_work_contract,
        agent_type,
        DAYOFWEEK(ts_slot_hour) AS day_of_week,
        SUM(allocated_slots) AS allocated_slots,
        SUM(specific_allocated_slots) AS specific_allocated_slots,
        dt_first_inspection,
        year,
        month,
        day
    FROM
        dw_agents_availability.fact_inspector_hourly_allocations
    WHERE
        DATE(ts_slot_hour) BETWEEN DATE('{year}-{month}-{day}') AND (DATE('{year}-{month}-{day}') + INTERVAL 21 DAYS)
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 14
)
SELECT DISTINCT
    asd.sk_agent,
    asd.sk_agent_region,
    asd.sk_agent_slot_date,
    asd.sk_region,
    asd.sk_slot_date,
    asd.sk_work_contract,
    asd.agent_type,
    CAST(asd.allocated_slots AS SMALLINT) AS allocated_slots,
    CAST((
            COALESCE(CAST(mwh.has_hours_between_08_and_09_available AS INTEGER), 0)
            + COALESCE(CAST(mwh.has_hours_between_09_and_10_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_10_and_11_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_11_and_12_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_12_and_13_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_13_and_14_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_14_and_15_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_15_and_16_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_16_and_17_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_17_and_18_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_18_and_19_available AS INTEGER),0)
            + COALESCE(CAST(mwh.has_hours_between_19_and_20_available AS INTEGER),0)
    )*4 AS SMALLINT) AS max_slots_allocation_available,
    CAST(asd.specific_allocated_slots AS SMALLINT) AS specific_allocated_slots,
    asd.dt_first_inspection,
    asd.year,
    asd.month,
    asd.day,
    NOW() AS ts_load 
FROM
    agents_slots_daily asd
LEFT JOIN 
    datalake_ebdb_clean.mask_weekly_hour AS mwh
        ON mwh.id_work_contract  = asd.sk_work_contract 
        AND MOD(mwh.day_of_week, 7) = MOD(asd.day_of_week, 7)