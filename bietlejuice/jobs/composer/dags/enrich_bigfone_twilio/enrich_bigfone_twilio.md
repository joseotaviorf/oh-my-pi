## Enrich Bigfone Twilio
### Purpose

This is the second layer of the enrichment phase of the [Bigfone](github.com/quintoandar/big-fone) data preparation. [Bigfone](https://github.com/quintoandar/big-fone) is a system responsible for interacting with Twilio (an external service) to manage calls, peers and store data used to generate some reports. Also, it acts as a central place to identify a person, adding info from Skynet, Akinator, Timeline (from Stalker) and Akinator.

### Execution Interval

This DAG is triggered once per day via Mediator, after `enrich_bigfone_events` DAG, usually around 6:00 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:

- `inbound_call_locations`
- `call_ivr_paths`
- `call_ivr_events`
- `call_flex_reservations`
- `call_flex_events`
- `call_agents`

### Disclaimer

The logic of call_flex_reservations is highly dependent of the order of the events (now we are sorting using The unix timestamp and untie by the alphabetical of the event).Changing these event names may impact on the results of this table and consequently the whole call model

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
