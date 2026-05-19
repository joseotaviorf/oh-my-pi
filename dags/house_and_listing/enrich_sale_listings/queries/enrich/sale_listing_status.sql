SELECT
    BIGINT(STRING(ssvo.id_house)||'00'||STRING(ssvo.order_version)) AS id_sale_listing,
    ssvo.id_house,
    ssvo.id_user_revision,
    ssvo.id_region,
    h.id_company_hubspot,
    h.uuid_company,
    h.partner_3p_supply,
    ssvo.status_history_new AS status_history,
    ssvo.status_closing_history,
    ssvo.status_reason AS status_change_reason,
    REGEXP_REPLACE(ssvo.status_reason_detail, '\n', '') AS status_change_reason_detail,
    COALESCE(
      -- get max ts per id_house_listings per day
      MAX(ssvo.ts_status_changed_new) OVER(
        PARTITION BY ssvo.id_house
      ) = ts_status_changed_new,
    FALSE) AS is_last_status,
    COALESCE(h.is_sale_3p_supply, FALSE) AS is_3p_supply,
    ssvo.ts_first_publication,
    ssvo.ts_status_changed_new AS ts_status_started,
    ssvo.ts_status_changed_next AS ts_status_ended
FROM
    datalake_sale_listings.sale_status_version_order AS ssvo
LEFT JOIN
    datalake_ebdb_listing.house AS h
        ON ssvo.id_house = h.id
