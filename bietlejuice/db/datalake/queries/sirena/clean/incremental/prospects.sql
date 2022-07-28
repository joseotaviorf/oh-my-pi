SELECT
    id,
    groupId AS id_group,
    accountId AS id_account,
    initialGroupId AS id_initial_group,
    label,
    group,
    account,
    initialGroup AS initial_group,
    firstName AS first_name,
    lastName AS last_name,
    category,
    status,
    nin AS national_identification_number,
    additionalData AS additional_data,
    phones,
    emails,
    contactMediums AS contact_mediums,
    leads,
    agent,
    archivingReason AS archiving_reason,
    absenceMessage AS absence_message,
    userMade AS is_user_made,
    merged AS is_merged,
    created AS ts_created,
    assigned AS ts_assigned,
    nextReminder AS ts_next_reminder,
    firstContactedAt AS ts_first_contact,
    sentWorkingHourMessage AS ts_sent_working_hour_message,
    year,
    month,
    day
FROM
    datalake_sirena_raw.prospects
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
