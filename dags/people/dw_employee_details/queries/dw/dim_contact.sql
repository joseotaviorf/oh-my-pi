WITH
employees AS (
    SELECT DISTINCT
        im.id_person
    FROM
        datalake_people_core.identifier_mapping AS im
    WHERE
        NOT im.is_user_test
),
contact_versions AS (
    SELECT
        ap.id_person,
        ap.person_number,
        ap.dt_effective_started,
        ap.dt_effective_ended,
        ap.id_primary_email,
        ap.id_primary_phone,
        ap.id_mailing_address
    FROM
        datalake_pin_core_clean.all_people AS ap
    INNER JOIN
        employees AS emp
            ON ap.id_person = emp.id_person
    WHERE
        ap.dt_effective_started <= CURRENT_DATE
),
work_email_at_version AS (
    SELECT
        cv.id_person,
        cv.dt_effective_started,
        ea.email_address AS work_email
    FROM
        contact_versions AS cv
    INNER JOIN
        datalake_pin_core_clean.email_address AS ea
            ON cv.id_person = ea.id_person
            AND ea.email_type = 'W1'
            AND ea.dt_started <= cv.dt_effective_started
            AND (ea.dt_ended >= cv.dt_effective_started OR ea.dt_ended IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                cv.id_person,
                cv.dt_effective_started
            ORDER BY
                ea.dt_started DESC
        ) = 1
),
personal_email_at_version AS (
    SELECT
        cv.id_person,
        cv.dt_effective_started,
        ea.email_address AS personal_email
    FROM
        contact_versions AS cv
    INNER JOIN
        datalake_pin_core_clean.email_address AS ea
            ON cv.id_person = ea.id_person
            AND ea.email_type = 'H1'
            AND ea.dt_started <= cv.dt_effective_started
            AND (ea.dt_ended >= cv.dt_effective_started OR ea.dt_ended IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                cv.id_person,
                cv.dt_effective_started
            ORDER BY
                ea.dt_started DESC
        ) = 1
),
phone_at_version AS (
    SELECT
        cv.id_person,
        cv.dt_effective_started,
        p.country_code_number,
        p.area_code,
        p.phone_number
    FROM
        contact_versions AS cv
    INNER JOIN
        datalake_pin_core_clean.phone AS p
            ON cv.id_primary_phone = p.id_phone
            AND p.dt_started <= cv.dt_effective_started
            AND (p.dt_ended >= cv.dt_effective_started OR p.dt_ended IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                cv.id_person,
                cv.dt_effective_started
            ORDER BY
                p.dt_started DESC
        ) = 1
),
github_at_version AS (
    SELECT
        cv.id_person,
        cv.dt_effective_started,
        pl.github_username
    FROM
        contact_versions AS cv
    INNER JOIN
        datalake_pin_core_clean.people_legislative AS pl
            ON cv.id_person = pl.id_person
            AND pl.legislation_code = 'BR'
            AND pl.dt_effective_started <= cv.dt_effective_started
            AND (pl.dt_effective_ended >= cv.dt_effective_started OR pl.dt_effective_ended IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                cv.id_person,
                cv.dt_effective_started
            ORDER BY
                pl.dt_effective_started DESC
        ) = 1
),
address_at_version AS (
    SELECT
        cv.id_person,
        cv.dt_effective_started,
        a.street,
        a.number AS address_number,
        a.complement AS address_complement,
        a.neighborhood AS address_district,
        a.postal_code AS address_zip_code,
        a.town_or_city AS address_city,
        a.state AS address_state,
        a.country_code AS address_country
    FROM
        contact_versions AS cv
    INNER JOIN
        datalake_pin_core_clean.address AS a
            ON cv.id_mailing_address = a.id_address
            AND a.dt_effective_started <= cv.dt_effective_started
            AND (a.dt_effective_ended >= cv.dt_effective_started OR a.dt_effective_ended IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                cv.id_person,
                cv.dt_effective_started
            ORDER BY
                a.dt_effective_started DESC
        ) = 1
)
SELECT
    MD5(CONCAT_WS('|', CAST(cv.id_person AS STRING), CAST(cv.dt_effective_started AS STRING))) AS sk_contact_version,
    cv.person_number,
    we.work_email,
    pe.personal_email,
    pv.country_code_number AS phone_country_code,
    pv.area_code AS phone_area_code,
    pv.phone_number AS phone_number,
    CONCAT_WS(' ', pv.country_code_number, pv.area_code, pv.phone_number) AS full_phone_number,
    gh.github_username,
    av.street AS address_street,
    av.address_number,
    av.address_complement,
    av.address_district,
    av.address_zip_code,
    av.address_city,
    av.address_state,
    av.address_country,
    CONCAT_WS(
        ', ',
        av.street,
        CAST(av.address_number AS STRING),
        av.address_complement,
        av.address_district,
        av.address_zip_code,
        av.address_city,
        av.address_state,
        av.address_country
    ) AS full_address,
    cv.dt_effective_started AS dt_valid_from,
    COALESCE(
        LEAD(cv.dt_effective_started) OVER (
            PARTITION BY
                cv.id_person
            ORDER BY
                cv.dt_effective_started
        ) - INTERVAL '1 DAY',
        DATE('9999-12-31')
    ) AS dt_valid_to,
    (
        LEAD(cv.dt_effective_started) OVER (
            PARTITION BY
                cv.id_person
            ORDER BY
                cv.dt_effective_started
        ) IS NULL
    ) AS is_current,
    NOW() AS ts_load
FROM
    contact_versions AS cv
LEFT JOIN
    work_email_at_version AS we
        ON cv.id_person = we.id_person
        AND cv.dt_effective_started = we.dt_effective_started
LEFT JOIN
    personal_email_at_version AS pe
        ON cv.id_person = pe.id_person
        AND cv.dt_effective_started = pe.dt_effective_started
LEFT JOIN
    phone_at_version AS pv
        ON cv.id_person = pv.id_person
        AND cv.dt_effective_started = pv.dt_effective_started
LEFT JOIN
    github_at_version AS gh
        ON cv.id_person = gh.id_person
        AND cv.dt_effective_started = gh.dt_effective_started
LEFT JOIN
    address_at_version AS av
        ON cv.id_person = av.id_person
        AND cv.dt_effective_started = av.dt_effective_started
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY
            cv.id_person,
            cv.dt_effective_started
        ORDER BY
            cv.dt_effective_ended DESC NULLS LAST
    ) = 1
