WITH opportunities_base AS(
    SELECT DISTINCT
        fhlf.sk_house_listing,
        LEFT(fhlf.sk_house_listing,9) AS imovel_id,
        fhlf.days_opportunity_to_listing,
        fhlf.sk_first_listing_date,
        fhlf.sk_opportunity_date,
        dd.date AS opportunity_date,
        fhlf.sk_region,
        fhlf.sk_first_photo_job AS sk_last_photo_job,
        fhlf.sk_lead,
        CASE 
            WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
            WHEN fhlf.mkt_origin = 'B2B' THEN 'B2B'
            WHEN dl.sales_company IN ('ACTION_LINE', 'ALGAR', 'ATENTO') AND fhlf.has_isales_intervention = TRUE THEN 'OUT'
            WHEN fhlf.has_isales_intervention = TRUE THEN 'ISS' 
            ELSE 'UNK' 
        END AS opp_origin
    FROM 
        dw_public.fact_house_listing_flows AS fhlf
    JOIN dw_public.dim_lead dl
        ON dl.sk_lead = fhlf.sk_lead
    JOIN dw_public.dim_date AS dd
        ON dd.sk_date = fhlf.sk_opportunity_date
    WHERE 
        sk_opportunity_date > 0
),
photo_jobs_base AS (
    SELECT 
        imovel_id,
        sk_photo_job,
        dt_job_created,
        COALESCE(dt_problem_reported, user_cancel_dt) AS dt_canceled,
        LEAD(dt_job_created,1) OVER (PARTITION BY imovel_id ORDER BY sk_photo_job) AS dt_next_photo_job,
        MIN(sk_photo_job) OVER (PARTITION BY imovel_id) AS sk_first_photo_job
    FROM 
        dw_public.dim_photo_job 
    GROUP BY 1, 2, 3, 4
),
-- informations about first photo_job for each imovel_id
first_photo_job_base AS (
    SELECT DISTINCT
        pjb.sk_first_photo_job,
        dpj.imovel_id,
        dpj.creation_origin,
        dpj.dt_job_scheduled AS dt_first_job_scheduled
    FROM 
        photo_jobs_base AS pjb
    LEFT JOIN 
        dw_public.dim_photo_job AS dpj
            ON dpj.sk_photo_job = pjb.sk_first_photo_job
),
photo_jobs_metrics AS (
    SELECT 
        imovel_id,
        ROUND(AVG(DATEDIFF(DATE(dt_next_photo_job), DATE(dt_canceled))), 0) AS avg_days_photo_job_created_after_cancel,
        COUNT(dt_next_photo_job) AS photo_jobs_reschedules,
        COUNT(1) AS photo_jobs_number
    FROM 
        photo_jobs_base
    GROUP BY 1
),      
opportunity_photo_info AS (
    SELECT 
        fb.sk_house_listing,
        fb.imovel_id,
        fb.days_opportunity_to_listing,
        fb.sk_first_listing_date,
        fb.sk_opportunity_date,
        fb.opportunity_date,
        fb.sk_region,
        fb.sk_last_photo_job,
        fb.sk_lead,	
        fb.opp_origin,
        lb.sk_first_photo_job,
        lb.creation_origin,
        lb.dt_first_job_scheduled,
        DATEDIFF(DATE(dt_first_job_scheduled), DATE(opportunity_date)) AS days_first_photo_job_scheduled
    FROM 
        opportunities_base AS fb
    LEFT JOIN 
        first_photo_job_base AS lb
            ON lb.imovel_id = fb.imovel_id
)
SELECT 
    o.sk_house_listing,
    o.sk_opportunity_date,
    o.sk_first_listing_date,    
    o.sk_region,    
    o.sk_lead,   
    o.sk_first_photo_job,
    o.sk_last_photo_job,
    o.opp_origin,
    o.creation_origin,
    m.photo_jobs_number,
    m.photo_jobs_reschedules,
    o.days_opportunity_to_listing,
    o.days_first_photo_job_scheduled,
    m.avg_days_photo_job_created_after_cancel
FROM 
    opportunity_photo_info AS o
LEFT JOIN 
    photo_jobs_metrics AS m
        ON m.imovel_id = o.imovel_id