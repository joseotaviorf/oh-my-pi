from argparse import ArgumentParser

import boto3
from os.path import basename
import json
import random

import urllib
import requests

import time
from datetime import datetime

import logging
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils

from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services import S3Service

def _format_requests(endpoint:str, configs: dict, display_limit: int) -> list:
    """
    Function to format URL requests based on display limit. The expected output
    is a bunch of URLs like:
    - https://endpoint.com/?config1=value1&offset=0&limit=99999
    - https://endpoint.com/?config1=value1&offset=10000&limit=199999
    - ...
    """
    params = '&'.join([f"{conf}={configs[conf]}" for conf in configs])
    startRow = 0
    maxRows = 100000
    endRow = display_limit

    url_requests = []
    for i in range(startRow, endRow, maxRows):
        offset = i
        limit = min(i + maxRows - 1, endRow)
        displayOffsetParam = f'&display_offset={offset}'
        displayLimitParam = f'&display_limit={limit}'

        url_requests.extend([endpoint + params + displayOffsetParam + displayLimitParam])  

    return url_requests

def _verify_request(api_key: str, url_test_request: str) -> Exception:
    """
    "Function to make a test request.
    """

    url_parsed = urllib.parse.urlparse(url_test_request)
    url_params = urllib.parse.parse_qs(url_parsed.query)

    url_params["display_offset"] = ["0"]
    url_params["display_limit"] = ["1"]

    url_test_formatted = urllib.parse.urlunparse(
        url_parsed._replace(query=urllib.parse.urlencode(url_params, doseq=True))
    )

    url_test_request_auth = url_test_formatted + f"&key={api_key}"

    try:
        api_units_before = int(requests.get(f'http://www.semrush.com/users/countapiunits.html?key={api_key}').text)
        response = requests.get(url_test_request_auth)
        api_units_after = int(requests.get(f'http://www.semrush.com/users/countapiunits.html?key={api_key}').text)

        return {
            "url": url_test_formatted,
            "api_units_consumed": api_units_before - api_units_after,
            "status_code": response.status_code,
        }
    except:
        raise Exception(f"""
                        Verification request wasn't successfull.
                        
                        url: {url_test_formatted}
                        failed_timestamp: {datetime.now()}
                        """)        

def _verify_request_cost(api_key: str, url_test_request: str) -> Exception:
    """
    "Function to make a test request and verify the amount of API units being 
    consumed. 
    """

    response = _verify_request(api_key, url_test_request)

    if response['api_units_consumed'] > 10:
        raise Exception(f"""
                        Cost of API Units per row exceeds the budget.
                        Number of untis per request: {response['api_units_consumed']}.
                        
                        url: {response['url']}
                        failed_timestamp: {datetime.now().isoformat()}
                        """)

    if response['status_code'] != 200:
        raise Exception(f"""
                        The verification request wasn't successfull:
                        status_code {response['status_code']}

                        url: {response['url']}
                        failed_timestamp: {datetime.now().isoformat()}                        
                        """)
    return True

def _make_request(api_key: str, url_request: str) -> str:
    """
    Function to make smothie requests to SEMrush API.
    """
    api_units_before = int(requests.get(f'http://www.semrush.com/users/countapiunits.html?key={api_key}').text)
    
    try:
        url_request_auth = url_request + f"&key={api_key}"
        response = requests.get(url_request_auth)
        api_units_after = int(requests.get(f'http://www.semrush.com/users/countapiunits.html?key={api_key}').text)

        if response.status_code == 200:
            response_data = {
                "ok": response.ok,
                "reason": response.reason,
                "status_code": response.status_code,
                "text": response.text,
                "url": response.url,
                "api_units_consumed": api_units_before - api_units_after,
                "timestamp_utc_request": datetime.now().isoformat(),
            }

            return response_data
        
        else:
            raise Exception(f"""
            Not successfull request. 
            url: {url_request}
            status_code: {response.status_code}
            reason: {response.reason}
            failed_timestamp: {datetime.now().isoformat()} 
            """)

    except Exception as exception:
        logging.error(f"Fail to make API request. error:{exception}")
        raise exception
 

## Logger
JOB_NAME = "load_semrush_transient"
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    parser.add_argument("overwrite_enabled")
    parser.add_argument("overcosts_enabled")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = datetime.strptime(args.execution_date, "%Y-%m-%d")

    display_date = execution_date.replace(day=15)
    display_date = display_date.strftime('%Y%m%d')

    overwrite_enabled = args.overwrite_enabled
    overcosts_enabled = args.overcosts_enabled

    config_service = ConfigurationService(source)
    report_list = config_service.get_config("report_list")

    s3_service = S3Service(boto3.resource("s3"))

    """
    Fetch auth credentials.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    api_key = dbutils.secrets.get('quintoandar', APIEnum.SEMRUSH)

    """
    [1] PREPARE REQUISITIONS TO BE MADE
    """    
    endpoint = 'https://api.semrush.com/?'
    requests_file_path = f"s3://{datalake_bucket}/{LayerEnum.RAW.value}/{source}/{display_date}/requests/requests.json"
    responses_folder_path = f"s3://{datalake_bucket}/{LayerEnum.RAW.value}/{source}/{display_date}/responses"

    if overwrite_enabled == 'True':
        s3_service.delete_object(requests_file_path)

    try:
        """
        Fetch 'requests.json' file.
        """
        url_requests = json.loads(s3_service.read_file(requests_file_path))
        if url_requests:

            url_responses = [
                urllib.parse.unquote(basename(url)).replace('.json','') for url in s3_service.list_objects(responses_folder_path)
            ]
            url_requests = [req for req in url_requests if req not in url_responses]
        
        else:
            raise Exception(f"The file 'requests.json' is not created yet.")

    except:
        """
        Create 'requests.json' file.
        """
        requests_nested_list = [
            _format_requests(endpoint, report_list[report]['configs'], report_list[report]['display_limit']) for report in report_list
        ]

        url_requests = [req for reqs in requests_nested_list for req in reqs]
        s3_service.upload_file(json.dumps(url_requests), requests_file_path)
        
    if url_requests:
        """
        [2] VERIFYING COSTS AND CONNECTIONS
        """
        if overcosts_enabled == 'True':
            _verify_request(api_key, random.choice(url_requests))

        else: 
            _verify_request_cost(api_key, random.choice(url_requests))
            
        logger.info("Verification request was successfull. Starting requests...")

        """
        [3] MAKING PENDING REQUESTS
        """ 
        for url_request in url_requests:
            logger.info(f"{url_request}\n")

            logger.info("Sleeping for 5 seconds before the next request.")          
            time.sleep(5)
            
            response_data = _make_request(api_key, url_request)
            file_name = urllib.parse.quote(url_request, safe='')
            s3_service.upload_file(json.dumps(response_data), f"{responses_folder_path}/{file_name}.json")
            
    else:
        logger.info(f"Data already ingested for display_date: {display_date}.")