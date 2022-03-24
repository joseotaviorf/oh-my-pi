WITH lbc_aud AS (
    SELECT
        lbc_aud.id_house,
        lbc_aud.rev,
        lbc_aud.ts_first_publication,
        IF(lbc_aud.mod_status_closing = 1, 
          status_closing, 
          status) AS status
    FROM 
      datalake_ebdb_clean.listing_business_context_aud AS lbc_aud
    WHERE
        lbc_aud.business_context = 'SALE'
),
house_aud AS (
--------------------------------------------------------------------------------------------------------
-- Bring to LBC_AUD datetime for each revision made                                                --
-- Also creates previous_status column so we can identify status changes                              --
-- (status_MOD = 1 may not work sometimes)                                                            --
--------------------------------------------------------------------------------------------------------
    SELECT
        rev2.ts_revision AS revision_time,
        DATE(FROM_UNIXTIME(BIGINT(rev.ts_revision)/1000)) AS status_date,
        rev.id_user,
        rev.reason,
        LAG(lbc_aud.status) OVER(PARTITION BY lbc_aud.id_house ORDER BY lbc_aud.rev) AS previous_status,
        LAG(h_aud.sale_price) OVER(PARTITION BY h_aud.id_house ORDER BY h_aud.rev) AS previous_sale_price,
        lbc_aud.status,
        h.id_region,
        h_aud.sale_price,
        h_aud.id_house,
        lbc_aud.rev,
        h_aud.mod_sale_price,
        lbc_aud.ts_first_publication
    FROM 
        datalake_ebdb_clean.house_aud AS h_aud
    JOIN 
        datalake_ebdb_clean.house AS h
            ON h.id = h_aud.id_house
    JOIN 
        lbc_aud
            ON lbc_aud.id_house = h.id
    JOIN 
        datalake_ebdb_clean.user_revision_entity AS rev
            ON rev.id = lbc_aud.rev
    JOIN 
        datalake_ebdb_user_revision_entity.user_revision_entity AS rev2
            ON rev2.id = lbc_aud.rev
),
house_status_history AS (
--------------------------------------------------------------------------------------------------------
-- Create status_history: for each house show all status changes, with start and end of each status   --
--------------------------------------------------------------------------------------------------------
    SELECT
        id_house,
        id_region,
        rev,
        MAX(ts_first_publication) OVER(PARTITION BY id_house) AS ts_first_publication,
        revision_time AS ts_status_changed,
        status AS status_history,
        reason,
        LEAD(revision_time) OVER(PARTITION BY id_house ORDER BY rev) AS ts_status_changed_next,
        ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY rev) AS order_status
    FROM 
        house_aud
    WHERE 
        status <> COALESCE(previous_status, '')
),
house_new_status_new_date AS (
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Create column to identify how long the house is in the status unpublished                                                                           -- In these cases of status_history_blank we also update the status changed date to the first_publication_date                                                         --
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    SELECT
        *,
        IF(status_history = 'UNPUBLISHED',
          DATEDIFF(DATE(COALESCE(ts_status_changed_next, NOW())), DATE(ts_status_changed)),
          NULL) AS days_unpublished,
        COALESCE(status_history, 'PUBLISHED') AS status_history_new,
        IF(status_history IS NULL,
          ts_first_publication,
          ts_status_changed) AS ts_status_changed_new,
        MAX(order_status) OVER(PARTITION BY id_house) AS max_order_status
    FROM 
        house_status_history
),
------------------------------------------------------------------------------------------------------------------------------------
-- Although a rented status is a trigger to a new version, the new version will only starts when there is a new published status  --
------------------------------------------------------------------------------------------------------------------------------------
house_status_version_first_publi AS (
    SELECT
        *,
        MIN(CASE 
            WHEN status_history_new = 'PUBLISHED' THEN ts_status_changed_new
        END) OVER(PARTITION BY id_house) AS first_publication_change_version
    FROM 
        house_new_status_new_date
),
house_status_version_order_null_publi_date AS (
--------------------------------------------------------------------------------------------------------
-- Define order version based on null publication dates                                               --
--------------------------------------------------------------------------------------------------------
    SELECT
        *,
        0 AS order_version
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
        *,
        DENSE_RANK() OVER(PARTITION BY id_house ORDER BY first_publication_change_version) AS order_version
    FROM 
        house_status_version_first_publi
    WHERE 
        first_publication_change_version IS NOT NULL
),

final_base AS (
  SELECT
      *
  FROM
      house_status_version_order_null_publi_date
  UNION ALL
  SELECT
      *
  FROM
      house_status_version_order_not_null_publi_date
)

SELECT fb.*
FROM 
    final_base AS fb
-- Filter to remove Casa Mineira listings included in Quinto Andar tables due to the BBB 22 campaign
LEFT JOIN
  datalake_ebdb_listing.house AS h
    ON h.id = fb.id_house
      AND h.internal_admin_info = '3P\n[FS-CM]'
WHERE
  h.id IS NULL
