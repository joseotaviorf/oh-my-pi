WITH metabase_dashboards AS (
    SELECT
        ARRAY('datahub') AS vendor,
        platform,
        id_dashboard,
        dashboard_path,
        title,
        description,
        NULL AS certified_by,
        NULL AS business_owners,
        ownership AS created_by,
        ownership AS changed_by,
        domain,
        status,
        ids_charts,
        dashboard_url,
        NULL AS created_on,
        NULL AS changed_on,
        NULL as tags
    FROM
        datalake_dashboard_governance.dashboard_metadata
    WHERE
        day == {day} and month == {month} and year == {year} and platform = "metabase"
), duplicated_superset_dashboards AS (
    SELECT
        *,
        row_number() OVER(PARTITION BY id ORDER BY d.ts_changed DESC) AS row_number
    FROM
        datalake_superset.dashboards d
    WHERE
        published = true
)
SELECT
    ARRAY('datahub') AS vendor,
    platform,
    CAST(id AS STRING) AS id_dashboard,
    company_line AS dashboard_path,
    entity_name AS title,
    COALESCE(entity_description,"") AS description,
    certified_by,
    business_owners,
    technical_owner AS created_by,
    last_owner AS changed_by,
    company_line AS domain,
    entity_status AS status,
    TRANSFORM(lineage_charts, x->CAST(x AS STRING) ) AS ids_charts,
    entity_url AS dashboard_url,
    date_format(ts_created, 'yyyy-MM-dd hh:mm:ss') AS created_on,
    date_format(ts_changed, 'yyyy-MM-dd hh:mm:ss') AS changed_on,
    tags
FROM
    duplicated_superset_dashboards
WHERE
    row_number = 1
UNION ALL
SELECT
    *
FROM
    metabase_dashboards
