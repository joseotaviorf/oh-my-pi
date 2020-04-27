SELECT
    id AS id_house_registration_status,
    REV AS rev,
    REVTYPE AS rev_type,
    photoShootSchedulingReason AS photo_shoot_schedule_reason,
    photoShootSchedulingReason_MOD AS mod_photo_shoot_schedule_reason,
    registrationAbandonedReason AS registration_abandoned_reason,
    registrationAbandonedReason_MOD AS mod_registration_abandoned_reason,
    status,
    status_MOD AS mod_status,
    house_id AS id_house,
    photoShoot_id AS id_photo_shoot,
    photoShoot_MOD AS mod_photo_shoot,
    assignee_id AS id_assignee,
    assignee_MOD AS mod_assignee
FROM
    datalake_ebdb_raw.HouseRegistrationStatus_AUD
