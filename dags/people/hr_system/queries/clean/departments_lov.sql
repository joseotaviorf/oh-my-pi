SELECT
    OrganizationId as id_organization,
    SetId as id_set,
    LocationId as id_location,
    Name as name,
    Title as title,
    Status as status,
    LocationCode as location_code,
    LocationName as location_name,
    SetCode as set_code,
    SetName as set_name,
    to_date(EffectiveStartDate, 'yyyy-MM-dd') AS dt_effective_start,
    to_date(EffectiveEndDate, 'yyyy-MM-dd') AS dt_effective_end,
    ts_load
FROM datalake_hr_system_raw.departments_lov