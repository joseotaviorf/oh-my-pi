DROP PROCEDURE IF EXISTS ebdb.app_network;

CREATE PROCEDURE ebdb.app_network()
READS SQL DATA
BEGIN

SELECT a.event_id,
    a.user_id,
    -- a.amplitude_id,
    -- a.version_name,
    -- a.user_creation_time,
    -- a.city,
    -- a.region,
    -- a.country,
    -- a.event_time,
    -- a.max_event_time,
    -- a.os_name,
    -- a.location_lat,
    -- a.location_lng,
    a.network-- ,
    -- a.amplitude_event_type,
    -- a.app,
    -- a.event_type
   FROM ( SELECT amp.message ->> 'event_id' AS event_id,
            amp.message ->> 'user_id' AS user_id,
            -- amp.message #>> '{user_properties,"Usuario_id"}' AS Usuario_id,
            -- amp.message ->> 'amplitude_id' AS amplitude_id,
            -- amp.message ->> 'version_name'::text AS version_name,
            -- amp.message ->> 'user_creation_time,'::text AS user_creation_time,
            -- amp.message ->> 'city'::text AS city,
            -- amp.message ->> 'region'::text AS region,
            -- amp.message ->> 'country'::text AS country,
            amp.message ->> 'event_time'::text AS event_time,
            max(amp.message ->> 'event_time'::text) OVER (PARTITION BY (amp.message ->> 'user_id'::text)) AS max_event_time,
            -- amp.message ->> 'os_name'::text AS os_name,
            -- amp.message ->> 'location_lat'::text AS location_lat,
            -- amp.message ->> 'location_lng'::text AS location_lng,
            amp.message #>> '{user_properties,"[adjust] network"}'::text[] AS network,
            -- amp.message ->> 'amplitude_event_type'::text AS amplitude_event_type,
            -- amp.message ->> 'app'::text AS app,
            amp.message ->> 'event_type'::text AS event_type
           FROM amplitude.events amp
          WHERE (amp.message ->> 'event_type'::text) = 'session_start'
          ) a
  WHERE a.event_time = a.max_event_time;
END
