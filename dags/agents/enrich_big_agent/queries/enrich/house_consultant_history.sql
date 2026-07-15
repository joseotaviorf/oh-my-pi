WITH agency_enrollment_aud AS (
    SELECT
        aud.id AS id_agency,
        aud.id_enrollment,
        aud.id_house,
        aud.rev,
        aud.rev_type,
        aud.ts_deleted,
        aud.ts_created,
        -- The relationship Angency:enrollment has cardinality N:1
        -- One agency has one enrollment per time, but one enrollment might have multiple agencies.
        LEAD(FROM_UNIXTIME(ure.ts_revision/1000)) OVER (PARTITION BY aud.id ORDER BY rev) AS ts_enrollment_ended,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_updated
    FROM
        datalake_big_agent_clean.agency_aud AS aud
    JOIN
        datalake_big_agent_clean.user_revision_entity AS ure
            ON ure.id = aud.rev
    WHERE
    -- In this aud Not only rev_type 2 are deletes, sometimes a row deleted shows up as a rev_type 1 with ts_deleted filled.
    -- To get both cases we are looking for rev_type 2 OR ts_deleted NOT NULL.
        aud.rev_type IN (0,2)
        OR aud.ts_deleted IS NOT NULL 
),
agency_enrollment_history AS (
    SELECT
        id_agency,
        id_enrollment,
        id_house,
        rev,
        COALESCE(MAX(rev) OVER(PARTITION BY id_agency, DATE(ts_updated)) = rev, False) AS is_last_status_of_day,
        ts_created AS ts_agency_created,
        ts_updated AS ts_enrollment_started,
        ts_enrollment_ended
    FROM
        agency_enrollment_aud
    WHERE
        rev_type <> 2
        AND ts_deleted IS NULL
),
last_status_agency AS (
    SELECT
        id AS id_agency,
        id_enrollment,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1 AS is_last_agency_status,
        dt_since AS dt_consultant_started,
        ts_deleted AS ts_consultant_deleted
    FROM
        datalake_big_agent_clean.agency
)
SELECT
    aeh.id_agency,
    aeh.id_enrollment,
    ag.id_internal_agent,
    GET_JSON_OBJECT(h.details, '$.houseExternalId') AS id_house,
    ag.id_partner,
    ag.id_user,
    aeh.rev,
    ag.consultant_type,
    aeh.is_last_status_of_day,
    lsa.dt_consultant_started,
    lsa.ts_consultant_deleted,
    aeh.ts_agency_created,
    aeh.ts_enrollment_started,
    aeh.ts_enrollment_ended
FROM
    datalake_big_agent_clean.house AS h
JOIN
    agency_enrollment_history AS aeh
        ON h.id = aeh.id_house
JOIN
    datalake_big_agent.agent_enrollment AS ag
        ON aeh.id_enrollment = ag.id_enrollment
LEFT JOIN
    last_status_agency AS lsa
        ON lsa.id_agency = aeh.id_agency
        AND lsa.is_last_agency_status = True
