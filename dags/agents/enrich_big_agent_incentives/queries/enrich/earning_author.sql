WITH author AS (
    SELECT
        ne.id AS id_earning,
        ne.id_author,
        u.id AS id_user,
        u.uuid_person,
        ne.author_role,
        ne.author_channel,
        ne.author_on_behalf_of_role,
        ROW_NUMBER() OVER (
            PARTITION BY
                ne.id,
                ne.id_author
            ORDER BY
                ne.ts_updated DESC
        ) = 1 AS is_last_updated,
        ne.ts_created,
        ne.ts_updated
    FROM
        datalake_big_agent_clean.new_earnings AS ne
    LEFT JOIN
        datalake_ebdb_user.user AS u
            ON u.uuid_person = ne.id_author 
    WHERE
        DATE(ne.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_earning,
    id_author,
    id_user,
    uuid_person,
    author_role,
    author_channel,
    author_on_behalf_of_role,
    ts_created,
    ts_updated,
    DATE(ts_created) AS dt_load,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
FROM
    author
WHERE
    is_last_updated = TRUE