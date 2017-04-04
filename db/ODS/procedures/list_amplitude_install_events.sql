DROP PROCEDURE IF EXISTS ebdb.amplitude_install_events;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.amplitude_install_events()
BEGIN

SELECT * FROM 
(select 
     message ->> 'event_id' as event_id,
     message ->> 'user_id' as user_id,
     message ->> 'amplitude_id' as amplitude_id,
     message ->> 'version_name' as version_name,
     message ->> 'user_creation_time,' as user_creation_time,
     message ->> 'city' as city,
     message ->> 'region' as region,
     message ->> 'country' as country,
     message ->> 'event_time' as event_time,
     max(message ->> 'event_time') OVER (PARTITION BY message ->> 'user_id') as max_event_time,
     message ->> 'os_name' as os_name,
     message ->> 'location_lat' as location_lat,
     message ->> 'location_lng' as location_lng,
     message #>> '{user_properties,[adjust] network}' as network,
     message ->> 'amplitude_event_type' as amplitude_event_type,
     message ->> 'app' as app,
     message ->> 'event_type' as event_type

from
     amplitude_event amp
where
     message ->> 'event_type' like '%Install%'
) a

where a.event_time = a.max_event_time

END