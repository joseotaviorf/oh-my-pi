import os
import json
import boto3

from moto import mock_s3
from bietlejuice.jobs.composer.services import S3Service


BUCKET = "mocked-bucket"
FOLDER = "mocked-folder"
CONTENT = json.dumps({"foo": "bar"})


def set_up():
    s3_resource = boto3.resource("s3", region_name="us-east-1")
    s3_resource.create_bucket(Bucket=BUCKET)

    s3 = boto3.client("s3")

    s3.put_object(Bucket=BUCKET, Key=f"{FOLDER}/foo_bar.json", Body=CONTENT)

    s3.put_object(Bucket=BUCKET, Key=f"{FOLDER}/empty.sql", Body="")


def tear_down():
    s3 = boto3.resource("s3", region_name="us-east-1")
    bucket = s3.Bucket(BUCKET)
    for key in bucket.objects.all():
        key.delete()
    bucket.delete()


@mock_s3
def test_list_objects():
    # arrange

    set_up()
    s3_file_path = f"s3://{BUCKET}/{FOLDER}"
    s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

    # act
    file_list = s3_service.list_objects(s3_file_path)

    # assert
    assert file_list == [
        "s3://mocked-bucket/mocked-folder/empty.sql",
        "s3://mocked-bucket/mocked-folder/foo_bar.json",
    ]

    tear_down()


@mock_s3
def test_read_file():
    # arrange

    set_up()
    s3_file_path = f"s3://{BUCKET}/{FOLDER}/foo_bar.json"
    s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

    # act
    file_content = s3_service.read_file(s3_file_path)

    # assert
    assert file_content == CONTENT

    tear_down()


@mock_s3
def test_list_sql_files():
    # arrange

    set_up()
    s3_file_path = f"s3://{BUCKET}/{FOLDER}"
    s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

    # act
    sql_files = s3_service.list_sql_files(s3_file_path)

    # assert
    assert sql_files == ["s3://mocked-bucket/mocked-folder/empty.sql"]

    tear_down()


@mock_s3
def test_create_empty_object():
    # arrange

    set_up()
    file_path = f"s3://{BUCKET}/{FOLDER}/test_file.sql"
    folder_path = f"s3://{BUCKET}/{FOLDER}"
    s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

    # act
    s3_service.create_empty_object(file_path)
    sql_files = s3_service.list_sql_files(folder_path)

    # assert
    assert file_path in sql_files

    tear_down()


@mock_s3
def test_delete_object():
    # arrange

    set_up()
    file_path = f"s3://{BUCKET}/{FOLDER}/test_file.sql"
    folder_path = f"s3://{BUCKET}/{FOLDER}"
    s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

    # act
    s3_service.delete_object(file_path)
    sql_files = s3_service.list_sql_files(folder_path)

    # assert
    assert file_path not in sql_files

    tear_down()


@mock_s3
def test_upload_file():
    # arrange

    set_up()
    file_content = "mock text"
    file_path = f"s3://{BUCKET}/test_{FOLDER}/file.txt"
    s3_service = S3Service(boto3.resource("s3", region_name="us-east-1"))

    # act
    s3_service.upload_file(file_content, file_path)

    # assert
    assert s3_service.read_file(file_path) == file_content

    tear_down()


@mock_s3
def test_download_file():
    # arrange

    set_up()
    file_path = f"s3://{BUCKET}/{FOLDER}/foo_bar.json"
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

    os.rmdir(os.path.join(os.path.dirname(os.path.realpath(__file__)), "mocked_data/"))
    tear_down()
