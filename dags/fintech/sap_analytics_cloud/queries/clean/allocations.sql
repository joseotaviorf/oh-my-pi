-- TODO: confirm the date format returned by the SAC OData export. TO_DATE below
-- assumes ISO (yyyy-MM-dd); if SAC returns yyyyMMdd, add the explicit pattern as
-- done in datalake_sap_4hana_clean.journal_entries.
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
    TO_DATE(`Date`) AS dt_allocation,
    year,
    month,
    day
FROM
    datalake_sap_analytics_cloud_raw.allocations
WHERE
    MAKE_DATE(year, month, day) = '{load_end_date}'
