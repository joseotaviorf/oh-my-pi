SELECT
    id,
    contract_id AS id_contract,
    edited_by_person AS id_edited_by_person,
    status,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    contract_id_mod AS mod_id_contract,
    status_mod AS mod_status,
    edited_by_person_mod AS mod_id_edited_by_person,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_status_history_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}