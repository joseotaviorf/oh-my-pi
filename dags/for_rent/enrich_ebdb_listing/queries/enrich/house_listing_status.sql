SELECT
    CAST(CAST(lbc_version.id_house AS STRING)||'00'||CAST(lbc_version.listing_version AS STRING) AS BIGINT) AS id_house_listing,
    lbc_version.id_house,
    house.id_region,
    lbc_version.country_code,
    lbc_version.listing_version AS version,
    lbc_version.status AS status_history,
    lbc_version.status_reason AS status_change_reason,
    lbc_version.revision_reason,
    COALESCE(
      -- get MAX ts per id_house_listings per day
      MAX(lbc_version.rev) OVER(
      PARTITION BY lbc_version.id_house, lbc_version.listing_version, CAST(lbc_version.ts_state_started AS DATE)
                    ) = lbc_version.rev,
    FALSE) AS is_last_status_of_day,
    lbc_version.ts_first_publication,
    lbc_version.ts_state_started AS ts_status_started,
    lbc_version.ts_state_ended AS ts_status_ended
FROM 
  datalake_ebdb_listing.lbc_status_version_order AS lbc_version
JOIN 
    datalake_ebdb_clean.house AS house
        ON house.id = lbc_version.id_house