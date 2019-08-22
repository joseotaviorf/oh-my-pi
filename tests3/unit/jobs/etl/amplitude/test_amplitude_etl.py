import pytest
import gzip
import zipfile
import os
import shutil

class TestAmplitudeEvents:
    @pytest.mark.parametrize('len_data', [0, 1, 1000, 100000])
    def test_get_number_of_partitions_raw(self, len_data, amplitude_events):
        # arrange
        expected = max(len_data // amplitude_events.RAW_RECORDS_BY_PARTITION, 1)

        #act
        result = amplitude_events.get_number_of_partitions(len_data, 'raw')

        #assert
        assert result == expected

    @pytest.mark.parametrize('len_data', [0, 1, 1000, 100000])
    def test_get_number_of_partitions_clean(self, len_data, amplitude_events):
        # arrange
        expected = max(len_data // amplitude_events.CLEAN_RECORDS_BY_PARTITION, 1)

        # act
        result = amplitude_events.get_number_of_partitions(len_data, 'clean')

        # assert
        assert result == expected

    def test_get_data_from_zip_file(self, amplitude_events):
        # arrange
        json_files = ['{"a": 1, "b": 3}\n{"a": 2, "b": 2}\n', '{"a": 5, "b": 5}']

        os.makedirs('/tmp/test_get_data_from_zip_file/gzips/', exist_ok=True)
        for i, file in enumerate(json_files):
            with gzip.GzipFile('/tmp/test_get_data_from_zip_file/gzips/{}.json.gz'.format(i), 'w') as f:
                f.write(file.encode())

        zipf = zipfile.ZipFile('/tmp/test_get_data_from_zip_file/gzips.zip', 'w', zipfile.ZIP_DEFLATED)
        for root, dirs, files in os.walk('/tmp/test_get_data_from_zip_file/gzips/'):
            for file in files:
                zipf.write(os.path.join(root, file))
        zipf.close()

        expected = ['{"a": 1, "b": 3}', '{"a": 2, "b": 2}', '{"a": 5, "b": 5}']

        # act
        with zipfile.ZipFile('/tmp/test_get_data_from_zip_file/gzips.zip', "r") as zip_file:
            result = amplitude_events.get_data_from_zip_file(zip_file)

        print('>>>>>>>>>', result)

        # assert
        assert expected.sort() == result.sort()

        # clean
        shutil.rmtree('/tmp/test_get_data_from_zip_file/', ignore_errors=True)

    def test_load_events_into_datalake_raw(self, mocked_data_frame_service):
        # arrange
        json_files = ['{"a": 1, "b": 3}\n{"a": 2, "b": 2}\n', '{"a": 5, "b": 5}']

        os.makedirs('/tmp/test_get_data_from_zip_file/gzips/', exist_ok=True)
        for i, file in enumerate(json_files):
            with gzip.GzipFile('/tmp/test_get_data_from_zip_file/gzips/{}.json.gz'.format(i), 'w') as f:
                f.write(file.encode())

        zipf = zipfile.ZipFile('/tmp/test_get_data_from_zip_file/gzips.zip', 'w', zipfile.ZIP_DEFLATED)
        for root, dirs, files in os.walk('/tmp/test_get_data_from_zip_file/gzips/'):
            for file in files:
                zipf.write(os.path.join(root, file))
        zipf.close()

        expected = ['{"a": 1, "b": 3}', '{"a": 2, "b": 2}', '{"a": 5, "b": 5}']
