DROP TABLE amplitude.ev_android_booking_media_sources;
CREATE EXTERNAL TABLE amplitude.ev_android_booking_media_sources (
    id bigint,
	app string,
	event_type string,
	uuid string,
	amplitude_id bigint,
	device_id string,
	user_id string,
	event_time timestamp,
	client_event_time timestamp,
	client_upload_time timestamp,
	server_upload_time timestamp,
	event_id string,
	session_id bigint,
	amplitude_event_type string,
	first_event boolean,
	version_name string,
	os_name string,
	os_version string,
	device_brand string,
	device_manufacturer string,
	device_model string,
	device_family string,
	device_type string,
	device_carrier string,
	country string,
	language string,
	revenue double,
	product_id string,
	quantity string,
	price double,
	location_lat double,
	location_lng double,
	ip_address string,
	event_properties struct<
		visita_code:string,
		visita_id:string,
		uri:string,
		imovel_id:string,
		landing_page:string,
		scheduled_hour_from:string,
		scheduled_hour_to:string,
		scheduled_date:string
	>,
	user_properties struct <
        usuario_id:string,
		adjust_network:string,
		utm_campaign:string,
		utm_medium:string,
		utm_source:string >,
	region string,
	city string,
	dma string,
	paying boolean,
	platform string,
	start_version string,
	user_creation_time timestamp,
	library string
)
PARTITIONED by(
			server_upload_date date
)
row FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' WITH SERDEPROPERTIES (
	'ignore.malformed.json' = 'true',
	'mapping.adjust_network' = '[adjust] network',
	'mapping.visita_id' = 'Visita_id',
	'mapping.uri' = 'URI',
	'mapping.imovel_id' = 'Imovel_id',
	'mapping.landing_page' = 'Landing_page'
)
LOCATION 's3://5a-amplitude-events/app=157033/event_type=Confirmation-Visit_confirmed/';
MSCK REPAIR TABLE amplitude.ev_android_booking_media_sources;