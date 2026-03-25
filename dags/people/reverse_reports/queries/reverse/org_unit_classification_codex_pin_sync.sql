SELECT
    'MERGE' AS METADATA,
    'OrgUnitClassification' AS OrgUnitClassification,
    date_format(CURRENT_DATE(), 'yyyy/MM/dd') AS EffectiveStartDate,
    '4712/12/31' AS EffectiveEndDate,
    pin_organization_name AS OrganizationName,
    'DEPARTMENT' AS ClassificationName,
    'DEPARTMENT' AS ClassificationCode,
    pin_organization_status AS Status,
    'COMMON' AS SetCode,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    datalake_people.codex_pin_sync_drift
WHERE
    is_any_drift
ORDER BY
    OrganizationName
