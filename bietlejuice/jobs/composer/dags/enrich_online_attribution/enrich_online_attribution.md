## Enrich Online Attribution

### Purpose

As a derivation of Amplitude enrich layer, this DAG generates an aggregated online attribution from conversion events. The query selects amplitude conversion events day to day and lookups all past events. The stakeholders will use this to improve attribution and reduce lost tracking metrics.

[Here](https://www.notion.so/productquintoandar/Growth-DE-Prioritization-c5796ec19067490ebe5b0e5c7132a600?p=39a5e8ff13504a3490c9ce640dd3ffcd) you can find more context about the Data Analyst objectives with the data. This is a part of a project to reduce lost tracking metrics. 

The query isn't 100% accurate, because we are fetching events that occur at most four months ago. For precise attribution, we need to collect all past events from a user.

The enrich `online attribute` table is partitioned by year, month, and day from the date of conversion, not the date of the event. So, if you query the table using where clause `WHERE year = 2022 AND month = 1 AND day = 1` you will retrive data from all events and attributions from users who converted in `2022/01/01`.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table in our enrich layer:

- `datalake_online_attribution.online_attribution`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>