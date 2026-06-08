SELECT
    id,
    listing_business_context_id AS id_listing_business_context,
    house_id AS id_house,
    REV AS rev,
    REVTYPE AS rev_type,
    contact_attempts,
    listing_confirmed AS is_confirmed,
    listing_business_context_id_MOD AS mod_id_listing_business_context,
    house_id_MOD AS mod_id_house,
    contact_attempts_MOD AS mod_contact_attempts,
    listing_confirmed_MOD AS mod_is_confirmed,
    last_contact_attempt_at_MOD AS mod_ts_last_contact_attempt,
    last_contact_attempt_at AS ts_last_contact_attempt,
    created_at AS ts_created
FROM
    datalake_ebdb_raw.`SuspectedUnavailabilityListing_AUD`
