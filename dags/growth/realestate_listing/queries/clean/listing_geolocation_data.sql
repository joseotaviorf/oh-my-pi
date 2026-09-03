SELECT
    idaviso AS id_listing,
    idgeolocalizacion AS id_geolocation,
    idgeolocalizacionamostrar AS id_geolocation_to_display,
    zoom AS map_zoom_level
FROM
    datalake_realestate_raw.avisosgeolocationdata
