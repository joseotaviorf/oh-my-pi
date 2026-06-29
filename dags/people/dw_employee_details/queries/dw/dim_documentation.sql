WITH
valid_employees AS (
    SELECT DISTINCT
        im.id_person
    FROM
        datalake_people.identifier_mapping AS im
    WHERE
        NOT im.is_user_test
        AND im.assignment_type IN ('C', 'E')
),
all_change_dates AS (
    SELECT
        ap.id_person,
        ap.dt_effective_started AS change_date
    FROM
        datalake_pin_core_clean.all_people AS ap
    UNION
    SELECT
        ni.id_person,
        DATE(ni.ts_updated) AS change_date
    FROM
        datalake_pin_core_clean.national_identifiers AS ni
    WHERE
        ni.legislation_code = 'BR'
        AND ni.ts_updated IS NOT NULL
    UNION
    SELECT
        pl.id_person,
        pl.dt_effective_started AS change_date
    FROM
        datalake_pin_core_clean.people_legislative AS pl
    WHERE
        pl.legislation_code = 'BR'
    UNION
    SELECT
        pl.id_person,
        date_add(pl.dt_effective_ended, 1) AS change_date
    FROM
        datalake_pin_core_clean.people_legislative AS pl
    WHERE
        pl.legislation_code = 'BR'
        AND pl.dt_effective_ended < DATE('9999-12-31')
    UNION
    SELECT
        pn.id_person,
        pn.dt_effective_started AS change_date
    FROM
        datalake_pin_core_clean.person_name AS pn
    WHERE
        pn.legislation_code = 'BR'
    UNION
    SELECT
        pn.id_person,
        date_add(pn.dt_effective_ended, 1) AS change_date
    FROM
        datalake_pin_core_clean.person_name AS pn
    WHERE
        pn.legislation_code = 'BR'
        AND pn.dt_effective_ended < DATE('9999-12-31')
    UNION
    SELECT
        p.id_person,
        DATE(p.ts_updated) AS change_date
    FROM
        datalake_pin_core_clean.person AS p
    INNER JOIN
        valid_employees AS emp
        ON p.id_person = emp.id_person
    WHERE
        p.ts_updated IS NOT NULL
),
person_periods AS (
    SELECT
        acd.id_person,
        acd.change_date AS dt_valid_from,
        COALESCE(
            date_add(
                LEAD(acd.change_date) OVER (
                    PARTITION BY
                        acd.id_person
                    ORDER BY
                        acd.change_date
                ),
                -1
            ),
            DATE('9999-12-31')
        ) AS dt_valid_to
    FROM
        all_change_dates AS acd
    INNER JOIN
        valid_employees AS emp
            ON acd.id_person = emp.id_person
    WHERE
        acd.change_date <= DATE('{load_start_date}')
),
person_numbers AS (
    SELECT
        ap.id_person,
        ap.person_number,
        ROW_NUMBER() OVER (
            PARTITION BY
                ap.id_person
            ORDER BY
                ap.dt_effective_started DESC
        ) AS rn
    FROM
        datalake_pin_core_clean.all_people AS ap
    INNER JOIN
        valid_employees AS emp
            ON ap.id_person = emp.id_person
),
legal_names AS (
    SELECT
        pr.id_person,
        pr.dt_valid_from,
        pn.documented_full_name AS legal_name,
        ROW_NUMBER() OVER (
            PARTITION BY
                pr.id_person,
                pr.dt_valid_from
            ORDER BY
                pn.dt_effective_started DESC
        ) AS rn
    FROM
        person_periods AS pr
    INNER JOIN
        datalake_pin_core_clean.person_name AS pn
            ON pr.id_person = pn.id_person
            AND pn.legislation_code = 'BR'
            AND pn.dt_effective_started <= pr.dt_valid_from
            AND (
                pn.dt_effective_ended >= pr.dt_valid_from
                OR pn.dt_effective_ended = DATE('9999-12-31')
            )
),
legislative_info AS (
    SELECT
        pr.id_person,
        pr.dt_valid_from,
        pl.marital_status,
        pl.ctps_number,
        pl.ctps_series,
        pl.vote_registration_number AS electoral_registration_number,
        pl.electoral_zone,
        pl.polling_station AS electoral_polling_station,
        ROW_NUMBER() OVER (
            PARTITION BY
                pr.id_person,
                pr.dt_valid_from
            ORDER BY
                pl.dt_effective_started DESC
        ) AS rn
    FROM
        person_periods AS pr
    INNER JOIN
        datalake_pin_core_clean.people_legislative AS pl
            ON pr.id_person = pl.id_person
            AND pl.legislation_code = 'BR'
            AND pl.dt_effective_started <= pr.dt_valid_from
            AND (
                pl.dt_effective_ended >= pr.dt_valid_from
                OR pl.dt_effective_ended = DATE('9999-12-31')
            )
),
national_ids AS (
    SELECT
        pr.id_person,
        pr.dt_valid_from,
        ni.national_identifier_type,
        ni.national_identifier_number,
        ni.issuing_state,
        ni.issuing_authority,
        ROW_NUMBER() OVER (
            PARTITION BY
                pr.id_person,
                pr.dt_valid_from,
                ni.national_identifier_type
            ORDER BY
                ni.ts_updated DESC
        ) AS rn
    FROM
        person_periods AS pr
    INNER JOIN
        datalake_pin_core_clean.national_identifiers AS ni
            ON pr.id_person = ni.id_person
            AND ni.legislation_code = 'BR'
            AND DATE(ni.ts_updated) <= pr.dt_valid_from
            AND ni.national_identifier_type IN ('CPF', 'RG', 'PIS')
),
birth_info AS (
    SELECT
        pr.id_person,
        pr.dt_valid_from,
        p.mother_name,
        p.father_name,
        p.town_of_birth AS birth_town,
        p.region_of_birth AS birth_state,
        p.country_of_birth AS birth_country,
        ROW_NUMBER() OVER (
            PARTITION BY
                pr.id_person,
                pr.dt_valid_from
            ORDER BY
                p.ts_updated DESC
        ) AS rn
    FROM
        person_periods AS pr
    LEFT JOIN
        datalake_pin_core_clean.person AS p
        ON pr.id_person = p.id_person
        AND DATE(p.ts_updated) <= pr.dt_valid_from
),
daily_snapshot AS (
    SELECT
        pr.id_person,
        pn.person_number,
        pr.dt_valid_from,
        pr.dt_valid_to,
        ln.legal_name,
        bi.mother_name,
        bi.father_name,
        bi.birth_town,
        bi.birth_state,
        bi.birth_country,
        COALESCE(flv.meaning, li.marital_status) AS marital_status,
        li.ctps_number,
        li.ctps_series,
        li.electoral_registration_number,
        li.electoral_zone,
        li.electoral_polling_station,
        cpf.national_identifier_number AS cpf,
        rg.national_identifier_number AS rg,
        rg.issuing_state AS rg_issuing_state,
        rg.issuing_authority AS rg_issuing_authority,
        pis.national_identifier_number AS pis
    FROM
        person_periods AS pr
    LEFT JOIN
        person_numbers AS pn
            ON pr.id_person = pn.id_person
            AND pn.rn = 1
    LEFT JOIN
        legal_names AS ln
            ON pr.id_person = ln.id_person
            AND pr.dt_valid_from = ln.dt_valid_from
            AND ln.rn = 1
    LEFT JOIN
        birth_info AS bi
            ON pr.id_person = bi.id_person
            AND pr.dt_valid_from = bi.dt_valid_from
            AND bi.rn = 1
    LEFT JOIN
        legislative_info AS li
            ON pr.id_person = li.id_person
            AND pr.dt_valid_from = li.dt_valid_from
            AND li.rn = 1
    LEFT JOIN
        datalake_pin_core_clean.foundation_lookup_value AS flv
            ON li.marital_status = flv.lookup_code
            AND flv.lookup_type = 'MAR_STATUS'
            AND flv.language = 'PTB'
    LEFT JOIN
        national_ids AS cpf
            ON pr.id_person = cpf.id_person
            AND pr.dt_valid_from = cpf.dt_valid_from
            AND cpf.national_identifier_type = 'CPF'
            AND cpf.rn = 1
    LEFT JOIN
        national_ids AS rg
            ON pr.id_person = rg.id_person
            AND pr.dt_valid_from = rg.dt_valid_from
            AND rg.national_identifier_type = 'RG'
            AND rg.rn = 1
    LEFT JOIN
        national_ids AS pis
            ON pr.id_person = pis.id_person
            AND pr.dt_valid_from = pis.dt_valid_from
            AND pis.national_identifier_type = 'PIS'
            AND pis.rn = 1
),
snapshot_with_changes AS (
    SELECT
        ds.id_person,
        ds.person_number,
        ds.dt_valid_from,
        ds.dt_valid_to,
        ds.legal_name,
        ds.mother_name,
        ds.father_name,
        ds.birth_town,
        ds.birth_state,
        ds.birth_country,
        ds.marital_status,
        ds.cpf,
        ds.rg,
        ds.rg_issuing_state,
        ds.rg_issuing_authority,
        ds.pis,
        ds.ctps_number,
        ds.ctps_series,
        ds.electoral_registration_number,
        ds.electoral_zone,
        ds.electoral_polling_station,
        CASE
            WHEN
                COALESCE(ds.legal_name, '') != COALESCE(LAG(ds.legal_name) OVER w, '')
                OR COALESCE(ds.mother_name, '') != COALESCE(LAG(ds.mother_name) OVER w, '')
                OR COALESCE(ds.father_name, '') != COALESCE(LAG(ds.father_name) OVER w, '')
                OR COALESCE(ds.birth_town, '') != COALESCE(LAG(ds.birth_town) OVER w, '')
                OR COALESCE(ds.birth_state, '') != COALESCE(LAG(ds.birth_state) OVER w, '')
                OR COALESCE(ds.birth_country, '') != COALESCE(LAG(ds.birth_country) OVER w, '')
                OR COALESCE(ds.marital_status, '') != COALESCE(LAG(ds.marital_status) OVER w, '')
                OR COALESCE(ds.cpf, '') != COALESCE(LAG(ds.cpf) OVER w, '')
                OR COALESCE(ds.rg, '') != COALESCE(LAG(ds.rg) OVER w, '')
                OR COALESCE(ds.rg_issuing_state, '') != COALESCE(LAG(ds.rg_issuing_state) OVER w, '')
                OR COALESCE(ds.rg_issuing_authority, '') != COALESCE(
                    LAG(ds.rg_issuing_authority) OVER w,
                    ''
                )
                OR COALESCE(ds.pis, '') != COALESCE(LAG(ds.pis) OVER w, '')
                OR COALESCE(ds.ctps_number, '') != COALESCE(LAG(ds.ctps_number) OVER w, '')
                OR COALESCE(ds.ctps_series, '') != COALESCE(LAG(ds.ctps_series) OVER w, '')
                OR COALESCE(ds.electoral_registration_number, '') != COALESCE(
                    LAG(ds.electoral_registration_number) OVER w,
                    ''
                )
                OR COALESCE(ds.electoral_zone, '') != COALESCE(LAG(ds.electoral_zone) OVER w, '')
                OR COALESCE(ds.electoral_polling_station, '') != COALESCE(
                    LAG(ds.electoral_polling_station) OVER w,
                    ''
                )
                OR LAG(ds.dt_valid_from) OVER w IS NULL
            THEN 1
            ELSE 0
        END AS is_new_island
    FROM
        daily_snapshot AS ds
    WINDOW
        w AS (
            PARTITION BY
                ds.id_person
            ORDER BY
                ds.dt_valid_from
        )
),
islands_grouped AS (
    SELECT
        swc.id_person,
        swc.person_number,
        swc.dt_valid_from,
        swc.dt_valid_to,
        swc.legal_name,
        swc.mother_name,
        swc.father_name,
        swc.birth_town,
        swc.birth_state,
        swc.birth_country,
        swc.marital_status,
        swc.cpf,
        swc.rg,
        swc.rg_issuing_state,
        swc.rg_issuing_authority,
        swc.pis,
        swc.ctps_number,
        swc.ctps_series,
        swc.electoral_registration_number,
        swc.electoral_zone,
        swc.electoral_polling_station,
        SUM(swc.is_new_island) OVER (
            PARTITION BY
                swc.id_person
            ORDER BY
                swc.dt_valid_from
        ) AS island_id
    FROM
        snapshot_with_changes AS swc
),
merged_periods AS (
    SELECT
        ig.id_person,
        ig.person_number,
        MIN(ig.dt_valid_from) AS dt_valid_from,
        MAX(ig.dt_valid_to) AS dt_valid_to,
        ig.legal_name,
        ig.mother_name,
        ig.father_name,
        ig.birth_town,
        ig.birth_state,
        ig.birth_country,
        ig.marital_status,
        ig.cpf,
        ig.rg,
        ig.rg_issuing_state,
        ig.rg_issuing_authority,
        ig.pis,
        ig.ctps_number,
        ig.ctps_series,
        ig.electoral_registration_number,
        ig.electoral_zone,
        ig.electoral_polling_station
    FROM
        islands_grouped AS ig
    GROUP BY
        ig.id_person,
        ig.person_number,
        ig.island_id,
        ig.legal_name,
        ig.mother_name,
        ig.father_name,
        ig.birth_town,
        ig.birth_state,
        ig.birth_country,
        ig.marital_status,
        ig.cpf,
        ig.rg,
        ig.rg_issuing_state,
        ig.rg_issuing_authority,
        ig.pis,
        ig.ctps_number,
        ig.ctps_series,
        ig.electoral_registration_number,
        ig.electoral_zone,
        ig.electoral_polling_station
)
SELECT
    MD5(
        CONCAT_WS(
            '|',
            CAST(mp.id_person AS STRING),
            CAST(mp.dt_valid_from AS STRING)
        )
    ) AS sk_documentation_version,
    mp.person_number,
    mp.marital_status,
    mp.legal_name,
    mp.mother_name,
    mp.father_name,
    mp.birth_town,
    mp.birth_state,
    mp.birth_country,
    mp.cpf,
    mp.rg,
    mp.rg_issuing_state,
    mp.rg_issuing_authority,
    mp.pis,
    mp.ctps_number,
    mp.ctps_series,
    mp.electoral_registration_number,
    mp.electoral_zone,
    mp.electoral_polling_station,
    mp.dt_valid_from,
    mp.dt_valid_to,
    (
        mp.dt_valid_from <= DATE('{load_start_date}')
        AND mp.dt_valid_to >= DATE('{load_start_date}')
    ) AS is_current,
    NOW() AS ts_load
FROM
    merged_periods AS mp
