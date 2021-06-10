## Sirena
### Purpose

Retrieves data from [Agents](https://api.sirena.app/#operation/getAgents.), [Channels](https://api.sirena.app/#operation/getChannels), [Groups](https://api.sirena.app/#operation/getGroups), [Interactions](https://api.sirena.app/#operation/getInteractions) and [Prospects](https://api.sirena.app/#operation/getProspects) from Sirena API.
Sirena is a CRM tool that is being used for the forSale business and acts as a communication facilitator between our consultants and customers (buyers & sellers) through WhatsApp. Therefore, our negotiation and relationship between entities during the sale flow are recorded in Sirena's interactions through WhatsApp messages (text / audio).

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG runs Spark jobs that execute multiple requests using different execution strategies for each endpoint. For `channels` and `groups` they use a single request retrieveing the full load. For `agents`, they use thread executors to make multiple concurrent requests, while for `interactions` and `prospects` they use Spark parallel processing for mutiple parallel requests.

This pipeline produces, via full load:

- In datalake raw and clean:
    - `agents`
    - `channels`
    - `groups`

and via incremental load:

- In datalake raw and clean:
    - `interactions`
    - `prospects`


### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
