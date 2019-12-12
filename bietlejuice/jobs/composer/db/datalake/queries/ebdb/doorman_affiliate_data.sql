SELECT
    id,
    workAddress AS work_address,
    workHouseNumber AS work_house_number,
    code,
    workNeighbourhood AS work_neighborhood,
    workCity AS work_city,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    joinedProgramAt AS ts_joined,
    lat,
    lng,
    placeId AS id_place,
    subscriptionSource AS subscription_source,
    workState AS work_state,
    workStreet AS work_street,
    recruiter AS recrutier,
    doorman_occupation_id AS id_doorman_occupation
FROM
    datalake_ebdb_raw.`DoormanAffiliateData`