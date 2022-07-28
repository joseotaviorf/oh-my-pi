SELECT
    id,
    NULLIF(workAddress, '') AS work_address,
    workHouseNumber AS work_house_number,
    code,
    NULLIF(workNeighbourhood, '') AS work_neighborhood,
    NULLIF(workCity, '') AS work_city,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    joinedProgramAt AS ts_joined,
    lat,
    lng,
    placeId AS id_place,
    subscriptionSource AS subscription_source,
    NULLIF(workState, '') AS work_state,
    NULLIF(workStreet, '') AS work_street,
    recruiter AS recrutier,
    doorman_occupation_id AS id_doorman_occupation
FROM
    datalake_ebdb_raw.`DoormanAffiliateData`