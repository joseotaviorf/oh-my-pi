SELECT
    id,
    listing_business_context_id AS id_listing_business_context,
    house_id AS id_house,
    contact_attempts,
    listing_confirmed AS is_confirmed,
    last_contact_attempt_at AS ts_last_contact_attempt,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.`SuspectedUnavailabilityListing`
