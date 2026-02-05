SELECT
    id,
    status_from,
    status_to,
    substatus_from,
    substatus_to,
    reason_category,
    reason,
    additional_context,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.HouseListingStatusLog
