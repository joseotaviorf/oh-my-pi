SELECT
    id,
    house_id AS id_house,
    photoShootSchedulingReason AS photo_shoot_schedule_reason,
    registrationAbandonedReason AS registration_abandoned_reason,
    status,
    photoShoot_id AS id_photo_shoot,
    assignee_id AS id_assignee,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.HouseRegistrationStatus
