WITH
  max_status_order AS ( 
  --------------------------------------------------------------------------------------------------------
  -- Identify the last status to each version                                                           --
  --------------------------------------------------------------------------------------------------------
    SELECT
        id_house,
        listing_version,
        MAX(is_extended_rental) AS is_extended_rental,
        MAX(is_brokerage_only_decommissioned) AS is_brokerage_only_decommissioned,
        MAX(state_order) AS max_order_status
    FROM
      datalake_ebdb_listing.lbc_status_version_order
    GROUP BY
      id_house, listing_version
  ),
  house_status_version_last_status AS (
    SELECT
        lbc_vo.id_house,
        lbc_vo.status,
        LAG(status) OVER(PARTITION BY lbc_vo.id_house ORDER BY lbc_vo.ts_state_started) AS previous_status,
        lbc_vo.status_reason,
        lbc_vo.revision_reason,
        lbc_vo.ts_state_started,
        lbc_vo.ts_state_ended,
        lbc_vo.days_in_state,
        lbc_vo.days_in_status,
        lbc_vo.trigger_new_version,
        lbc_vo.listing_version,
        lbc_vo.state_order,
        lbc_vo.max_state_order,
        lbc_vo.country_code,
        MAX(
          CASE
              WHEN lbc_vo.status IN ('despublicado', 'UNPUBLISHED')
              THEN ts_state_started
          END
        ) OVER(PARTITION BY lbc_vo.id_house, lbc_vo.listing_version) AS ts_last_unpublished,
        IF(ms_o.max_order_status IS NOT NULL, lbc_vo.status, NULL) AS last_status,
        IF(ms_o.max_order_status IS NOT NULL, lbc_vo.status_reason, NULL) AS last_status_reason,
        MAX(lbc_vo.state_order) OVER(PARTITION BY lbc_vo.id_house, lbc_vo.listing_version) AS max_order_status_version,
        MAX(ms_o.is_extended_rental) OVER(PARTITION BY lbc_vo.id_house, lbc_vo.listing_version) AS is_extended_rental,
        MAX(ms_o.is_brokerage_only_decommissioned) OVER(PARTITION BY lbc_vo.id_house, lbc_vo.listing_version) AS is_brokerage_only_decommissioned
    FROM 
      datalake_ebdb_listing.lbc_status_version_order AS lbc_vo
    LEFT JOIN 
      max_status_order AS ms_o
        ON lbc_vo.id_house = ms_o.id_house
        AND lbc_vo.listing_version = ms_o.listing_version
        AND lbc_vo.state_order = ms_o.max_order_status
  ),
  status_change_version AS (
  --------------------------------------------------------------------------------------------------------
  -- Identify the status that made it changes to a new version                                          --
  -- This status is important to define which category the listing will have                            --
  --------------------------------------------------------------------------------------------------------
    SELECT
      id_house,
      listing_version,
      FIRST(status) OVER(PARTITION BY id_house, listing_version ORDER BY ts_state_started DESC, ts_state_ended DESC) AS category_change,
      FIRST(status_reason) OVER(PARTITION BY id_house, listing_version ORDER BY ts_state_started DESC, ts_state_ended DESC) AS category_change_reason
    FROM 
      house_status_version_last_status
    WHERE
      trigger_new_version = 1
  ),
  house_listing_plain AS (
  --------------------------------------------------------------------------------------------------------
  -- Create listings column according to version                                                        --
  -- Create column to identify category (using column from join with status_change_version              --
  -- Keep only the version changes                                                                      --
  --------------------------------------------------------------------------------------------------------
    SELECT
        hs_v.id_house,
        hs_v.country_code,
        hs_v.listing_version AS version,
        sc_v.category_change AS change_version_status,
        sc_v.category_change_reason AS change_version_status_reason,
        hs_v.ts_last_unpublished,
        hs_v.is_extended_rental,
        hs_v.is_brokerage_only_decommissioned,
        MAX(hs_v.previous_status) AS status_history,
        MAX(hs_v.ts_state_started) AS ts_status_changed,
        MAX(hs_v.last_status) AS status,
        MAX(hs_v.last_status_reason) AS status_reason,
        MAX(hs_v.revision_reason) AS revision_reason,
        MIN(hs_v.ts_state_started) AS ts_listing_version_start,
        MAX(COALESCE(hs_v.ts_state_ended, CAST('2200-01-01 12:00:00' AS TIMESTAMP))) AS ts_listing_version_end
    FROM
      house_status_version_last_status AS hs_v
    LEFT JOIN 
      status_change_version AS sc_v
        ON hs_v.id_house = sc_v.id_house
        AND hs_v.listing_version = sc_v.listing_version
    GROUP BY 
      1, 2, 3, 4, 5, 6, 7, 8
  )
--------------------------------------------------------------------------------------------------------
-- Create category                                                                                    --
--------------------------------------------------------------------------------------------------------
SELECT
  CAST(CAST(id_house AS STRING)||'00'||CAST(version AS STRING) AS BIGINT) AS id_house_listing,
  id_house,
  country_code,
  version,
  CASE 
    WHEN version = 0 THEN NULL
    WHEN version = 1 THEN 'First Listing'
    WHEN 
      version > 1 
      AND (
        LAG(change_version_status) OVER(PARTITION BY id_house ORDER BY version) = 'alugado'
        OR (
          LAG(change_version_status) OVER(PARTITION BY id_house ORDER BY version) = 'SUSPENDED'
          AND
          LAG(change_version_status_reason) OVER(PARTITION BY id_house ORDER BY version) = 'RENTED'
        )
      )
    THEN 'Re-Listing'
    WHEN 
      version > 1
      AND 
      LAG(change_version_status) OVER(PARTITION BY id_house ORDER BY version) IN ('despublicado', 'UNPUBLISHED') 
    THEN 'Recovered'
    ELSE NULL 
  END AS listing_category,
  status,
  status_reason,
  revision_reason,
  status_history,
  is_extended_rental,
  is_brokerage_only_decommissioned,
  CAST(ts_status_changed AS TIMESTAMP) AS ts_status_changed,
  CAST(ts_listing_version_start AS TIMESTAMP) AS ts_listing_version_start,
  NULLIF(CAST(ts_listing_version_end AS TIMESTAMP), CAST('2200-01-01 12:00:00' AS TIMESTAMP)) AS ts_listing_version_end,
  CAST(ts_last_unpublished AS TIMESTAMP) AS ts_last_unpublished
FROM 
  house_listing_plain