## Klefki

### Purpose

Retrieve data from Klefki database (postgresql). [Klefiki](https://github.com/quintoandar/klefiki-api) is related to delivering and receiving keys during the renting period.

Please note that, even though this is an PostgreSQL database, you'll find it named 'klefiki_api' on some locations.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables in our datalake:

1. Incremental load:
   - address_location_key
   - change_owner_control
   - inspector_booking_retrieve_key
   - key_return_preferred_location
   - key_return_preferred_location_aud
   - lock_box_track_entries
   - notifications_sent
2. Full load:
   - address_location_key_aud

### Responsible Data Team
*Data S&S - Inside Ops + Canais e Autoatendimento*

For any questions or concerns about this DAG, please contact the Data Engineering team responsible.
