WITH person_keys AS (
    SELECT
      im.id_person,
      im.person_number,
      im.legislation_code
    FROM
      datalake_people.identifier_mapping AS im
    WHERE
      im.is_person_latest_assignment = TRUE
      AND im.assignment_type IN ('E', 'C')
      AND NOT im.is_user_test
),
ethnicity_primary_ranked AS (
    SELECT
      id_person,
      legislation_code,
      ethnicity_code,
      ROW_NUMBER() OVER (
        PARTITION BY
          id_person,
          legislation_code
        ORDER BY
          ts_updated DESC
      ) AS rn
    FROM
      datalake_pin_core_clean.ethnicity
    WHERE
      is_primary
),
ethnicity_primary AS (
    SELECT
      id_person,
      legislation_code,
      ethnicity_code
    FROM
      ethnicity_primary_ranked
    WHERE
      rn = 1
),
religion_primary_ranked AS (
    SELECT
      id_person,
      legislation_code,
      religion_code,
      ROW_NUMBER() OVER (
        PARTITION BY
          id_person,
          legislation_code
        ORDER BY
          ts_updated DESC
      ) AS rn
    FROM
      datalake_pin_core_clean.religion
    WHERE
      is_primary
),
religion_primary AS (
    SELECT
      id_person,
      legislation_code,
      religion_code
    FROM
      religion_primary_ranked
    WHERE
      rn = 1
),
lookup_fnd_ranked AS (
    SELECT
      lookup_code,
      meaning,
      lookup_type,
      ROW_NUMBER() OVER (
        PARTITION BY
          lookup_type,
          lookup_code
        ORDER BY
          ts_updated DESC
      ) AS rn
    FROM
      datalake_pin_core_clean.foundation_lookup_value
    WHERE
      lookup_type IN (
        'PER_ETHNICITY',
        'ORA_PER_ETHNICITY',
        'PER_RELIGION',
        'QA_ORIENTACAO_SEXUAL'
      )
      AND language = 'US'
      AND (
        lookup_type IN ('PER_ETHNICITY', 'ORA_PER_ETHNICITY')
        OR (
          lookup_type IN ('PER_RELIGION', 'QA_ORIENTACAO_SEXUAL')
          AND is_enabled = TRUE
        )
      )
),
lookup_fnd AS (
    SELECT
      lookup_code,
      meaning,
      lookup_type
    FROM
      lookup_fnd_ranked
    WHERE
      rn = 1
),
pl_periods AS (
    SELECT
      pl.id_person,
      CAST(pl.id_person AS STRING) AS sk_employee,
      pk.person_number,
      pl.legislation_code,
      eth.ethnicity_code,
      rel.religion_code,
      pl.gender_identity,
      pl.sexual_orientation,
      pl.legal_sex,
      pl.neurodiversity,
      pl.disability_answer,
      DATE(pl.dt_effective_started) AS dt_period_start,
      COALESCE(
        NULLIF(DATE(pl.dt_effective_ended), DATE('4712-12-31')),
        DATE('9999-12-31')
      ) AS dt_period_end
    FROM
      datalake_pin_core_clean.people_legislative AS pl
    INNER JOIN
      person_keys AS pk
        ON pk.id_person = pl.id_person
        AND pk.legislation_code = pl.legislation_code
    LEFT JOIN
      ethnicity_primary AS eth
        ON eth.id_person = pl.id_person
        AND eth.legislation_code = pl.legislation_code
    LEFT JOIN
      religion_primary AS rel
        ON rel.id_person = pl.id_person
        AND rel.legislation_code = pl.legislation_code
),
missing_people_legislative AS (
    SELECT
      pk.id_person,
      CAST(pk.id_person AS STRING) AS sk_employee,
      pk.person_number,
      pk.legislation_code,
      CAST(NULL AS STRING) AS ethnicity_code,
      CAST(NULL AS STRING) AS religion_code,
      CAST(NULL AS STRING) AS gender_identity,
      CAST(NULL AS STRING) AS sexual_orientation,
      CAST(NULL AS STRING) AS legal_sex,
      CAST(NULL AS STRING) AS neurodiversity,
      CAST(NULL AS STRING) AS disability_answer,
      DATE('1900-01-01') AS dt_period_start,
      DATE('9999-12-31') AS dt_period_end
    FROM
      person_keys AS pk
    WHERE
      NOT EXISTS (
        SELECT
          1
        FROM
          datalake_pin_core_clean.people_legislative AS pl
        WHERE
          pl.id_person = pk.id_person
          AND pl.legislation_code = pk.legislation_code
      )
),
pl_periods_all AS (
    SELECT
      id_person,
      sk_employee,
      person_number,
      legislation_code,
      ethnicity_code,
      religion_code,
      gender_identity,
      sexual_orientation,
      legal_sex,
      neurodiversity,
      disability_answer,
      dt_period_start,
      dt_period_end
    FROM
      pl_periods
    UNION ALL
    SELECT
      id_person,
      sk_employee,
      person_number,
      legislation_code,
      ethnicity_code,
      religion_code,
      gender_identity,
      sexual_orientation,
      legal_sex,
      neurodiversity,
      disability_answer,
      dt_period_start,
      dt_period_end
    FROM
      missing_people_legislative
),
normalized AS (
    SELECT
      pp.id_person,
      pp.sk_employee,
      pp.person_number,
      pp.legislation_code,
      pp.dt_period_start,
      pp.dt_period_end,
      pp.ethnicity_code,
      COALESCE(
        NULLIF(TRIM(lk_eth_per.meaning), ''),
        NULLIF(TRIM(lk_eth_ora.meaning), ''),
        '-1'
      ) AS ethnicity,
      CASE
        WHEN pp.religion_code IS NULL OR pp.religion_code = 'NONE'
          THEN '-1'
        ELSE COALESCE(NULLIF(TRIM(lk_rel.meaning), ''), pp.religion_code)
      END AS religion,
      pp.gender_identity AS gender_identity_reported,
      CASE
        WHEN pp.legal_sex = 'F' THEN 'Female'
        WHEN pp.legal_sex = 'M' THEN 'Male'
        ELSE pp.legal_sex
      END AS legal_sex,
      CASE
        WHEN pp.gender_identity IN (
          'Mulher cisgênero',
          'Cisgender woman',
          'Mujer Cisgénero (Cis)',
          'Mulher Cis'
        )
          THEN 'Woman Cisgender'
        WHEN pp.gender_identity IN (
          'Mulher transgênero',
          'Transgender woman',
          'Mujer Transgénero (Trans)',
          'Mulher Trans ou Travesti'
        )
          THEN 'Woman Transgender'
        WHEN pp.gender_identity IN (
          'Homem cisgênero',
          'Cisgender man',
          'Hombre Cisgénero (Cis)',
          'Homem Cis'
        )
          THEN 'Man Cisgender'
        WHEN pp.gender_identity IN (
          'Homem transgênero',
          'Transgender man',
          'Hombre Transgénero (Trans)',
          'HomemTrans'
        )
          THEN 'Man Transgender'
        WHEN pp.gender_identity IN (
          'Não-binário',
          'Non-binary',
          'Género no binario',
          'Gênero Não-binária'
        )
          THEN 'Non Binary'
        WHEN pp.gender_identity IN (
          'Outro',
          'Other',
          'Otro',
          'Demi-genero',
          'Gênero Fluido',
          'Homem Trans Não-binário'
        )
          THEN 'Other'
        WHEN pp.gender_identity IN (
          'Prefiro não informar',
          'I''d rather not answer',
          'Prefiero no responder'
        )
          THEN 'Prefer Not To Say'
        ELSE '-1'
      END AS gender_identity,
      CASE
        WHEN pp.sexual_orientation IS NULL OR TRIM(COALESCE(pp.sexual_orientation, '')) = ''
          THEN '-1'
        ELSE COALESCE(lk_so.meaning, lk_so_hom.meaning, '-1')
      END AS sexual_orientation,
      COALESCE(pp.neurodiversity, '-1') AS neurodiversity,
      CASE
        WHEN UPPER(COALESCE(pp.disability_answer, '')) IN ('SIM', 'S', 'Y', 'YES')
          THEN TRUE
        WHEN UPPER(COALESCE(pp.disability_answer, '')) IN ('NÃO', 'NAO', 'N')
          THEN FALSE
        ELSE NULL
      END AS has_self_declared_pwd_raw
    FROM
      pl_periods_all AS pp
    LEFT JOIN
      lookup_fnd AS lk_eth_per
        ON lk_eth_per.lookup_code = pp.ethnicity_code
        AND lk_eth_per.lookup_type = 'PER_ETHNICITY'
    LEFT JOIN
      lookup_fnd AS lk_eth_ora
        ON lk_eth_ora.lookup_code = pp.ethnicity_code
        AND lk_eth_ora.lookup_type = 'ORA_PER_ETHNICITY'
    LEFT JOIN
      lookup_fnd AS lk_rel
        ON lk_rel.lookup_code = pp.religion_code
        AND lk_rel.lookup_type = 'PER_RELIGION'
    LEFT JOIN
      lookup_fnd AS lk_so
        ON lk_so.lookup_code = TRIM(
          REGEXP_REPLACE(COALESCE(pp.sexual_orientation, ''), '^[0-9]+\\s*-\\s*', '')
        )
        AND lk_so.lookup_type = 'QA_ORIENTACAO_SEXUAL'
    LEFT JOIN
      lookup_fnd AS lk_so_hom
        ON lk_so_hom.lookup_code = 'Homossexual'
        AND lk_so_hom.lookup_type = 'QA_ORIENTACAO_SEXUAL'
        AND TRIM(
          REGEXP_REPLACE(COALESCE(pp.sexual_orientation, ''), '^[0-9]+\\s*-\\s*', '')
        ) IN ('Homosexual', 'Homossexual')
),
with_medical_disability_record AS (
    SELECT
      n.id_person,
      n.sk_employee,
      n.person_number,
      n.legislation_code,
      n.dt_period_start,
      n.dt_period_end,
      n.ethnicity_code,
      n.ethnicity,
      n.religion,
      n.gender_identity_reported,
      n.gender_identity,
      n.sexual_orientation,
      n.legal_sex,
      n.neurodiversity,
      n.has_self_declared_pwd_raw,
      EXISTS (
        SELECT
          1
        FROM
          datalake_pin_core_clean.disability AS d
        WHERE
          d.id_person = n.id_person
          AND d.legislation_code = n.legislation_code
          AND COALESCE(UPPER(d.status), '') = 'A'
          AND DATE(d.dt_effective_started) <= n.dt_period_end
          AND COALESCE(
            NULLIF(DATE(d.dt_effective_ended), DATE('4712-12-31')),
            DATE('9999-12-31')
          ) >= n.dt_period_start
      ) AS has_medical_disability_record
    FROM
      normalized AS n
),
with_flags AS (
    SELECT
      id_person,
      sk_employee,
      person_number,
      legislation_code,
      dt_period_start,
      dt_period_end,
      ethnicity,
      religion,
      gender_identity_reported,
      gender_identity,
      sexual_orientation,
      legal_sex,
      neurodiversity,
      ethnicity_code,
      CASE
        WHEN legislation_code <> 'BR'
          THEN NULL
        WHEN ethnicity = '-1'
          THEN NULL
        WHEN ethnicity_code IN (
          '1', -- Indigenous
          '3', -- Black
          '4', -- Black
          '7', -- Indigenous
          '8', -- Brown
          '15', -- Black
          '20', -- Brown
          '60', -- Indigenous
          'ORA_HRX_BRIN', -- Brazilian Indigenous
          'ORA_HRX_MIXED' -- Mixed race
        )
          THEN TRUE
        ELSE FALSE
      END AS is_underrepresented_race,
      CASE
        WHEN sexual_orientation NOT IN ('-1', 'Heterosexual')
          OR gender_identity IN (
            'Woman Transgender',
            'Man Transgender',
            'Non Binary',
            'Other'
          )
          THEN TRUE
        WHEN sexual_orientation = '-1' AND gender_identity = '-1'
          THEN NULL
        ELSE FALSE
      END AS is_lgbtqia,
      CASE
        WHEN gender_identity = '-1'
          OR gender_identity = 'Prefer Not To Say'
          THEN NULL
        WHEN gender_identity IN (
          'Woman Cisgender',
          'Woman Transgender',
          'Man Transgender',
          'Non Binary',
          'Other'
        )
          THEN TRUE
        WHEN gender_identity = 'Man Cisgender'
          THEN FALSE
        ELSE FALSE
      END AS is_underrepresented_gender,
      CASE
        WHEN gender_identity IN ('Woman Cisgender', 'Woman Transgender')
          THEN TRUE
        WHEN gender_identity = '-1'
          THEN NULL
        ELSE FALSE
      END AS is_woman,
      CASE
        WHEN neurodiversity IS NULL
          OR LENGTH(TRIM(COALESCE(neurodiversity, ''))) = 0
          OR neurodiversity = '-1'
          THEN NULL
        WHEN LOWER(TRIM(neurodiversity)) IN (
          '.',
          'neurotypical',
          'i''m not a neuro minority person',
          'n/a',
          'não',
          'nao',
          'não informado',
          'nao informado',
          'não se aplica',
          'nao se aplica',
          'nenhum',
          'normal',
          'i''d rather not answer',
          'um cara bem de boas'
        )
          THEN FALSE
        WHEN LOWER(TRIM(neurodiversity)) = 'other'
          THEN NULL
        ELSE TRUE
      END AS is_neurodivergent,
      has_self_declared_pwd_raw AS has_self_declared_pwd,
      has_medical_disability_record
    FROM
      with_medical_disability_record
),
with_underrepresented_group AS (
    SELECT
      *,
      (
        COALESCE(is_underrepresented_race, FALSE)
        OR gender_identity IN ('Woman Cisgender', 'Woman Transgender')
        OR COALESCE(is_lgbtqia, FALSE)
        OR COALESCE(has_medical_disability_record, FALSE)
      ) AS is_underrepresented_group
    FROM
      with_flags
),
with_sig AS (
    SELECT
      *,
      CONCAT_WS(
        '|',
        legislation_code,
        ethnicity,
        religion,
        gender_identity_reported,
        gender_identity,
        sexual_orientation,
        legal_sex,
        neurodiversity,
        CAST(is_underrepresented_race AS STRING),
        CAST(is_lgbtqia AS STRING),
        CAST(is_underrepresented_gender AS STRING),
        CAST(is_neurodivergent AS STRING),
        CAST(has_self_declared_pwd AS STRING),
        CAST(has_medical_disability_record AS STRING),
        CAST(is_woman AS STRING),
        CAST(is_underrepresented_group AS STRING)
      ) AS attr_sig
    FROM
      with_underrepresented_group
),
with_prev AS (
    SELECT
      id_person,
      sk_employee,
      person_number,
      legislation_code,
      dt_period_start,
      dt_period_end,
      ethnicity,
      religion,
      gender_identity_reported,
      gender_identity,
      sexual_orientation,
      legal_sex,
      neurodiversity,
      ethnicity_code,
      is_underrepresented_race,
      is_lgbtqia,
      is_underrepresented_gender,
      is_woman,
      is_neurodivergent,
      has_self_declared_pwd,
      has_medical_disability_record,
      is_underrepresented_group,
      attr_sig,
      LAG(attr_sig) OVER (
        PARTITION BY
          id_person,
          legislation_code
        ORDER BY
          dt_period_start,
          dt_period_end
      ) AS prev_sig
    FROM
      with_sig
),
with_grp AS (
    SELECT
      id_person,
      sk_employee,
      person_number,
      legislation_code,
      dt_period_start,
      dt_period_end,
      ethnicity,
      religion,
      gender_identity_reported,
      gender_identity,
      sexual_orientation,
      legal_sex,
      neurodiversity,
      ethnicity_code,
      is_underrepresented_race,
      is_lgbtqia,
      is_underrepresented_gender,
      is_woman,
      is_neurodivergent,
      has_self_declared_pwd,
      has_medical_disability_record,
      is_underrepresented_group,
      attr_sig,
      prev_sig,
      SUM(
        CASE
          WHEN prev_sig IS NULL OR attr_sig <> prev_sig
            THEN 1
          ELSE 0
        END
      ) OVER (
        PARTITION BY
          id_person,
          legislation_code
        ORDER BY
          dt_period_start,
          dt_period_end
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS grp_id
    FROM
      with_prev
)
SELECT
    ANY_VALUE(sk_employee) AS sk_employee,
    ANY_VALUE(person_number) AS person_number,
    ANY_VALUE(legislation_code) AS legislation_code,
    ANY_VALUE(ethnicity) AS ethnicity,
    ANY_VALUE(religion) AS religion,
    ANY_VALUE(gender_identity_reported) AS gender_identity_reported,
    ANY_VALUE(gender_identity) AS gender_identity,
    ANY_VALUE(sexual_orientation) AS sexual_orientation,
    ANY_VALUE(legal_sex) AS legal_sex,
    ANY_VALUE(is_underrepresented_race) AS is_underrepresented_race,
    ANY_VALUE(is_lgbtqia) AS is_lgbtqia,
    ANY_VALUE(is_underrepresented_gender) AS is_underrepresented_gender,
    ANY_VALUE(is_woman) AS is_woman,
    ANY_VALUE(is_neurodivergent) AS is_neurodivergent,
    ANY_VALUE(has_self_declared_pwd) AS has_self_declared_pwd,
    ANY_VALUE(has_medical_disability_record) AS has_medical_disability_record,
    ANY_VALUE(is_underrepresented_group) AS is_underrepresented_group,
    (
      MIN(dt_period_start) <= CURRENT_DATE
      AND MAX(dt_period_end) >= CURRENT_DATE
    ) AS is_current,
    MIN(dt_period_start) AS dt_valid_from,
    MAX(dt_period_end) AS dt_valid_to,
    NOW() AS ts_load
FROM
    with_grp
GROUP BY
    id_person,
    legislation_code,
    grp_id
