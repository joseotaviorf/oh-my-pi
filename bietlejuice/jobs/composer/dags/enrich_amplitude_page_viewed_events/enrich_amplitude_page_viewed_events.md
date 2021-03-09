## Enrich Amplitude Page Viewed Events

### Purpose

Amplitude is a product analytics tool that we use at Quinto Andar to help track visitor behaviour. We use the events in conjunction with our major Facts and Dims; focused mostly on enriching them (such as enriching user information onto leads.) More information about how the tool works can be found on [their site](https://amplitude.com/) This Enrich layer is used for a few datamarts due to timeout issues we have using Athena. As a result we take certain events and materialize them so that the processing time is easier and Athena can handle the load.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there are the following output tables in our enrich layer:

- `home_page_viewed`
- `listing_page_viewed`
- `schedule_page_viewed`
- `search_results_page_viewed`
- `contract_docusign_signed_events`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
