WITH
  base_data AS (
    SELECT
      a.id_application,
      q.id AS id_question,
      ao.id AS id_answer,
      q.name AS question,
      ao.name AS answer_original,
      a.free_form_text AS answer_open_text,
      q.language AS question_language,
      q.is_required AS is_required_question,
      a.ts_updated
    FROM
      datalake_greenhouse_clean.demographics_answers AS a
    LEFT JOIN 
      datalake_greenhouse_clean.demographics_questions AS q
        ON a.id_demographic_question = q.id
    LEFT JOIN
      datalake_greenhouse_clean.demographics_answer_options AS ao
        ON a.id_demographic_answer_option = ao.id
  ),
  
  race_ethnicity AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      CASE
        WHEN id_answer IN (4022931009, 4023190009, 4023232009) THEN 'White'
        WHEN id_answer IN (4022933009, 4023191009, 4023234009) THEN 'Black or African American'
        WHEN id_answer IN (4022932009, 4023192009, 4023233009) THEN 'Two or more races'
        WHEN id_answer IN (4022935009, 4023194009, 4023236009) THEN 'Asian'
        WHEN id_answer IN (4022934009, 4023193009, 4023235009) THEN 'American Indian'
        WHEN id_answer IN (4022936009, 4023195009, 4023237009) THEN 'I dont wish to answer'
        ELSE CONCAT(answer_original, '*')
      END AS answer,
      answer_open_text,
      is_required_question,
      ts_updated
    FROM base_data
    WHERE id_question IN (4003820009, 4003863009, 4003870009)
  ),
  race_ethnicity_enriched AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      answer,
      answer_open_text,
      is_required_question,
      ts_updated,
      CASE
        WHEN answer = 'White' THEN false
        WHEN answer = 'I dont wish to answer' THEN NULL
        ELSE true
      END AS is_race_ethnicity_minority
    FROM race_ethnicity
  ),
  
  gender_identity AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      CASE
        WHEN id_answer IN (4022939009, 4023198009, 4023240009) THEN 'Cisgender Man'
        WHEN id_answer IN (4022937009, 4023196009, 4023238009) THEN 'Cisgender Woman'
        WHEN id_answer IN (4022940009, 4023199009, 4023241009) THEN 'Transgender Man'
        WHEN id_answer IN (4022938009, 4023197009, 4023239009) THEN 'Transgender Woman'
        WHEN id_answer IN (4022941009, 4023200009, 4023242009) THEN 'Non-binary'
        WHEN id_answer IN (4022942009, 4023201009, 4023243009) THEN 'Other'
        WHEN id_answer IN (4022943009, 4023202009, 4023244009) THEN 'I dont wish to answer'
        ELSE CONCAT(answer_original, '*')
      END AS answer,
      answer_open_text,
      is_required_question,
      ts_updated
    FROM base_data
    WHERE id_question IN (4003821009, 4003864009, 4003871009)
  ),
  gender_identity_enriched AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      answer,
      answer_open_text,
      is_required_question,
      ts_updated,
      CASE
        WHEN answer IN ('Cisgender Man', 'Cisgender Woman') THEN false
        WHEN answer = 'I dont wish to answer' THEN NULL
        ELSE true
      END AS is_gender_identity_minority,
      CASE
        WHEN answer IN ('Cisgender Woman', 'Transgender Woman') THEN true
        WHEN answer IN ('Cisgender Man', 'Transgender Man') THEN false
        ELSE NULL
      END AS is_woman
    FROM gender_identity
  ),
  
  sexual_orientation AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      CASE
        WHEN id_answer IN (4022944009, 4023203009, 4023245009) THEN 'Asexual'
        WHEN id_answer IN (4022945009, 4023204009, 4023246009) THEN 'Bisexual'
        WHEN id_answer IN (4022948009, 4023207009, 4023249009) THEN 'Heterosexual'
        WHEN id_answer IN (4022947009, 4023206009, 4023248009) THEN 'Homosexual'
        WHEN id_answer IN (4022946009, 4023205009, 4023247009) THEN 'Pansexual'
        WHEN id_answer IN (4022949009, 4023208009, 4023250009) THEN 'Other'
        WHEN id_answer IN (4022950009, 4023209009, 4023251009) THEN 'I dont wish to answer'
        ELSE CONCAT(answer_original, '*')
      END AS answer,
      answer_open_text,
      is_required_question,
      ts_updated
    FROM base_data
    WHERE id_question IN (4003822009, 4003865009, 4003872009)
  ),
  sexual_orientation_enriched AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      answer,
      answer_open_text,
      is_required_question,
      ts_updated,
      CASE
        WHEN answer = 'Heterosexual' THEN false
        WHEN answer = 'I dont wish to answer' THEN NULL
        ELSE true
      END AS is_sexual_orientation_minority
    FROM sexual_orientation
  ),
  
  neurodiversity AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      CASE
        WHEN id_answer IN (4022964009, 4023223009, 4023265009) THEN 'Autism Spectrum Disorder (ASD)'
        WHEN id_answer IN (4022965009, 4023224009, 4023266009) THEN 'Attention Deficit Hyperactivity Disorder (ADHD)'
        WHEN id_answer IN (4022966009, 4023225009) THEN 'Dyslexia'
        WHEN id_answer IN (4022967009) THEN 'Dyspraxia'
        WHEN id_answer IN (4022963009, 4023222009, 4023264009) THEN 'I do not consider myself a neurodivergent person'
        WHEN id_answer IN (4022968009, 4023227009, 4023269009) THEN 'Other'
        WHEN id_answer IN (4022969009, 4023228009, 4023270009) THEN 'I dont wish to answer'
        ELSE CONCAT(answer_original, '*')
      END AS answer,
      answer_open_text,
      is_required_question,
      ts_updated
    FROM base_data
    WHERE id_question IN (4003825009, 4003868009, 4003875009)
  ),
  neurodiversity_enriched AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      answer,
      answer_open_text,
      is_required_question,
      ts_updated,
      CASE
        WHEN answer = 'I do not consider myself a neurodivergent person' THEN false
        WHEN answer = 'I dont wish to answer' THEN NULL
        ELSE true
      END AS is_neurodiversity_minority
    FROM neurodiversity
  ),
  
  has_disability AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      CASE
        WHEN id_answer IN (4022951009, 4023210009, 4023252009) THEN 'Yes'
        WHEN id_answer IN (4022952009, 4023211009, 4023253009) THEN 'No'
        WHEN id_answer IN (4022953009, 4023212009, 4023254009) THEN 'I dont wish to answer'
        ELSE CONCAT(answer_original, '*')
      END AS answer,
      answer_open_text,
      is_required_question,
      ts_updated
    FROM base_data
    WHERE id_question IN (4003823009, 4003866009, 4003873009)
  ),
  has_disability_enriched AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      answer,
      answer_open_text,
      is_required_question,
      ts_updated,
      CASE
        WHEN answer = 'Yes' THEN true
        WHEN answer = 'No' THEN false
        WHEN answer = 'I dont wish to answer' THEN NULL
        ELSE NULL
      END AS is_person_with_disability
    FROM has_disability
  ),
  
  accessibility_details_enriched AS (
    SELECT
      id_application,
      id_question,
      id_answer,
      question,
      question_language,
      answer_original,
      CASE
        WHEN id_answer IN (4023188009, 4023229009, 4039363009, 4023271009) THEN 'Yes (Please specify)'
        WHEN id_answer IN (4022971009, 4023230009, 4039364009, 4023272009) THEN 'No'
        WHEN id_answer IN (4023189009, 4023231009, 4023273009) THEN 'I dont wish to answer'
        ELSE CONCAT(answer_original, '*')
      END AS answer,
      answer_open_text,
      is_required_question,
      ts_updated
    FROM base_data
    WHERE id_question IN (4003826009, 4003869009, 4003876009)
  ),
  
  disability_type_enriched AS (
    SELECT
      id_application,
      MAX(id_question) AS id_question,
      MAX(question) AS question,
      MAX(question_language) AS question_language,
      COLLECT_LIST(id_answer) AS id_answer,
      COLLECT_LIST(answer_original) AS answer_original,
      COLLECT_LIST(
        CASE
          WHEN id_answer IN (4022955009, 4023214009, 4023256009) THEN 'Deafness and hearing loss'
          WHEN id_answer IN (4022956009, 4023215009, 4023257009) THEN 'Physical Disability'
          WHEN id_answer IN (4022957009, 4023216009) THEN 'Intellectual Disability'
          WHEN id_answer IN (4022958009, 4023217009, 4023259009) THEN 'Visual impairment'
          WHEN id_answer IN (4022959009, 4023218009) THEN 'Mental/Psychosocial Disability'
          WHEN id_answer IN (4022960009, 4023219009) THEN 'Multiple Disabilities'
          WHEN id_answer IN (4022954009, 4023213009, 4023255009) THEN 'I do not consider myself a person with a disability'
          WHEN id_answer IN (4022961009, 4023220009, 4023262009) THEN 'Other'
          WHEN id_answer IN (4022962009, 4023221009, 4023263009) THEN 'I dont wish to answer'
          ELSE CONCAT(answer_original, '*')
        END
      ) AS answer,
      COLLECT_LIST(answer_open_text) AS answer_open_text,
      MAX(is_required_question) AS is_required_question,
      MAX(ts_updated) AS ts_updated
      
    FROM base_data
    WHERE id_question IN (4003824009, 4003867009, 4003874009) -- disability_type
    GROUP BY
      id_application
  ),
  
  all_applications AS (
    SELECT DISTINCT
      id_application
    FROM base_data
  )
  
SELECT
  apps.id_application,
  
  -- id_question
  re.id_question AS id_question_race_ethnicity,
  gi.id_question AS id_question_gender_identity,
  so.id_question AS id_question_sexual_orientation,
  nd.id_question AS id_question_neurodiversity,
  hd.id_question AS id_question_has_disability,
  ad.id_question AS id_question_accessibility_details,
  dt.id_question AS id_question_disability_type,
  
  -- id_answer
  re.id_answer AS id_answer_race_ethnicity,
  gi.id_answer AS id_answer_gender_identity,
  so.id_answer AS id_answer_sexual_orientation,
  nd.id_answer AS id_answer_neurodiversity,
  hd.id_answer AS id_answer_has_disability,
  ad.id_answer AS id_answer_accessibility_details,
  
  -- question
  re.question AS question_race_ethnicity,
  gi.question AS question_gender_identity,
  so.question AS question_sexual_orientation,
  nd.question AS question_neurodiversity,
  hd.question AS question_has_disability,
  ad.question AS question_accessibility_details,
  dt.question AS question_disability_type,
  
  -- question_language
  re.question_language AS question_language_race_ethnicity,
  gi.question_language AS question_language_gender_identity,
  so.question_language AS question_language_sexual_orientation,
  nd.question_language AS question_language_neurodiversity,
  hd.question_language AS question_language_has_disability,
  ad.question_language AS question_language_accessibility_details,
  dt.question_language AS question_language_disability_type,
  
  -- answer_original
  re.answer_original AS answer_original_race_ethnicity,
  gi.answer_original AS answer_original_gender_identity,
  so.answer_original AS answer_original_sexual_orientation,
  nd.answer_original AS answer_original_neurodiversity,
  hd.answer_original AS answer_original_has_disability,
  ad.answer_original AS answer_original_accessibility_details,
  
  -- answer (standardized)
  re.answer AS answer_race_ethnicity,
  gi.answer AS answer_gender_identity,
  so.answer AS answer_sexual_orientation,
  nd.answer AS answer_neurodiversity,
  hd.answer AS answer_has_disability,
  ad.answer AS answer_accessibility_details,
  
  -- answer_open_text
  re.answer_open_text AS answer_open_text_race_ethnicity,
  gi.answer_open_text AS answer_open_text_gender_identity,
  so.answer_open_text AS answer_open_text_sexual_orientation,
  nd.answer_open_text AS answer_open_text_neurodiversity,
  hd.answer_open_text AS answer_open_text_has_disability,
  ad.answer_open_text AS answer_open_text_accessibility_details,

  -- is_minority / flags
  gi.is_woman,
  re.is_race_ethnicity_minority,
  gi.is_gender_identity_minority,
  so.is_sexual_orientation_minority,
  nd.is_neurodiversity_minority,
  hd.is_person_with_disability,
  (
    COALESCE(re.is_race_ethnicity_minority, false)
    OR COALESCE(gi.is_gender_identity_minority, false)
    OR COALESCE(so.is_sexual_orientation_minority, false)
    OR COALESCE(nd.is_neurodiversity_minority, false)
    OR COALESCE(hd.is_person_with_disability, false)
  ) AS is_any_minority,
  
  -- is_required_question
  re.is_required_question AS is_required_question_race_ethnicity,
  gi.is_required_question AS is_required_question_gender_identity,
  so.is_required_question AS is_required_question_sexual_orientation,
  nd.is_required_question AS is_required_question_neurodiversity,
  hd.is_required_question AS is_required_question_has_disability,
  ad.is_required_question AS is_required_question_accessibility_details,
  dt.is_required_question AS is_required_question_disability_type,
  
  -- ts_updated
  re.ts_updated AS ts_updated_race_ethnicity,
  gi.ts_updated AS ts_updated_gender_identity,
  so.ts_updated AS ts_updated_sexual_orientation,
  nd.ts_updated AS ts_updated_neurodiversity,
  hd.ts_updated AS ts_updated_has_disability,
  ad.ts_updated AS ts_updated_accessibility_details,
  dt.ts_updated AS ts_updated_disability_type,
  
  -- disability_type (arrays)
  dt.id_answer AS id_answer_disability_type,
  dt.answer_original AS answer_original_disability_type,
  dt.answer AS answer_disability_type,
  dt.answer_open_text AS answer_open_text_disability_type
  
FROM
  all_applications AS apps
LEFT JOIN race_ethnicity_enriched AS re
  ON apps.id_application = re.id_application
LEFT JOIN gender_identity_enriched AS gi
  ON apps.id_application = gi.id_application
LEFT JOIN sexual_orientation_enriched AS so
  ON apps.id_application = so.id_application
LEFT JOIN neurodiversity_enriched AS nd
  ON apps.id_application = nd.id_application
LEFT JOIN has_disability_enriched AS hd
  ON apps.id_application = hd.id_application
LEFT JOIN accessibility_details_enriched AS ad
  ON apps.id_application = ad.id_application
LEFT JOIN disability_type_enriched AS dt
  ON apps.id_application = dt.id_application