## Kodak

### Purpose
​
This DAG creates the tables from [Kodak](https://github.com/quintoandar/kodak), a service that stores all media formats at QuintoAndar.
​
### Execution​ Interval

This DAG is triggered once per day. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables, via full load:

1. In datalake raw:
    - `photosphere`
    - `photosphere_aud`
    - `userrevisionentity`
    - `video`
    - `video_aud`

1. In datalake clean:
    - `photo_sphere`
    - `photo_sphere_aud`
    - `user_revision_entity`
    - `video`
    - `video_aud`
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
