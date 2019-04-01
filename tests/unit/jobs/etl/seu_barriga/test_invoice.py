import time

import mock
import pytest
import requests
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.seu_barriga import SeuBarrigaInvoice


class TestSeuBarrigaReport(object):

    @pytest.mark.parametrize('request_response, expected_result',
                             [('{"status": ""}', False),
                              ('{"status": "status"}', False),
                              ('{"status": "process-running.status/success"}', True)])
    @mock.patch.object(SeuBarrigaInvoice, 'request_job_data')
    def test_is_job_finished(self, mock_request_job_data, seu_barriga_invoice, request_response, expected_result):
        # arrange
        status_url = mock.ANY
        mock_request_job_data.return_value = request_response

        # act
        result = seu_barriga_invoice.is_job_finished(status_url=status_url)

        # assert
        assert result == expected_result

    @mock.patch.object(SeuBarrigaInvoice, 'request_job_data', return_value='{"status": null}')
    def test_is_job_finished_with_response_status_none(self, mock_request_job_data, seu_barriga_invoice):
        # arrange
        status_url = mock.ANY

        # act & assert
        with pytest.raises(Exception):
            seu_barriga_invoice.is_job_finished(status_url=status_url)

    @pytest.mark.parametrize('request_response', [None, ''])
    @mock.patch.object(SeuBarrigaInvoice, 'request_job_data')
    def test_is_job_finished_with_invalid_response(self, mock_request_job_data, seu_barriga_invoice, request_response):
        # arrange
        status_url = mock.ANY
        mock_request_job_data.return_value = request_response

        # act & assert
        with pytest.raises(RuntimeError):
            seu_barriga_invoice.is_job_finished(status_url=status_url)

    @mock.patch.object(requests, 'get')
    def test_request_job_data(self, mock_requests_get, seu_barriga_invoice):
        # arrange
        job_url = 'job_url'
        requests_get_call_args = {
            'url': job_url,
            'headers': {
                'jwt-token': seu_barriga_invoice.api_dict['token']
            }
        }

        # act
        seu_barriga_invoice.request_job_data(job_url=job_url)

        # assert
        assert mock_requests_get.call_args[1] == requests_get_call_args

    @mock.patch.object(requests, 'get')
    def test__request_data(self, mock_requests_get, seu_barriga_invoice):
        # arrange
        endpoint_complement = 'endpoint_complement'
        requests_get_call_args = {
            'url': '{}/{}'.format(seu_barriga_invoice.api_dict['endpoint'], endpoint_complement),
            'headers': {
                'jwt-token': seu_barriga_invoice.api_dict['token']
            }
        }

        # act
        seu_barriga_invoice._request_data(endpoint_complement=endpoint_complement)

        # assert
        assert mock_requests_get.call_args[1] == requests_get_call_args

    @mock.patch.object(time, 'sleep')
    @mock.patch.object(SeuBarrigaInvoice, 'is_job_finished', return_value=True)
    def test_wait_for_results(self, mock_is_job_finished, mock_time_sleep, seu_barriga_invoice):
        # arrange
        status_url = mock.ANY

        # act
        seu_barriga_invoice.wait_for_results(status_url=status_url)

        # assert
        assert mock_time_sleep.call_count == 0

    @mock.patch.object(time, 'sleep')
    @mock.patch.object(SeuBarrigaInvoice, 'is_job_finished')
    def test_wait_for_results_with_sleep(self, mock_time_sleep, mock_is_job_finished, seu_barriga_invoice):
        # arrange
        status_url = mock.ANY
        mock_is_job_finished.side_effect = [False, True]

        # act
        seu_barriga_invoice.wait_for_results(status_url=status_url)

        # assert
        assert mock_time_sleep.call_count == 1

    @mock.patch.object(time, 'sleep')
    @mock.patch.object(SeuBarrigaInvoice, 'is_job_finished', return_value=False)
    def test_wait_for_results_with_wait_time_out(self, mock_is_job_finished, mock_time_sleep, seu_barriga_invoice):
        # arrange
        status_url = mock.ANY

        # act & assert
        with pytest.raises(RuntimeError):
            seu_barriga_invoice.wait_for_results(status_url=status_url)

    @mock.patch.object(BaseETL, 'obj_to_s3')
    @mock.patch.object(AthenaClient, 'upsert_single_partition')
    def test_save_into_s3_raw(self, mock_upsert_single_partition, mock_obj_to_s3, seu_barriga_invoice):
        # arrange
        file_path_prefix = 'file_path_prefix'
        file_path = '{}/ym={}/data.gz'.format(file_path_prefix, seu_barriga_invoice.year_month)

        object_ = mock.ANY
        raw_table_name = mock.ANY
        base_etl_obj_to_s3_call_args = {
            'obj_io': object_,
            'bucket': seu_barriga_invoice.s3_bucket,
            'file_path': file_path
        }
        athena_client_upsert_partition_call_args = {
            'bucket_folder_path': '{}/raw/seu_barriga/invoice/{}'.format(seu_barriga_invoice.s3_bucket,
                                                                         seu_barriga_invoice.type_),
            'database': 'datalake_raw',
            'table': raw_table_name,
            'partition_name': 'ym',
            'partition_value': seu_barriga_invoice.year_month
        }

        # act
        seu_barriga_invoice.save_into_s3_raw(
            object_=object_,
            file_path_prefix=file_path_prefix,
            raw_table_name=raw_table_name
        )

        # assert
        assert mock_obj_to_s3.call_args[1] == base_etl_obj_to_s3_call_args
        assert mock_upsert_single_partition.call_args[1] == athena_client_upsert_partition_call_args

    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(AthenaClient, 'upsert_single_partition')
    def test__transform_data(self, mock_upsert_single_partition, mock_create_parquet_from_query, seu_barriga_invoice):
        # arrange
        query = 'select {year_month}'
        raw_columns = clean_columns = mock.ANY
        clean_table_name = mock.ANY
        key = 'clean/seu_barriga/invoice/{}/ym={}/data.parq'.format(seu_barriga_invoice.type_,
                                                                    seu_barriga_invoice.year_month)
        athena_client_create_parquet_call_args = {
            'key': key,
            'query': query.format(year_month=seu_barriga_invoice.year_month),
            'raw_columns': raw_columns,
            'clean_columns': clean_columns
        }
        athena_client_upsert_partition_call_args = {
            'bucket_folder_path': '{}/clean/seu_barriga/invoice/{}'.format(seu_barriga_invoice.s3_bucket,
                                                                           seu_barriga_invoice.type_),
            'database': 'datalake_clean',
            'table': clean_table_name,
            'partition_name': 'ym',
            'partition_value': seu_barriga_invoice.year_month
        }

        # act
        seu_barriga_invoice._transform_data(
            query=query,
            raw_columns=raw_columns,
            clean_columns=clean_columns,
            clean_table_name=clean_table_name
        )

        # assert
        assert mock_create_parquet_from_query.call_args[1] == athena_client_create_parquet_call_args
        assert mock_upsert_single_partition.call_args[1] == athena_client_upsert_partition_call_args
