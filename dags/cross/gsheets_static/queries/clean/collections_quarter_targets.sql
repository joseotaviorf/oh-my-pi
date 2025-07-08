SELECT
    NULLIF(Active_Flow, '') AS active_flow,
    NULLIF(Active_Stock, '') AS active_stock,
    NULLIF(FPD, '') AS fpd,
    NULLIF(Property_Owners, '') AS property_owners,
    NULLIF(Ended_1_to_90, '') AS ended_1_to_90,
    NULLIF(Ended_91_to_360, '') AS ended_91_to_360,
    NULLIF(Ended_greater_360, '') AS ended_greater_360,
    NULLIF(Detractor_index, '') AS detractor_index,
    NULLIF(Active_Cushion_Effectiveness, '') AS active_cushion_effectiveness,
    NULLIF(Ended_Cushion_Effectiveness, '') AS ended_cushion_effectiveness,
    NULLIF(Resolution_Rate_120D, '') AS resolution_rate_120d,
    NULLIF(Resolution_Rate_120_to_240D, '') AS resolution_rate_120_to_240d,
    NULLIF(Resolution_Rate_greater_240D, '') AS resolution_rate_greater_240d,
    NULLIF(Resolution_Rate_240D_to_360D, '') AS resolution_rate_240d_to_360d,
    NULLIF(Resolution_Rate_greater_360D, '') AS resolution_rate_greater_360d,
    NULLIF(Resolution_Rate_MOB3, '') AS resolution_rate_mob3,
    NULLIF(Eficiencia_Processual, '') AS process_efficiency,
    NULLIF(Average_Overdue_Rent_Anomalies_greater_120, '') AS average_overdue_rent_anomalies_greater_120,
    NULLIF(TO_DATE(Date, 'yyyy-MM-dd'), '') AS dt_reference,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.collections_quarter_targets
