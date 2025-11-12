SELECT
    id,
    offer_cohort_id AS id_offer_cohort,
    person_uuid AS uuid_person,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_lending_raw.offer_cohort_member