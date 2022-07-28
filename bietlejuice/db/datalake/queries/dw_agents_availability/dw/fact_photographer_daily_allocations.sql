WITH photographer_slots_daily AS ( -- TODO [ODS] we are following ODS current structure. The table structure should be updated later
    SELECT
        sk_agent,
        sk_slot_date,
        sk_agent_region,
        sk_slot_date_agent,
        id_work_contract,
        DAYOFWEEK(ts_slot_hour) - 1 AS day_of_week,
        id_dados_fotografo,
        area,
        SUM(allocated_slots) AS allocated_slots,
        SUM(allocated_slots_0) AS allocated_slots_0,
        year,
        month,
        day
    FROM
        dw_agent.fact_photographer_hourly_allocations
    WHERE
        DATE(ts_slot_hour) BETWEEN DATE('{year}-{month}-{day}') AND (DATE('{year}-{month}-{day}') + INTERVAL 21 DAYS)
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13
)
SELECT
    psd.sk_agent,
    psd.sk_slot_date,
    psd.sk_agent_region,
    psd.sk_slot_date_agent,
    psd.id_work_contract,
    psd.id_dados_fotografo,
	CAST(psd.allocated_slots AS INT) AS allocated_slots,
	CAST(psd.allocated_slots_0 AS INT) AS allocated_slots_0,
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
    psd.area,
    psd.year,
    psd.month,
    psd.day,
    NOW() as ts_load
FROM 
    photographer_slots_daily psd
LEFT JOIN 
    datalake_ebdb_clean.mask_weekly_hour AS mwh
        ON mwh.id_work_contract  = psd.id_work_contract 
          AND MOD(mwh.day_of_week, 7) = MOD(psd.day_of_week, 7)