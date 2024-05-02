WITH organizations AS (
  SELECT 
    OrganizationId,
    OrganizationDFF
  FROM datalake_hr_system_raw.organizations
), organization_dff_step1 AS (
  SELECT 
    OrganizationId,
    explode(OrganizationDFF) AS organization_dff
  FROM organizations 
), organization_dff AS (
  SELECT
    OrganizationId,
    organization_dff['EffectiveStartDate'] dt_effective_start_dff,
    organization_dff['EffectiveEndDate'] dt_effective_end_dff,
    organization_dff['codigo'] AS codigo_dff,
    organization_dff['business'] AS business,
    organization_dff['product'] AS product,
    organization_dff['vertical'] AS vertical,
    organization_dff['vicePresidencia'] AS vice_presidency,
    organization_dff['diretoria'] AS directory,
    organization_dff['subDiretoria'] AS sub_directory
  FROM organization_dff_step1
)
SELECT 
    -- ids
    o.OrganizationId AS id_organization,
    o.LocationIdLOV AS id_location_lov,
    o.LocationId AS id_location,
    -- non-metrics
    o.name,
    o.title,
    o.OrganizationCode AS organization_code,
    o.status,
    o.OrgCode AS org_code,
    o.OrgClassificationVA AS organization_classification_va,
    o.StatusLOV AS status_lov,
    o.ClassificationCode AS classification_code,
    o.InternalAddressLine AS internal_address_line,
    odff.codigo_dff,
    odff.business,
    odff.product,
    odff.vertical,
    odff.vice_presidency,
    odff.directory,
    odff.sub_directory,
    -- Nested Fields
    o.OrganizationDFF AS organization_dff,
    o.extraInformation AS extra_information,
    -- dates
    to_date(o.EffectiveStartDate, 'yyyy-MM-dd') AS dt_effective_start,
    to_date(o.EffectiveEndDate, 'yyyy-MM-dd') AS dt_effective_end,
    to_date(odff.dt_effective_start_dff, 'yyyy-MM-dd') AS dt_effective_start_dff,
    to_date(odff.dt_effective_end_dff, 'yyyy-MM-dd') AS dt_effective_end_dff,
    -- timestamps
    to_timestamp(substr(replace(o.CreationDate, 'T', ' '), 0, 19), 'yyyy-MM-dd HH:mm:ss') AS ts_created,
    to_timestamp(substr(replace(o.LastUpdateDate, 'T', ' '), 0, 19), 'yyyy-MM-dd HH:mm:ss') AS ts_last_update,
    o.ts_load,
    -- partitions
    o.year,
    o.month,
    o.day
FROM datalake_hr_system_raw.organizations AS o
LEFT JOIN organization_dff AS  odff
  ON o.OrganizationId = odff.OrganizationId