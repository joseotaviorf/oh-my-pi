## Greenseer
### Purpose

Retrieve data from Greenseer database (postgresql). [Greenseer](https://github.com/quintoandar/greenseer) is our specific-purpose chatbot!

Greenseer interacts with Sauron, orchestrating all automatic text-based customer support in QuintoAndar. When an user tries to contact us via WhatsApp, Greenseer is the receptionist that asks the contact reason and routes the ticket to the best possible human agent.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake, updating only sessions created within 5 days:

1. In datalake raw:

    * session

2. In datalake clean

    * session

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering team responsible listed in the DAG owners.

</details>
