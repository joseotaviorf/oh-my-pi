WITH metabase_last_view AS (
    SELECT
        id_model,
        COUNT(id_model) AS views,
        MAX(ts_viewed) AS ts_last_view
    FROM
        datalake_metabase_clean.view_log
    WHERE
        DATE(ts_viewed) <= DATE(format_string('%d-%d-%d', {year}, {month}, {day}))
    GROUP BY
        id_model
),
metabase_dashboard_last_update AS (
    SELECT
        RANK() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS row_number,
        CAST(md.id AS STRING) AS id_dashboard,
        md.id_user_creator AS id_owner,
        md.id_collection,
        md.name AS title,
        md.description,
        md.id_collection,
        md.is_archived
    FROM
        datalake_metabase_clean.report_dashboard AS md
    WHERE
        DATE(ts_updated) <= DATE(format_string('%d-%d-%d', {year}, {month}, {day}))
),
metabase_dashboards AS (
    SELECT
        mdlu.id_dashboard,
        mdlu.id_owner,
        mdlu.id_collection,
        mdlu.title,
        mdlu.description,
        mdlu.is_archived,
        mdlu.id_collection
    FROM
        metabase_dashboard_last_update AS mdlu
    WHERE
        mdlu.row_number == 1
),
metabase_user_last_update AS (
    SELECT
        RANK() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS row_number,
        id AS id_user,
        email
    FROM
        datalake_metabase_clean.core_user
),
metabase_user AS (
    SELECT
        mulu.id_user,
        mulu.email
    FROM
        metabase_user_last_update AS mulu
    WHERE
        mulu.row_number == 1
),
metabase_collections_filtered AS (
    SELECT
        id AS id_collection,
        name AS name_collection,
        location
    FROM
        datalake_metabase_clean.collection
    WHERE
        id_user_personal_owner IS NULL
),
metabase_collections_exploded AS (
    SELECT
        id_collection,
        name_collection,
        EXPLODE(SPLIT(TRIM('/' FROM location), '/')) AS dir_collection_id
    FROM
        metabase_collections_filtered
),
metabase_collections AS (
    SELECT
        mce.id_collection,
        mce.name_collection,
        CONCAT_WS(
            "/",
            COLLECT_LIST(mcf.name_collection),
            mce.name_collection
        ) AS readable_location
    FROM
        metabase_collections_exploded AS mce
    JOIN
        metabase_collections_filtered AS mcf
            ON mce.dir_collection_id = mcf.id_collection
    GROUP BY
        mce.id_collection, mce.name_collection
),
metabase_dash_card AS (
    SELECT
        CAST(id_dashboard AS STRING) AS id_dashboard,
        COLLECT_LIST(CAST(id_card AS STRING)) AS ids_charts
    FROM
        datalake_metabase_clean.report_dashboard_card
    WHERE
        id_card IS NOT NULL
        AND DATE(ts_updated) <= DATE(FORMAT_STRING('%d-%d-%d', {year}, {month}, {day}))
    GROUP BY
        id_dashboard
),
metabase_dashboard_enrich AS (
    SELECT
        "metabase" AS platform,
        md.id_dashboard,
        mc.readable_location AS dashboard_path,
        md.title,
        md.description,
        lv.views,
        mu.email AS ownership,
        CASE
            WHEN mc.readable_location LIKE 'Fintech%' THEN 'Fintech'
            WHEN mc.readable_location LIKE 'Cross%' THEN 'Cross'
            WHEN mc.readable_location LIKE 'For Rent%' THEN 'For Rent'
            WHEN mc.readable_location LIKE 'For Sale%' THEN 'For Sale'
            WHEN mc.readable_location LIKE 'Growth%' THEN 'Growth'
            WHEN mc.readable_location LIKE 'International%' THEN 'International'
            WHEN mc.readable_location LIKE 'Rede%' THEN 'Rede'
            WHEN mc.readable_location LIKE 'BedRock%' THEN 'BedRock'
            WHEN mc.readable_location LIKE 'Tech Platform%' THEN 'Tech Platform'
            WHEN mc.readable_location LIKE 'Support and Services%' THEN 'Support and Services'
            WHEN mc.readable_location LIKE 'People%' THEN 'People'
            ELSE NULL
        END AS domain,
        CASE
            WHEN md.is_archived IS TRUE THEN 'DEPRECATED'
            WHEN DATEDIFF(DATE(format_string('%d-%d-%d', {year}, {month}, {day})), lv.ts_last_view) > 90 THEN 'DEPRECATED'
            ELSE 'ACTIVE'
        END AS status,
        mdc.ids_charts,
        lv.ts_last_view AS last_view,
        CONCAT(
            "https://metabase.quintoandar.com.br/dashboard/",
            md.id_dashboard
        ) AS dashboard_url,
        DATE(format_string('%d-%d-%d', {year}, {month}, {day})) AS dt_updated,
        {year} AS year,
        {month} AS month,
        {day} AS day
    FROM
        metabase_dashboards AS md
    JOIN
        metabase_user AS mu
            ON mu.id_user = md.id_owner
    JOIN
        metabase_dash_card AS mdc
            ON mdc.id_dashboard = md.id_dashboard
    JOIN
        metabase_last_view AS lv
            ON lv.id_model = md.id_dashboard
    JOIN
        metabase_collections AS mc
            ON md.id_collection = mc.id_collection
)
SELECT
    platform,
    id_dashboard,
    dashboard_path,
    title,
    description,
    views,
    ownership,
    domain,
    status,
    ids_charts,
    last_view,
    dashboard_url,
    dt_updated,
    year,
    month,
    day
FROM
    metabase_dashboard_enrich
