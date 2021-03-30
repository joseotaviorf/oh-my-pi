import os
import json
import boto3
import unittest

from moto import mock_s3
from bietlejuice.jobs.composer.services import S3Service


@mock_s3
class TestS3Service(unittest.TestCase):
    bucket = "mocked-bucket"
    folder = "mocked-folder"
    content = json.dumps({"foo": "bar"})

    def setUp(self):
        s3_resource = boto3.resource("s3", region_name="us-east-1")
        s3_resource.create_bucket(Bucket=self.bucket)

        s3 = boto3.client("s3")

        s3.put_object(
            Bucket=self.bucket, Key=f"{self.folder}/foo_bar.json", Body=self.content
        )

        s3.put_object(Bucket=self.bucket, Key=f"{self.folder}/empty.sql", Body="")

    def test_list_objects(self):
        # arrange
        s3_file_path = f"s3://{self.bucket}/{self.folder}"
        s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

        # act
        file_list = s3_service.list_objects(s3_file_path)

        # assert
        assert file_list == [
            "s3://mocked-bucket/mocked-folder/empty.sql",
            "s3://mocked-bucket/mocked-folder/foo_bar.json",
        ]

    def test_read_file(self):
        # arrange
        s3_file_path = f"s3://{self.bucket}/{self.folder}/foo_bar.json"
        s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

        # act
        file_content = s3_service.read_file(s3_file_path)

        # assert
        assert file_content == self.content

    def test_list_sql_files(self):
        # arrange
        s3_file_path = f"s3://{self.bucket}/{self.folder}"
        s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

        # act
        sql_files = s3_service.list_sql_files(s3_file_path)

        # assert
        assert sql_files == ["s3://mocked-bucket/mocked-folder/empty.sql"]

    def test_upload_file(self):
        # arrange
        file_content = "mock text"
        file_path = f"s3://{self.bucket}/test_{self.folder}/file.txt"
        s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

        # act
        s3_service.upload_file(file_content, file_path)

        # assert
        assert s3_service.read_file(file_path) == file_content

    def test_download_file(self):
        # arrange
        file_path = f"s3://{self.bucket}/{self.folder}/foo_bar.json"
        destination_folder = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), "mocked_data/"
        )
        s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

        # act
        s3_service.download_file(file_path, destination_folder)

        # assert
        assert os.path.exists(destination_folder)
        assert os.path.exists(f"{destination_folder}/foo_bar.json")

        # clear files
        os.remove(
            os.path.join(
                os.path.dirname(os.path.realpath(__file__)), "mocked_data/foo_bar.json"
            )
        )

        os.rmdir(
            os.path.join(os.path.dirname(os.path.realpath(__file__)), "mocked_data/")
        )

    def tearDown(self):
        s3 = boto3.resource("s3", region_name="us-east-1")
        bucket = s3.Bucket(self.bucket)
        for key in bucket.objects.all():
            key.delete()
        bucket.delete()
