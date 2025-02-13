WITH metabase_last_view AS (
    SELECT
        id_model,
        MAX(ts_viewed) AS ts_last_view
    FROM
        datalake_metabase_clean.view_log
    GROUP BY
        id_model
),
window_chart AS (
    SELECT
        RANK() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS row_number,
        chart.id AS id_chart,
        chart.id_user_creator AS id_owner,
        chart.id_database,
        chart.id_table,
        chart.id_collection,
        chart.name AS title,
        chart.description,
        chart.display AS type,
        chart.is_archived,
        chart.ts_updated
    FROM
        datalake_metabase_clean.report_card AS chart
),
metabase_chart AS (
    SELECT
        chart.id_chart,
        chart.id_owner,
        chart.id_database,
        chart.id_table,
        chart.id_collection,
        chart.title,
        chart.description,
        chart.type,
        chart.is_archived,
        IF(
          lv.id_model IS NOT NULL,
          lv.ts_last_view,
          chart.ts_updated
        ) AS ts_last_view
    FROM
        window_chart AS chart
    LEFT JOIN
        metabase_last_view AS lv
            ON lv.id_model = chart.id_chart
    WHERE
        chart.row_number = 1
),
metabase_database AS (
    SELECT
        id AS id_database,
        name AS name_database
    FROM
        datalake_metabase_clean.metabase_database
    WHERE
        name = "all-data"
    GROUP BY
        id,
        name
),
metabase_table AS (
    SELECT
        id AS id_table,
        id_database,
        name AS name_table,
        schema AS hive_schema
    FROM
        datalake_metabase_clean.metabase_table
    GROUP BY
        id,
        id_database,
        name,
        schema
),
metabase_user AS (
    SELECT
        id AS id_user,
        email
    FROM
        datalake_metabase_clean.core_user
    GROUP BY
        id,
        email
),
non_personal_location_collection(
    SELECT
        id AS id_collection,
        name AS name_collection
    FROM
        datalake_metabase_clean.collection
    WHERE
        id_user_personal_owner IS NULL
),
flatten_location_collection AS (
    SELECT
        id AS id_collection,
        name AS name_collection,
        location AS location_collection,
        SPLIT(location, '/') AS array_location,
        EXPLODE(SPLIT(location, '/')) AS dir_collection
    FROM
        datalake_metabase_clean.collection
    WHERE
        id_user_personal_owner IS NULL
        AND location != '/'
),
joined_location_collection AS (
    SELECT
        fc.id_collection,
        fc.name_collection,
        fc.array_location,
        fc.dir_collection,
        mc.name_collection AS dir_name_collection
    FROM
        flatten_location_collection AS fc
    JOIN
        non_personal_location_collection AS mc
            ON fc.dir_collection = mc.id_collection
),
metabase_collection AS (
    SELECT
        id_collection,
        name_collection,
        array_location,
        concat_ws(
          "/",
          collect_list(dir_name_collection),
          name_collection
        ) AS readable_location
    FROM
        joined_location_collection
    GROUP BY
        id_collection,
        name_collection,
        array_location
    UNION
    SELECT
        id AS id_collection,
        name AS name_collection,
        null AS array_location,
        name AS readable_location
    FROM
        datalake_metabase_clean.collection
    WHERE
        id_user_personal_owner IS NULL
        AND location = "/"
)
SELECT
    "metabase" AS platform,
    CONCAT("/", metabase_collection.readable_location, "/") AS chart_path,
    chart.id_chart AS chart_id,
    chart.type,
    chart.title,
    chart.description AS chart_description,
    chart.ts_last_view AS last_view,
    CONCAT(
        "https://metabase.quintoandar.com.br/card/",
        chart.id_chart
    ) AS chart_url,
    IF(
        chart.id_table IS NOT NULL,
        CONCAT(
          "hive.",
          metabase_table.hive_schema,
          ".",
          metabase_table.name_table
        ),
        NULL
    ) AS dataset,
    metabase_user.email AS ownership,
    CASE
        WHEN is_archived IS TRUE THEN 'DEPRECATED'
        WHEN DATEDIFF(CURRENT_TIMESTAMP(), chart.ts_last_view) > 90 THEN 'DEPRECATED'
        ELSE 'ACTIVE'
    END AS status,
    CAST(NULL AS string) AS domain,
    CURRENT_TIMESTAMP() AS ts_ingested,
    YEAR(CURRENT_TIMESTAMP()) AS year,
    MONTH(CURRENT_TIMESTAMP()) AS month,
    DAY(CURRENT_TIMESTAMP()) AS day
FROM
    metabase_chart AS chart
JOIN
    metabase_database
        ON chart.id_database = metabase_database.id_database
LEFT JOIN
    metabase_user
        ON chart.id_owner = metabase_user.id_user
LEFT JOIN
    metabase_table
        ON chart.id_table = metabase_table.id_table
LEFT JOIN
    metabase_collection
        ON chart.id_collection = metabase_collection.id_collection
