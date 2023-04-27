SELECT
    BIGINT(STRING(ssvo.id_house)||'00'||STRING(ssvo.order_version)) AS id_sale_listing,
    ssvo.id_house,
    ssvo.id_region,
    rhh.id_company_hubspot,
    rhh.partner_3p_supply,
    ssvo.status_history_new AS status_history,
    REGEXP_REPLACE(reason, '\n', '') AS status_change_reason,
    COALESCE(
      -- get max ts per id_house_listings per day
      MAX(ssvo.ts_status_changed_new) OVER(
        PARTITION BY ssvo.id_house
      ) = ts_status_changed_new,
    FALSE) AS is_last_status,
    COALESCE(rhh.is_3p_supply, FALSE) AS is_3p_supply,
    ssvo.ts_first_publication,
    ssvo.ts_status_changed_new AS ts_status_started,
    ssvo.ts_status_changed_next AS ts_status_ended
FROM 
    datalake_sale_listings.sale_status_version_order AS ssvo
LEFT JOIN
    datalake_rede_house_history.rede_house_history AS rhh
        ON ssvo.id_house = rhh.id_house
        AND rhh.business_context = 'SALE'
        AND ssvo.ts_status_changed_new >= rhh.ts_status_started
        AND ssvo.ts_status_changed_new < COALESCE(rhh.ts_status_ended, NOW())
