WITH agents_slots_daily AS ( -- TODO [ODS] we are following ODS current structure. The table structure should be updated later
    SELECT
        sk_agent,
        sk_slot_date,
        sk_agent_region,
        sk_slot_date_agent,
        id_work_contract,
        agent_business_context,
        DAYOFWEEK(ts_slot_hour) - 1 AS day_of_week,
        area,
        ts_first_visit,
        SUM(allocated_slots) AS allocated_slots,
        SUM(allocated_slots_0) AS allocated_slots_0,
        year,
        month,
        day
    FROM
        dw_agent.fact_agent_hourly_allocations
    WHERE
        DATE(ts_slot_hour) BETWEEN DATE('{year}-{month}-{day}') AND (DATE('{year}-{month}-{day}') + INTERVAL 21 DAYS)
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 14
)
SELECT
	asd.sk_agent,
	asd.sk_slot_date,
	asd.sk_agent_region,
	asd.sk_slot_date_agent,
	asd.id_work_contract,
	CAST(asd.allocated_slots AS INT) AS allocated_slots,
	CAST(asd.allocated_slots_0 AS INT) AS allocated_slots_0,
    asd.agent_business_context,
    (
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
    ) * 4 AS max_slots_allocation_available,
	asd.area,
	ts_first_visit,
    asd.year,
    asd.month,
    asd.day,
	NOW() AS ts_load
FROM 
    agents_slots_daily asd
LEFT JOIN 
    datalake_ebdb_clean.mask_weekly_hour AS mwh
        ON mwh.id_work_contract  = asd.id_work_contract 
        AND MOD(mwh.day_of_week, 7) = MOD(asd.day_of_week, 7)