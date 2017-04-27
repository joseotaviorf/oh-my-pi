from jobs.wrappers.amplitude.amplitude_athena_wrapper import AthenaAmplitudeETL

athena = AthenaAmplitudeETL()

database = 'amplitude'
table_name = 'filter_web'

schema = """event_type string,
            app int,
            library string,
            device_type string,
            device_manufacturer string,
            device_carrier string,
            `$schema` int,
            start_version float,
            location_lng float,
            city string,
            user_id bigint,
            uuid string,
            event_time timestamp,
            platform string,
            event_id bigint,
            location_lat float,
            os_version string,
            os_name string,
            amplitude_id bigint,
            processed_time timestamp,
            user_creation_time timestamp,
            device_brand string,
            event_properties struct<Flag_type:string, Flag_value:string>,
            version_name string,
            ip_address string,
            device_id string,
            paying string,
            language string,
            device_model string,
            country string,
            region string,
            server_upload_time timestamp,
            user_properties struct<Location_enabled:boolean, adj_network:string, Total_map_price_flag_clicks:bigint>,
            session_id bigint,
            device_family string,
            client_upload_time timestamp,
            client_event_time timestamp,
            `$insert_id` string"""

partition = """server_upload_date date"""

serde_options = """'ignore.malformed.json' = 'true'"""

location = """s3://5a-amplitude-events/app=156118/event_type=Map-Price_flag_click/"""

athena.create_athena_table(database=database, table_name=table_name, partitions=partition, schema=schema,
                           serde_options=serde_options, location=location)

