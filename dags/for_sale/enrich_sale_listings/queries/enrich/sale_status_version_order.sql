WITH lbc_aud AS (
    SELECT
        lbc_aud.id_house,
        lbc_aud.rev,
        lbc_aud.status,
        lbc_aud.status_closing,
        LAG(lbc_aud.status) OVER (PARTITION BY lbc_aud.id_house ORDER BY rev) AS previous_status,
        LAG(lbc_aud.status_closing) OVER (PARTITION BY lbc_aud.id_house ORDER BY rev) AS previous_status_closing,
        lbc_aud.status_reason,
        lbc_aud.ts_first_publication
    FROM 
      datalake_ebdb_clean.listing_business_context_aud AS lbc_aud
    WHERE
        lbc_aud.business_context = 'SALE'
    QUALIFY -- (status_MOD = 1 may not work sometimes)    
        status IS DISTINCT FROM previous_status
        OR (lbc_aud.mod_status_closing IS NOT NULL AND status_closing IS DISTINCT FROM previous_status_closing)
),
house_aud AS (
    SELECT
        lbc_aud.id_house,
        rev.id_user,
        h.id_region,
        lbc_aud.status,
        lbc_aud.status_closing,
        lbc_aud.status_reason,
        rev.reason,
        lbc_aud.rev,
        DATE(rev.ts_revision) AS status_date,
        lbc_aud.ts_first_publication,
        rev.ts_revision AS revision_time
    FROM 
        lbc_aud
    JOIN 
        datalake_ebdb_clean.house AS h
            ON h.id = lbc_aud.id_house
    JOIN 
        datalake_ebdb_user.user_revision_entity AS rev
            ON rev.id = lbc_aud.rev
),
house_status_history AS (
--------------------------------------------------------------------------------------------------------
-- Create status_history: for each house show all status changes, with start and end of each status   --
--------------------------------------------------------------------------------------------------------
    SELECT
        id_house,
        id_user AS id_user_revision,
        id_region,
        rev,
        status AS status_history,
        status_closing AS status_closing_history,
        status_reason,
        reason AS status_reason_detail,
        revision_time AS ts_status_changed,
        LEAD(revision_time) OVER(PARTITION BY id_house ORDER BY rev) AS ts_status_changed_next,
        MAX(ts_first_publication) OVER(PARTITION BY id_house) AS ts_first_publication,
        ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY rev) AS order_status
    FROM 
        house_aud
),
house_new_status_new_date AS (
-----------------------------------------------------------------------------------------------------------------
-- Create column to identify how long the house is in the status unpublished                                   --
-- In these cases of status_history_blank we also update the status changed date to the first_publication_date --
-----------------------------------------------------------------------------------------------------------------
    SELECT
        id_house,
        id_user_revision,
        id_region,
        rev,
        status_history,
        status_closing_history,
        status_reason,
        status_reason_detail,
        COALESCE(status_history, 'PUBLISHED') AS status_history_new,
        IF(status_history = 'UNPUBLISHED',
          DATEDIFF(DATE(COALESCE(ts_status_changed_next, NOW())), DATE(ts_status_changed)),
          NULL) AS days_unpublished,
        order_status,
        MAX(order_status) OVER(PARTITION BY id_house) AS max_order_status,
        ts_first_publication,
        ts_status_changed,
        ts_status_changed_next,
        IF(status_history IS NULL,
          ts_first_publication,
          ts_status_changed) AS ts_status_changed_new
    FROM 
        house_status_history
),
------------------------------------------------------------------------------------------------------------------------------------
-- Although a rented status is a trigger to a new version, the new version will only starts when there is a new published status  --
------------------------------------------------------------------------------------------------------------------------------------
house_status_version_first_publi AS (
    SELECT
        id_house,
        id_user_revision,
        id_region,
        rev,
        status_history,
        status_closing_history,
        status_reason,
        status_reason_detail,
        status_history_new,
        MIN(CASE 
            WHEN status_history_new = 'PUBLISHED' THEN ts_status_changed_new
        END) OVER(PARTITION BY id_house) AS first_publication_change_version,
        days_unpublished,
        order_status,
        max_order_status,
        ts_first_publication,
        ts_status_changed,
        ts_status_changed_next,
        ts_status_changed_new
    FROM 
        house_new_status_new_date
),
house_status_version_order_null_publi_date AS (
--------------------------------------------------------------------------------------------------------
-- Define order version based on null publication dates                                               --
--------------------------------------------------------------------------------------------------------
    SELECT
        id_house,
        id_user_revision,
        id_region,
        rev,
        status_history,
        status_closing_history,
        status_reason,
        status_reason_detail,
        status_history_new,
        first_publication_change_version,
        days_unpublished,
        order_status,
        0 AS order_version,
        max_order_status,
        ts_first_publication,
        ts_status_changed,
        ts_status_changed_next,
        ts_status_changed_new
    FROM 
        house_status_version_first_publi
    WHERE 
        first_publication_change_version IS NULL
),
house_status_version_order_not_null_publi_date AS (
--------------------------------------------------------------------------------------------------------
-- Define order version based on non null publication dates                                           --
--------------------------------------------------------------------------------------------------------
    SELECT
        id_house,
        id_user_revision,
        id_region,
        rev,
        status_history,
        status_closing_history,
        status_reason,
        status_reason_detail,
        status_history_new,
        first_publication_change_version,
        days_unpublished,
        order_status,
        DENSE_RANK() OVER (PARTITION BY id_house ORDER BY first_publication_change_version) AS order_version,
        max_order_status,
        ts_first_publication,
        ts_status_changed,
        ts_status_changed_next,
        ts_status_changed_new
    FROM 
        house_status_version_first_publi
    WHERE 
        first_publication_change_version IS NOT NULL
),
aux AS (
    SELECT
        id_house,
        id_user_revision,
        id_region,
        rev,
        status_history,
        status_closing_history,
        status_reason,
        status_reason_detail,
        status_history_new,
        first_publication_change_version,
        days_unpublished,
        order_status,
        order_version,
        max_order_status,
        ts_first_publication,
        ts_status_changed,
        ts_status_changed_next,
        ts_status_changed_new
    FROM
        house_status_version_order_null_publi_date
    UNION ALL
    SELECT
        id_house,
        id_user_revision,
        id_region,
        rev,
        status_history,
        status_closing_history,
        status_reason,
        status_reason_detail,
        status_history_new,
        first_publication_change_version,
        days_unpublished,
        order_status,
        order_version,
        max_order_status,
        ts_first_publication,
        ts_status_changed,
        ts_status_changed_next,
        ts_status_changed_new
    FROM
        house_status_version_order_not_null_publi_date
)
SELECT 
    id_house,
    id_user_revision,
    id_region,
    rev,
    status_history,
    status_closing_history,
    status_reason,
    status_reason_detail,
    status_history_new,
    first_publication_change_version,
    days_unpublished,
    order_status,
    order_version,
    max_order_status,
    ts_first_publication,
    ts_status_changed,
    ts_status_changed_next,
    ts_status_changed_new
FROM 
    aux 