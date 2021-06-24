## Hogwarts
### Purpose

Retrieve data from Hogwarts database (postgresql). [Hogwarts](https://github.com/quintoandar/hogwarts) is the knowledge base of QuintoAndar (internal and external FAQs). This service is also responsible for tagging this FAQ which will be used in the Smart Assistant to direct the users to the document that most fits their needs. 

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake:

1. In datalake raw:

    * document
    * document_localization
    * document_x_tag_join
    * locale
    * revision
    * tag
    * tag_localization
    * tagging_category
    * tagging_category_localization
    * tagging_class_localization

2. In datalake clean
    
    * document
    * document_localization
    * document_x_tag_join
    * locale
    * tag
    * tag_localization
    * tagging_category
    * tagging_category_localization
    * tagging_class_localization
    
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>