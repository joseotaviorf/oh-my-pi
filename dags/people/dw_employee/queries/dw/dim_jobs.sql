WITH jobs AS (
    SELECT
        id_job,
        id_set,
        id_job_family,
        id_grade_ladder,
        active_status,
        job_code,
        job_name,
        job_customer_flex,
        valid_grades,
        dt_effective_start,
        dt_effective_end
    FROM
        datalake_hr_system_clean.jobs
), job_customer_flex_step1 AS (
    SELECT
        id_job,
        EXPLODE (job_customer_flex) AS job_customer_flex
    FROM
        jobs
), job_customer_flex AS (
    SELECT
        id_job,
        DATE(job_customer_flex['EffectiveStartDate'])   AS dt_effective_start_jcf,
        DATE(job_customer_flex['EffectiveEndDate'])     AS dt_effective_end_jcf,
        job_customer_flex['trilha']                     AS career_track,
        job_customer_flex['marcaPonto']                 AS has_clock_in,
        job_customer_flex['regimeDeJornadaDoEmpregado'] AS working_hours_regime,
        job_customer_flex['cargaHoraria']               AS workload,
        job_customer_flex['target']                     AS target,
        job_customer_flex['targetMensal']               AS monthly_target,
        job_customer_flex['targetSop']                  AS sop_target
    FROM
        job_customer_flex_step1
), band_ladder AS (
    SELECT DISTINCT
        id_band_ladder,
        comp_ladder_directorate
    FROM
        datalake_hr_system.assignments
    QUALIFY dt_effective_start = MAX(dt_effective_start) OVER (PARTITION BY id_band_ladder)
)
SELECT DISTINCT
    -- ids
    j.id_job AS sk_job,
    -- non-metrics
    j.job_code,
    j.job_name,
    COALESCE(bl.comp_ladder_directorate, 'UNKNOWN') AS comp_ladder_directorate,
    CASE
        WHEN j.id_set = 300000004799082 THEN 'Benvi MX'
        WHEN j.id_set = 300000004799081 THEN 'Benvi PT'
        WHEN j.id_set = 300000004799083 THEN 'Classifieds Latam'
        WHEN j.id_set = 0 THEN 'Conjunto Comum'
        WHEN j.id_set = 300000000000174 THEN 'Conjunto do Enterprise'
        WHEN j.id_set = 300000004799080 THEN 'Deel - QuintoAndar'
        WHEN j.id_set = 300000004799078 THEN 'QuintoAndar MG'
        WHEN j.id_set = 300000004799079 THEN 'QuintoAndar SC'
        WHEN j.id_set = 300000004799077 THEN 'QuintoAndar SP'
        ELSE 'UNKNOWN'
    END AS comp_ladder_business_unit,
    CASE
        WHEN j.id_job_family = 300000004860261 THEN 'C-Level'
        WHEN j.id_job_family = 300000004860279 THEN 'Gerentes'
        WHEN j.id_job_family = 300000004860291 THEN 'Especialistas'
        WHEN j.id_job_family = 300000004860273 THEN 'Diretores'
        WHEN j.id_job_family = 300000004860297 THEN 'Supervisores'
        WHEN j.id_job_family = 300000004860267 THEN 'Vice Presidentes'
        WHEN j.id_job_family = 300000004860285 THEN 'Coordenadores'
        WHEN j.id_job_family = 300000004860321 THEN 'Jovem Aprendiz'
        WHEN j.id_job_family = 300000004860303 THEN 'Analistas'
        WHEN j.id_job_family = 300000004860327 THEN 'Estagiario'
        WHEN j.id_job_family = 300000004860309 THEN 'Assistentes'
        WHEN j.id_job_family = 300000004860315 THEN 'Auxiliares'
        ELSE 'UNKNOWN'
    END AS job_ctegory,
    COALESCE(jcf.career_track, 'UNKNOWN') AS career_track,
    COALESCE(jcf.working_hours_regime, 'UNKNOWN') AS working_hours_regime,
    jcf.workload,
    -- metrics
    CASE
        WHEN j.active_status = 'A' THEN TRUE
        WHEN j.active_status = 'I' THEN TRUE
    END AS is_active,
    CASE
        WHEN jcf.has_clock_in = 'Sim' THEN TRUE
        WHEN jcf.has_clock_in = 'Não' THEN FALSE
    END has_clock_in,
    -- dates
    j.dt_effective_start,
    j.dt_effective_end,
    NOW() AS ts_load
FROM
    jobs AS j
LEFT JOIN 
    job_customer_flex AS jcf 
        ON j.id_job = jcf.id_job
LEFT JOIN 
    band_ladder AS bl 
        ON j.id_grade_ladder = bl.id_band_ladder