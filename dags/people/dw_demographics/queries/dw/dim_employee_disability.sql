WITH person_keys AS (
    SELECT
        im.id_person,
        im.person_number
    FROM
        datalake_people.identifier_mapping AS im
    WHERE
        im.is_person_latest_assignment = TRUE
        AND im.assignment_type IN ('E', 'C')
        AND NOT im.is_user_test
),
lookups AS (
    SELECT
        lookup_code,
        meaning,
        lookup_type
    FROM
        datalake_pin_core_clean.foundation_lookup_value
    WHERE
        lookup_type IN ('DISABILITY_CATEGORY', 'QA_DISABILITY_SUBCLAS')
        AND language = 'US'
        AND is_enabled = TRUE
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                lookup_type,
                lookup_code
            ORDER BY
                ts_updated DESC
        ) = 1
),
disability_enriched AS (
    SELECT
        d.id_person,
        pk.person_number,
        d.legislation_code,
        d.id_disability,
        d.disability_code,
        d.category,
        d.status,
        d.quota_fte,
        pl.accessibility_need,
        COALESCE(flv.meaning, pl.neurodiversity) AS neurodiversity,
        pl.disability_answer,
        pl.disability_type,
        DATE(d.dt_effective_started) AS dt_valid_from,
        COALESCE(
            NULLIF(DATE(d.dt_effective_ended), DATE('4712-12-31')),
            DATE('9999-12-31')
        ) AS dt_valid_to
    FROM
        datalake_pin_core_clean.disability AS d
    INNER JOIN
        person_keys AS pk
            ON d.id_person = pk.id_person
    LEFT JOIN
        datalake_pin_core_clean.people_legislative AS pl
            ON pl.id_person = d.id_person
            AND pl.legislation_code = d.legislation_code
            AND pl.dt_effective_started <= COALESCE(
                NULLIF(DATE(d.dt_effective_ended), '4712-12-31'),
                '9999-12-31'
            )
            AND COALESCE(
                NULLIF(pl.dt_effective_ended, '4712-12-31'),
                '9999-12-31'
            ) >= DATE(d.dt_effective_started)
    LEFT JOIN 
        datalake_pin_core_clean.foundation_lookup_value AS flv
            ON flv.lookup_type = 'QA_NEURODIVERSIDADE'
            AND flv.lookup_code = pl.neurodiversity
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                d.id_disability,
                d.dt_effective_started,
                d.dt_effective_ended
            ORDER BY
                d.ts_updated DESC,
                pl.dt_effective_started DESC
        ) = 1
)
SELECT
    CAST(id_person AS STRING) AS sk_employee,
    person_number,
    legislation_code,
    COALESCE(lc.meaning, category) AS category,
    COALESCE(ls.meaning, disability_code, 'Unknown') AS documented_name,
    COALESCE(disability_type, disability_answer) AS self_declared_name,
    neurodiversity,
    accessibility_need,
    CAST(NULL AS STRING) AS disability_reason,
    CASE UPPER(COALESCE(status, ''))
        WHEN 'A' THEN 'Active'
        WHEN 'P' THEN 'Pending'
        WHEN 'I' THEN 'Inactive'
        ELSE COALESCE(status, 'Unknown')
    END AS disability_status,
    UPPER(COALESCE(status, '')) = 'A' AS is_active,
    ROW_NUMBER() OVER (
        PARTITION BY
            id_person,
            legislation_code
        ORDER BY
            COALESCE(quota_fte, 0) DESC,
            id_disability ASC
    ) = 1 AS is_primary,
    COALESCE(quota_fte, 0) > 0 AS is_quota_eligible,
    dt_valid_from,
    dt_valid_to,
    NOW() AS ts_load
FROM
    disability_enriched AS de
LEFT JOIN
    lookups AS lc
        ON lc.lookup_code = de.category
        AND lc.lookup_type = 'DISABILITY_CATEGORY'
LEFT JOIN
    lookups AS ls
        ON ls.lookup_code = de.disability_code
        AND ls.lookup_type = 'QA_DISABILITY_SUBCLAS'
