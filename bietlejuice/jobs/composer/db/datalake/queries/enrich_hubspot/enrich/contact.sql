WITH numbered_contact_history AS (
    SELECT *,
        ROW_NUMBER() OVER(PARTITION BY id_contact ORDER BY ts_updated DESC) AS rw
    FROM
        datalake_hubspot.contact_history
)
SELECT
    id_contact,
    id_hubspot_owner,
    id_company,
    hs_analytics_first_touch_converting_campaign,
    hs_analytics_last_touch_converting_campaign,
    hs_analytics_source,
    hs_analytics_source_data_1,
    hs_analytics_source_data_2,
    hs_latest_source_data_1,
    hs_latest_source_data_2,
    first_conversion_event_name,
    field_of_business,
    occupation,
    address,
    city,
    state,
    company,
    email,
    hs_email_domain,
    mobile_phone,
    phone,
    website,
    first_name,
    last_name,
    hs_marketable_status,
    life_cycle_stage,
    lead_origin_restricted_use,
    recent_conversion_event_name,
    lead_status,
    lead_status_history,
    num_conversion_events,
    num_associated_deals,
    is_enrolled_in_sequence,
    ts_first_conversion,
    ts_notes_last_updated,
    ts_notes_next_activity,
    ts_closed,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    numbered_contact_history
WHERE
    rw = 1
    AND NOT is_archived