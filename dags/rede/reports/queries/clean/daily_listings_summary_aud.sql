SELECT
    id,
    location_id AS id_location,
    company AS uuid_company,
    sale_count,
    sale_traffic,
    sale_visits_scheduled,
    sale_visits_confirmed,
    sale_offers_sent,
    sale_offers_accepted,
    ccv,
    ccvs_transacted_amount,
    ongoing_listings,
    rev,
    revend,
    revtype,
    version,
    location_id_mod AS mod_id_location,
    company_mod AS mod_uuid_company,
    sale_count_mod AS mod_sale_count,
    sale_traffic_mod AS mod_sale_traffic,
    sale_visits_scheduled_mod AS mod_sale_visits_scheduled,
    sale_visits_confirmed_mod AS mod_sale_visits_confirmed,
    sale_offers_sent_mod AS mod_sale_offers_sent,
    sale_offers_accepted_mod AS mod_sale_offers_accepted,
    ccv_mod AS mod_ccv,
    ccvs_transacted_amount_mod,
    ongoing_listings_mod,
    entry_date_mod AS mod_dt_entry,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    entry_date AS dt_entry,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_reports_raw.daily_listings_summary_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}