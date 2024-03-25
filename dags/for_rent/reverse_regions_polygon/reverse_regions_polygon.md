## Reverse Regions polygon

### Purpose

Creates geo json files for polygons of the regions from ebdb and saves 
them in a s3 bucket. 

To create this geojson file, it uses Apache Sedona libs to get some functions to use in query (ST_PolygonFromText, ST_AsGeoJSON).
And then creates the topojson file to upload it to 5a-looker bucket.
This file has a polygon data of the sk_regions that we use.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following files in s3 bucket:

- `5a_subregion_polygons.topojson`

