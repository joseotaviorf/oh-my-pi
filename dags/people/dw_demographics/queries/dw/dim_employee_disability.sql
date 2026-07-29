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
lookups_ranked AS (
    SELECT
        lookup_code,
        meaning,
        lookup_type,
        ROW_NUMBER() OVER (
            PARTITION BY
                lookup_type,
                lookup_code
            ORDER BY
                CASE
                    WHEN language = 'US' THEN 0
                    WHEN language = 'PTB' THEN 1
                    ELSE 2
                END,
                ts_updated DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.foundation_lookup_value
    WHERE
        lookup_type IN (
            'DISABILITY_CATEGORY',
            'QA_DISABILITY_SUBCLAS',
            'QA_DEF_AUTODECLARADA',
            'QA_NEURODIVERSIDADE'
        )
        AND language IN ('PTB', 'US')
        AND is_enabled = TRUE
),
lookups AS (
    SELECT
        lookup_code,
        meaning,
        lookup_type
    FROM
        lookups_ranked
    WHERE
        rn = 1
),
disability_enriched_ranked AS (
    SELECT
        d.id_person,
        pk.person_number,
        d.legislation_code,
        d.id_disability,
        d.disability_code,
        d.category,
        d.status,
        d.quota_fte,
        d.disability_description,
        d.work_restriction,
        d.accommodation_request,
        d.documented_subclassification,
        d.clinical_classification_code,
        pl.accessibility_need,
        pl.neurodiversity AS neurodiversity_code,
        pl.disability_answer,
        pl.disability_type,
        d.dt_effective_started AS dt_valid_from,
        d.dt_effective_ended AS dt_valid_to,
        ROW_NUMBER() OVER (
            PARTITION BY
                d.id_disability,
                d.dt_effective_started,
                d.dt_effective_ended
            ORDER BY
                d.ts_updated DESC,
                pl.dt_effective_started DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.disability AS d
    INNER JOIN
        person_keys AS pk
            ON d.id_person = pk.id_person
    LEFT JOIN
        datalake_pin_core_clean.people_legislative AS pl
            ON pl.id_person = d.id_person
            AND pl.legislation_code = d.legislation_code
            AND pl.dt_effective_started <= d.dt_effective_ended
            AND pl.dt_effective_ended >= d.dt_effective_started
),
disability_enriched AS (
    SELECT
        id_person,
        person_number,
        legislation_code,
        id_disability,
        disability_code,
        category,
        status,
        quota_fte,
        disability_description,
        work_restriction,
        accommodation_request,
        documented_subclassification,
        clinical_classification_code,
        accessibility_need,
        neurodiversity_code,
        disability_answer,
        disability_type,
        dt_valid_from,
        dt_valid_to
    FROM
        disability_enriched_ranked
    WHERE
        rn = 1
)
SELECT
    CAST(id_person AS STRING) AS sk_employee,
    person_number,
    legislation_code,
    COALESCE(lc.meaning, category) AS category,
    COALESCE(
        de.documented_subclassification,
        de.disability_description,
        ls.meaning,
        disability_code,
        'Unknown'
    ) AS documented_name,
    documented_subclassification,
    disability_description,
    work_restriction,
    accommodation_request,
    clinical_classification_code,
    COALESCE(
        lt.meaning,
        de.disability_type,
        CASE
            WHEN UPPER(TRIM(COALESCE(de.disability_answer, ''))) NOT IN (
                'SIM', 'S', 'Y', 'YES', 'NÃO', 'NAO', 'N', 'NO', ''
            )
                THEN COALESCE(la.meaning, de.disability_answer)
            ELSE NULL
        END
    ) AS self_declared_name,
    CASE
        WHEN UPPER(TRIM(COALESCE(disability_answer, ''))) IN ('SIM', 'S', 'Y', 'YES')
            THEN TRUE
        WHEN UPPER(TRIM(COALESCE(disability_answer, ''))) IN ('NÃO', 'NAO', 'N')
            THEN FALSE
        ELSE NULL
    END AS has_self_declared_disability,
    COALESCE(ln.meaning, de.neurodiversity_code) AS neurodiversity,
    CASE
        WHEN UPPER(TRIM(COALESCE(accessibility_need, ''))) IN ('SIM', 'S', 'Y', 'YES')
            THEN TRUE
        WHEN UPPER(TRIM(COALESCE(accessibility_need, ''))) IN ('NÃO', 'NAO', 'N')
            THEN FALSE
        ELSE NULL
    END AS has_accessibility_need,
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
LEFT JOIN
    lookups AS lt
        ON lt.lookup_code = de.disability_type
        AND lt.lookup_type = 'QA_DEF_AUTODECLARADA'
LEFT JOIN
    lookups AS la
        ON la.lookup_code = de.disability_answer
        AND la.lookup_type = 'QA_DEF_AUTODECLARADA'
LEFT JOIN
    lookups AS ln
        ON ln.lookup_code = de.neurodiversity_code
        AND ln.lookup_type = 'QA_NEURODIVERSIDADE'
