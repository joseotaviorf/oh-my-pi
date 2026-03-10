SELECT DISTINCT
  im.id_person,
  im.person_number,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(an.first_name, '[^a-zA-ZÀ-ÿ ]', ''), 
      ' +', ' ')
    )
  ) AS first_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(an.last_name, '[^a-zA-ZÀ-ÿ ]', ''), 
      ' +', ' ')
    )
  ) AS last_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(an.full_name, '[^a-zA-ZÀ-ÿ ]', ''), 
      ' +', ' ')
    )
  ) AS full_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(an.first_social_name, '[^a-zA-ZÀ-ÿ ]', ''), 
      ' +', ' ')
    )
  ) AS first_social_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(an.last_social_name, '[^a-zA-ZÀ-ÿ ]', ''), 
      ' +', ' ')
    )
  ) AS last_social_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(p.mother_name, '[^a-zA-ZÀ-ÿ ]', ''), 
      ' +', ' ')
    )
  ) AS mother_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(p.father_name, '[^a-zA-ZÀ-ÿ ]', ''), 
      ' +', ' ')
    )
  ) AS father_name,
  p.town_of_birth AS birth_town,
  p.region_of_birth AS birth_state,
  p.country_of_birth AS birth_country,
  DATE(p.dt_of_birth) AS dt_birth
FROM
  datalake_people.identifier_mapping AS im
INNER JOIN
  datalake_pin_core_clean.person AS p
    ON p.id_person = im.id_person
INNER JOIN 
  datalake_pin_core_clean.person_name AS an
    ON p.id_person = an.id_person
    AND an.name_type = 'GLOBAL'
    AND an.dt_effective_ended = '4712-12-31' 
WHERE 
  NOT im.is_user_test