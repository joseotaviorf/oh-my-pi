SELECT
    NULLIF(DIM_Allocation, '') AS id_allocation,
    NULLIF(DIM_AllocationLine, '') AS id_allocation_line,
    NULLIF(DIM_Driver, '') AS id_driver,
    NULLIF(DIM_L3D, '') AS id_l3d,
    NULLIF(Company_Code, '') AS id_company,
    NULLIF(GL_Account_Master, '') AS id_gl_account,
    NULLIF(Profit_Center_Master_Data, '') AS id_profit_center,
    NULLIF(Order_Controlling, '') AS id_order_controlling,
    NULLIF(Supplier, '') AS id_supplier,
    NULLIF(dim_datasource, '') AS id_datasource,
    NULLIF(Version, '') AS version,
    NULLIF(Accounting_Group, '') AS accounting_group,
    NULLIF(PnL, '') AS pnl,
    NULLIF(Functional_Area, '') AS functional_area,
    NULLIF(Business, '') AS business,
    NULLIF(FSC, '') AS fsc,
    NULLIF(RDO, '') AS rdo,
    NULLIF(F_TARGET_ALLOCATION, '') AS target_allocation,
    NULLIF(F_SOURCE_ALLOCATION, '') AS source_allocation,
    K_VALUE AS value_amount,
    K_DRIVER AS driver_amount,
    K_DRIVER_ALLOCATION AS driver_allocation_amount,
    K_DRIVER_L3D AS driver_l3d_amount,
    K_DRIVER_BUSINESS AS driver_business_amount,
    K_TEMP_VALUE AS temp_value_amount,
    K_TEMP_DRIVER AS temp_driver_amount,
    K_HSL AS hsl_amount,
    K_ML1 AS ml1_amount,
    -- The model's date dimension is monthly and arrives as YYYYMM, so the
    -- pattern is explicit and the resulting date is the first of the month.
    TO_DATE(`Date`, 'yyyyMM') AS dt_allocation,
    year,
    month
FROM
    datalake_sap_analytics_cloud_raw.allocations
WHERE
    -- The raw layer is partitioned by the month the data belongs to, and each
    -- run loads one month, so the clean load reads that same month's partition.
    year = YEAR(TO_DATE('{load_end_date}'))
    AND month = MONTH(TO_DATE('{load_end_date}'))
