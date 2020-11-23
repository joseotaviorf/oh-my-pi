WITH max_listing AS (
    SELECT
    	LEFT(sk_house_listing, 9) AS house_id,
    	MAX(sk_house_listing) AS sk_house_listing
    FROM
    	dim_house_listing
    GROUP BY 1 
),
agent_visits AS (
    SELECT DISTINCT 
        db.sk_booking,
    	flrf.sk_user_agent agent_id,
    	flrf.sk_visit_date,
    	db.dt_scheduling,
    	db.ts_scheduling_local,
    	dv.slot,
    	flrf.sk_house_listing,
    	dhl.house_lat,
    	dhl.house_lng,
    	region_code,
    	flrf.flg_visit_completed AS visit_completed,
    	CASE WHEN db.status != 'Cancelado'
    	OR db.ts_cancel_local > date_trunc('d',
    	ts_scheduling_local) - INTERVAL '5 hour' THEN TRUE
    	ELSE FALSE
    END AS visit_scheduled
    FROM
        public.fact_listing_rent_flows flrf
    JOIN public.dim_house_listing dhl ON
        flrf.sk_house_listing = dhl.sk_house_listing
    JOIN max_listing ml ON
        ml.sk_house_listing = flrf.sk_house_listing
    JOIN dim_region dr
    	USING(sk_region)
    JOIN public.dim_visit dv ON
        flrf.sk_visit = dv.sk_visit
    JOIN dim_booking db ON
        flrf.sk_booking = db.sk_booking
    WHERE
        sk_visit_date > 20171231
            AND dt_scheduling < CURRENT_TIMESTAMP
            AND (db.status != 'Cancelado'
            OR db.ts_cancel_local > date_trunc('d',
            db.ts_scheduling_local) - INTERVAL '5 hour') 
),
-- order visits in chronological and lat-lng order from the previous one
 scheduled_ordered_lat_lng_visits AS( -- visits scheduling planner
    SELECT
    	agent_id,
    	region_code,
    	sk_booking,
    	sk_visit_date,
    	dt_scheduling,
    	house_lat,
    	house_lng,
    	lag(house_lat) OVER (PARTITION BY sk_visit_date,
    	agent_id
    ORDER BY
    	slot) last_house_lat,
    	lag(house_lng) OVER (PARTITION BY sk_visit_date,
    	agent_id
    ORDER BY
    	slot) last_house_lng
    FROM
    	agent_visits
    WHERE
    	visit_scheduled = TRUE 
),
completed_ordered_lat_lng_visits AS( -- visits completed
    SELECT
    	agent_id,
    	region_code,
    	sk_booking,
    	sk_visit_date,
    	dt_scheduling,
    	house_lat,
    	house_lng,
    	lag(house_lat) OVER (PARTITION BY sk_visit_date, agent_id ORDER BY slot) last_house_lat,
    	lag(house_lng) OVER (PARTITION BY sk_visit_date, agent_id ORDER BY slot) last_house_lng
    FROM
    	agent_visits
    WHERE
    	visit_completed = TRUE 
),
--calculate the distance for each agent
 scheduled_agent_distances AS ( -- scheduled visits
    SELECT
    	sk_booking,
    	house_lat,
    	house_lng,
    	last_house_lat,
    	last_house_lng,
    	dd.date AS DATE,
    	CASE WHEN last_house_lat IS NULL THEN 0
    	ELSE f_geodesical_distance(last_house_lat,
    	last_house_lng,
    	house_lat,
    	house_lng)
    END distance,
    du.dadosagente_perfil
    FROM
        scheduled_ordered_lat_lng_visits sollv
    JOIN public.dim_date dd ON
        sollv.sk_visit_date = dd.sk_date
    LEFT JOIN dim_user du ON
        du.id = sollv.agent_id 
),
completed_agent_distances AS (-- completed visits
    SELECT
    	agent_id,
    	sk_booking,
    	house_lat,
    	house_lng,
    	last_house_lat,
    	last_house_lng,
    	CASE WHEN last_house_lat IS NULL THEN 0
    	ELSE f_geodesical_distance(last_house_lat,
    	last_house_lng,
    	house_lat,
    	house_lng)
    END distance,
    du.dadosagente_perfil
    FROM
        completed_ordered_lat_lng_visits sollv
    JOIN public.dim_date dd ON
        sollv.sk_visit_date = dd.sk_date
    LEFT JOIN dim_user du ON
        du.id = sollv.agent_id 
),
-- calculates slots occupied by visits
 scheduled_agent_slots AS( -- visitas agendadas
    SELECT
    	sk_booking,
    	distance,
    	dadosagente_perfil,
        CASE WHEN dadosagente_perfil = 'CAR_TEMP_COVID' THEN
            CASE WHEN distance <= 200 THEN 0
        	WHEN distance BETWEEN 200 AND 1200 THEN 1
        	WHEN distance BETWEEN 1200 AND 3000 THEN 2
        	WHEN distance BETWEEN 3000 AND 4500 THEN 3
        	WHEN distance >= 4500 THEN 4
            END
        WHEN dadosagente_perfil = 'CARRO' THEN
            CASE WHEN distance <= 50 THEN 0
            WHEN distance BETWEEN 50 AND 1000 THEN 1
            WHEN distance BETWEEN 1000 AND 2000 THEN 2
            WHEN distance BETWEEN 2000 AND 3000 THEN 3
            WHEN distance >= 3000 THEN 4
            END
        WHEN dadosagente_perfil = 'ONIBUS' THEN
            CASE WHEN distance <= 50 THEN 0
            WHEN distance BETWEEN 50 AND 750 THEN 1
            WHEN distance BETWEEN 750 AND 1300 THEN 2
            WHEN distance BETWEEN 1300 AND 2000 THEN 3
            WHEN distance BETWEEN 2000 AND 3000 THEN 4
            WHEN distance >= 3000 THEN 5
            END
        WHEN dadosagente_perfil = 'CAR_USING_HIGHWAYS' THEN
            CASE WHEN distance <= 500 THEN 0
            WHEN distance BETWEEN 500 AND 1500 THEN 1
            WHEN distance BETWEEN 1500 AND 5000 THEN 2
            WHEN distance BETWEEN 5000 AND 12000 THEN 3
            WHEN distance BETWEEN 12000 AND 24000 THEN 4
            WHEN distance BETWEEN 24000 AND 48000 THEN 5
            WHEN distance >= 48000 THEN 6
            END
        WHEN dadosagente_perfil = 'CAR_LONG_DISTANCE' THEN
            CASE WHEN distance <= 50 THEN 0
            WHEN distance BETWEEN 50 AND 1250 THEN 1
            WHEN distance BETWEEN 1250 AND 2500 THEN 2
            WHEN distance BETWEEN 2500 AND 4000 THEN 3
            WHEN distance BETWEEN 4000 AND 6000 THEN 4
            WHEN distance BETWEEN 6000 AND 8000 THEN 5
            WHEN distance BETWEEN 8000 AND 10000 THEN 6
            WHEN distance >= 10000 THEN 7
            END
        WHEN dadosagente_perfil = 'BUS_LONG_DISTANCE' THEN
            CASE WHEN distance <= 50 THEN 0
            WHEN distance BETWEEN 50 AND 750 THEN 1
            WHEN distance BETWEEN 750 AND 1500 THEN 2
            WHEN distance BETWEEN 1500 AND 2250 THEN 3
            WHEN distance BETWEEN 2250 AND 3250 THEN 4
            WHEN distance BETWEEN 3250 AND 4500 THEN 5
            WHEN distance BETWEEN 4500 AND 5750 THEN 6
            WHEN distance BETWEEN 5750 AND 7000 THEN 7
            WHEN distance BETWEEN 7000 AND 20000 THEN 8
            WHEN distance BETWEEN 20000 AND 22500 THEN 9
            WHEN distance BETWEEN 22500 AND 25000 THEN 10
            WHEN distance >= 25000 THEN 11
            END
        END AS displacement_slots
    FROM 
        scheduled_agent_distances 
),
completed_agent_slots AS ( -- visitas completas
    SELECT
    	sk_booking,
    	distance,
    	CASE WHEN dadosagente_perfil = 'CAR_TEMP_COVID' THEN
        	CASE WHEN distance <= 200 THEN 0
        	WHEN distance BETWEEN 200 AND 1200 THEN 1
        	WHEN distance BETWEEN 1200 AND 3000 THEN 2
        	WHEN distance BETWEEN 3000 AND 4500 THEN 3
        	WHEN distance >= 4500 THEN 4
        END
        WHEN dadosagente_perfil = 'CARRO' THEN
        CASE WHEN distance <= 50 THEN 0
            -- min slot 
            WHEN distance BETWEEN 50 AND 1000 THEN 1
            WHEN distance BETWEEN 1000 AND 2000 THEN 2
            WHEN distance BETWEEN 2000 AND 3000 THEN 3
            WHEN distance >= 3000 THEN 4
            -- max slot 
            END
        WHEN dadosagente_perfil = 'ONIBUS' THEN
            CASE WHEN distance <= 50 THEN 0
            WHEN distance BETWEEN 50 AND 750 THEN 1
            WHEN distance BETWEEN 750 AND 1300 THEN 2
            WHEN distance BETWEEN 1300 AND 2000 THEN 3
            WHEN distance BETWEEN 2000 AND 3000 THEN 4
            WHEN distance >= 3000 THEN 5
            END
        WHEN dadosagente_perfil = 'CAR_USING_HIGHWAYS' THEN
            CASE WHEN distance <= 500 THEN 0
            WHEN distance BETWEEN 500 AND 1500 THEN 1
            WHEN distance BETWEEN 1500 AND 5000 THEN 2
            WHEN distance BETWEEN 5000 AND 12000 THEN 3
            WHEN distance BETWEEN 12000 AND 24000 THEN 4
            WHEN distance BETWEEN 24000 AND 48000 THEN 5
            WHEN distance >= 48000 THEN 6
            END
        WHEN dadosagente_perfil = 'CAR_LONG_DISTANCE' THEN
            CASE WHEN distance <= 50 THEN 0
            WHEN distance BETWEEN 50 AND 1250 THEN 1
            WHEN distance BETWEEN 1250 AND 2500 THEN 2
            WHEN distance BETWEEN 2500 AND 4000 THEN 3
            WHEN distance BETWEEN 4000 AND 6000 THEN 4
            WHEN distance BETWEEN 6000 AND 8000 THEN 5
            WHEN distance BETWEEN 8000 AND 10000 THEN 6
            WHEN distance >= 10000 THEN 7
            END
        WHEN dadosagente_perfil = 'BUS_LONG_DISTANCE' THEN
            CASE WHEN distance <= 50 THEN 0
            WHEN distance BETWEEN 50 AND 750 THEN 1
            WHEN distance BETWEEN 750 AND 1500 THEN 2
            WHEN distance BETWEEN 1500 AND 2250 THEN 3
            WHEN distance BETWEEN 2250 AND 3250 THEN 4
            WHEN distance BETWEEN 3250 AND 4500 THEN 5
            WHEN distance BETWEEN 4500 AND 5750 THEN 6
            WHEN distance BETWEEN 5750 AND 7000 THEN 7
            WHEN distance BETWEEN 7000 AND 20000 THEN 8
            WHEN distance BETWEEN 20000 AND 22500 THEN 9
            WHEN distance BETWEEN 22500 AND 25000 THEN 10
            WHEN distance >= 25000 THEN 11
            END
        END AS displacement_slots
    FROM
    completed_agent_distances 
),
base AS (
SELECT
	agv.sk_booking,
	agv.sk_visit_date,
	agv.ts_scheduling_local AS visit_time,
	agv.agent_id AS sk_user_agent,
	agv.house_lat AS visit_lat,
	agv.house_lng AS visit_lng,
	sas.dadosagente_perfil,
	agv.region_code,
	agv.visit_scheduled,
	agv.visit_completed,
	sas.distance AS scheduled_displacement,
	sas.displacement_slots AS scheduled_displacement_slots,
	cas.distance AS completed_displacement,
	cas.displacement_slots AS completed_displacement_slots
FROM
	agent_visits agv
LEFT JOIN scheduled_agent_slots sas ON
	sas.sk_booking = agv.sk_booking
LEFT JOIN completed_agent_slots cas ON
	cas.sk_booking = agv.sk_booking
WHERE 
    sk_user_agent > 0 -- visits that have been assigned to agents
ORDER BY
    agv.sk_visit_date, agv.agent_id, agv.dt_scheduling
)
SELECT * FROM base