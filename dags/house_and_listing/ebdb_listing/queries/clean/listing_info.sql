SELECT
    id,
    house_id AS id_house,
    movingDate AS moving_date,
    daysToVacate AS days_to_vacate,
    displayCustomOfferPreference AS display_custom_offer_preference,
    awaitingAvailabilityReason AS awaiting_availability_reason,
    allowsCustomOffer AS allows_custom_offer,
    availabilityType AS availability_type,
    furniture,
    movingDateDefined AS dt_moving_defined,
    updated_on AS ts_updated,
    created_on AS ts_created
FROM
    datalake_ebdb_raw.listinginfo
