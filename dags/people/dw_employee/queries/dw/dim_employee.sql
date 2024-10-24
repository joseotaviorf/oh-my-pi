WITH cte_enrich_demographic_attributes AS (
  SELECT
    id_person,
    marital_status,
    highest_education_level,
    gender
  FROM
    datalake_hr_system.demographic_attributes
  QUALIFY
    ts_last_update = MAX(ts_last_update) OVER (PARTITION BY id_person)
)
SELECT
  emp_info.id_person AS sk_employee,
  emp_info.person_number,
  emp_info.first_name,
  emp_info.last_name,
  emp_info.full_name,
  emp_info.first_social_name,
  emp_info.last_social_name,
  emp_info.birth_town,
  emp_info.birth_state,
  emp_info.birth_country,
  emp_info.mother_name,
  emp_info.father_name,
  COALESCE(da.gender, '-1') AS gender_code,
  CASE
    WHEN da.gender = 'M' THEN 'Masculino'
    WHEN da.gender = 'F' THEN 'Feminino'
    ELSE '-1'
  END AS gender,
  COALESCE(da.marital_status, '-1') AS marital_status_code,
  CASE
    WHEN marital_status = 'C' THEN 'Casado(a)'
    WHEN marital_status = 'D' THEN 'Divorciado(a)'
    WHEN marital_status = 'M' THEN 'União Estável'
    WHEN marital_status = 'O' THEN 'Outros'
    WHEN marital_status = 'Q' THEN 'Desquitado(a) / Separado(a)'
    WHEN marital_status = 'S' THEN 'Solteiro'
    WHEN marital_status = 'V' THEN 'Viúvo(a)'
    WHEN marital_status = 'L' THEN 'Legalmente separado'
    WHEN marital_status = 'N' THEN 'Não informado'
    WHEN marital_status = 'ORA_HRX_SEP' THEN 'Separado(a)'
    ELSE '-1'
  END AS marital_status_description,
  COALESCE(da.highest_education_level, '-1') AS highest_education_level_code,
  CASE
    WHEN da.highest_education_level = '10' THEN 'Analfabeto, inclusive o que, embora tenha recebido instrução, não se alfabetizou'
    WHEN da.highest_education_level = '13' THEN 'Doutorado incompleto'
    WHEN da.highest_education_level = '20' THEN 'Até o 5º ano incompleto do Ensino Fundamental'
    WHEN da.highest_education_level = '25' THEN '5º ano completo do Ensino Fundamental'
    WHEN da.highest_education_level = '30' THEN 'Do 6º ao 9º ano do Ensino Fundamental incompleto'
    WHEN da.highest_education_level = '35' THEN 'Ensino Fundamental completo'
    WHEN da.highest_education_level = '40' THEN 'Ensino Médio incompleto'
    WHEN da.highest_education_level = '45' THEN 'Ensino Médio completo'
    WHEN da.highest_education_level = '50' THEN 'Educação Superior incompleta'
    WHEN da.highest_education_level = '55' THEN 'Educação Superior completa'
    WHEN da.highest_education_level = '65' THEN 'Mestrado completo'
    WHEN da.highest_education_level = '75' THEN 'Doutorado completo'
    WHEN da.highest_education_level = '85' THEN 'Pós-graduação completa'
    WHEN da.highest_education_level = '800' THEN 'Mestrado incompleto'
    WHEN da.highest_education_level = '801' THEN 'Pós-graduação incompleta'
    WHEN da.highest_education_level = '803' THEN 'Tecnólogo incompleto'
    WHEN da.highest_education_level = '805' THEN 'Tecnólogo completo'
    WHEN da.highest_education_level = '807' THEN 'Técnico incompleto'
    WHEN da.highest_education_level = '809' THEN 'Técnico completo'
    WHEN da.highest_education_level = '811' THEN 'Não Informado'
    WHEN da.highest_education_level = 'ORA_HRX_HIGHER_UNI' THEN 'Universitário superior'
    ELSE '-1'
  END AS highest_education_level_description,
  CASE
    WHEN DATEDIFF(current_date(), emp_info.dt_birth) < 21 * 365 THEN 'menos de 21 anos'
    WHEN DATEDIFF(current_date(), emp_info.dt_birth) BETWEEN 21 * 365
    AND 25 * 365 THEN 'de 21 até 25 anos'
    WHEN DATEDIFF(current_date(), emp_info.dt_birth) BETWEEN 26 * 365
    AND 30 * 365 THEN 'de 26 até 30 anos'
    WHEN DATEDIFF(current_date(), emp_info.dt_birth) BETWEEN 31 * 365
    AND 35 * 365 THEN 'de 31 até 35 anos'
    WHEN DATEDIFF(current_date(), emp_info.dt_birth) BETWEEN 36 * 365
    AND 40 * 365 THEN 'de 36 até 40 anos'
    WHEN DATEDIFF(current_date(), emp_info.dt_birth) BETWEEN 41 * 365
    AND 45 * 365 THEN 'de 41 até 45 anos'
    WHEN DATEDIFF(current_date(), emp_info.dt_birth) BETWEEN 46 * 365
    AND 50 * 365 THEN 'de 46 até 50 anos'
    WHEN DATEDIFF(current_date(), emp_info.dt_birth) BETWEEN 51 * 365
    AND 55 * 365 THEN 'de 51 até 55 anos'
    ELSE 'mais de 55 anos'
  END AS age_range,
  DATE(emp_info.dt_birth) AS dt_birthday,
  NOW() AS ts_loaded
FROM
  datalake_hr_system.employee_info AS emp_info
LEFT JOIN
  cte_enrich_demographic_attributes AS da
      ON emp_info.id_person = da.id_person
