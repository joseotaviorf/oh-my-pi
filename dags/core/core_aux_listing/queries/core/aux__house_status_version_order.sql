WITH house_aud AS (
--------------------------------------------------------------------------------------------------------
-- Bring to IMOVEL_AUD datetime for each revision made                                                --
-- Also creates previous_status column so we can identify status changes                              --
-- (status_MOD = 1 may not work sometimes)                                                            --
--------------------------------------------------------------------------------------------------------
    SELECT
        rev.id_user,
        h_aud.id_house,
        CAST(from_unixtime(CAST(rev.ts_revision AS BIGINT)/1000) AS TIMESTAMP) AS revision_time,
        rev.reason,
        LAG(h_aud.status) OVER(PARTITION BY h_aud.id_house ORDER BY h_aud.rev) AS previous_status,
        h_aud.status,
        h_aud.rev,
        h_aud.dt_first_publication
    FROM
        datalake_ebdb_clean.house_aud AS h_aud
    INNER JOIN
        datalake_ebdb_clean.user_revision_entity AS rev
            ON rev.id = h_aud.rev
),
house_status_history AS (
--------------------------------------------------------------------------------------------------------
-- Create status_history: for each house show all status changes, with start and end of each status   --
--------------------------------------------------------------------------------------------------------
    SELECT
        id_house,
        rev,
        MAX(dt_first_publication) OVER(PARTITION BY id_house) AS ts_first_publication,
        revision_time AS ts_status_changed,
        status AS status_history,
        reason,
        LEAD(revision_time) OVER(PARTITION BY id_house ORDER BY rev) AS ts_status_changed_next,
        ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY rev) AS order_status
    FROM
        house_aud
    WHERE
        status <> previous_status
        OR previous_status IS NULL
),
house_new_status_new_date AS (
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Create column to identify how long the house is in the status unpublished                                                                                           --
-- We will use this column to check if a new version will be created to this house (a new version will be created when the house is unpublished for 12 weeks or more)  --
-- Since we will count from the day it turns 12 weeks, there's no need to extract 1 day from the end_date in date_diff                                                 --
-- Since we are using date_diff, we are considering the whole part of the number, so if the difference is 83.7, it won't consider as recovered                         --
-- For the older houses there are cases of status_history blank, so we have to input status_history = 'publicado' (this happens to status from 2015)                   --
-- In these cases of status_history_blank we also update the status changed date to the first_publication_date                                                         --
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
SELECT
    *,
    CASE
        WHEN status_history = 'despublicado'
            THEN CAST((UNIX_TIMESTAMP(COALESCE(ts_status_changed_next, NOW())) - UNIX_TIMESTAMP(ts_status_changed))/(86400) AS INTEGER)
    END AS days_unpublished,
    COALESCE(status_history, 'publicado') AS status_history_new,
    CASE
        WHEN status_history IS NULL
            THEN ts_first_publication
        ELSE ts_status_changed
    END AS ts_status_changed_new,
    MAX(order_status) OVER(PARTITION BY id_house) AS max_order_status
FROM
    house_status_history
),
house_status_version_changes_base AS (
--------------------------------------------------------------------------------------------------------
-- Create column to identify moments where house changed status would create a new version/listing    --
-- The moments are: when there is a status rented or a status unpublished with days_unpublished >= 84 --
-- With a cumulative sum we can identify when a new change of status happens                          --
--------------------------------------------------------------------------------------------------------
    SELECT *,
        CASE
            WHEN status_history_new = 'alugado'
                OR (status_history_new = 'despublicado' AND days_unpublished >= 84)
                THEN 1
            ELSE 0
        END AS events_change_version
    FROM
        house_new_status_new_date
),
house_status_version_changes AS (
    SELECT
        *,
        CASE
            WHEN events_change_version = 1
                THEN status_history_new
        END AS events_change_status,
        SUM(events_change_version) OVER (PARTITION BY id_house ORDER BY rev ROWS UNBOUNDED PRECEDING) AS sum_events_change_version
    FROM
        house_status_version_changes_base
),
house_status_version_first_publi AS (
------------------------------------------------------------------------------------------------------------------------------------
-- Although a rented status is a trigger to a new version, the new version will only starts when there is a new published status  --
-- The rented status will still be a part of previous status and the new published status will be the start of the new version    --
------------------------------------------------------------------------------------------------------------------------------------
    SELECT
        *,
        MIN(
            CASE
                WHEN status_history_new = 'publicado'
                    THEN ts_status_changed_new
            END
        ) OVER(PARTITION BY id_house, sum_events_change_version ORDER BY rev) AS first_publication_change_version
    FROM
        house_status_version_changes
),
house_status_version_publications AS (
------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- The rented status will still be a part of previous status, and so will be all status different from published after rental                                   --
-- All versions begin with a date from published status, without a published status there will not be a version_start_date                                      --
------------------------------------------------------------------------------------------------------------------------------------------------------------------
    SELECT
        id_house,
        rev,
        reason,
        status_history,
        ts_first_publication,
        ts_status_changed,
        ts_status_changed_next,
        order_status,
        events_change_status,
        MAX(first_publication_change_version) OVER (PARTITION BY id_house ORDER BY rev ROWS UNBOUNDED PRECEDING) AS publication_version_date
    FROM
        house_status_version_first_publi
),
house_status_version_order_null_publi_date AS (
--------------------------------------------------------------------------------------------------------
-- Define order version based on null publication dates                                               --
--------------------------------------------------------------------------------------------------------
    SELECT
        *,
        0 AS order_version
    FROM
        house_status_version_publications
    WHERE
        publication_version_date IS NULL
),
house_status_version_order_not_null_publi_date AS (
--------------------------------------------------------------------------------------------------------
-- Define order version based on non null publication dates                                           --
--------------------------------------------------------------------------------------------------------
    SELECT
        *,
        DENSE_RANK() OVER(PARTITION BY id_house ORDER BY publication_version_date) AS order_version
    FROM
        house_status_version_publications
    WHERE
        publication_version_date IS NOT NULL
)
SELECT
    id_house,
    order_status,
    order_version,
    rev,
    status_history,
    reason,
    events_change_status,
    publication_version_date,
    ts_first_publication,
    ts_status_changed,
    ts_status_changed_next
FROM
    house_status_version_order_null_publi_date

UNION ALL

SELECT
    id_house,
    order_status,
    order_version,
    rev,
    status_history,
    reason,
    events_change_status,
    publication_version_date,
    ts_first_publication,
    ts_status_changed,
    ts_status_changed_next
FROM
    house_status_version_order_not_null_publi_date
