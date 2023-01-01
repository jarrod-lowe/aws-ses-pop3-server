#!/usr/bin/python3 -u
"""Authentication Proxy for the POP3 Server"""
from typing import Optional, Dict
import os
import json
import boto3
import crypt
from functools import lru_cache
import traceback


TABLE_NAME = os.environ['TABLE_NAME']


def exception_as_dict(exc):
    data = {
        "type": exc.__class__.__name__,
        "str": str(exc),
        "full": traceback.format_exc(),
    }
    for term in ('args', 'errno', 'message', 'operation_name', 'response'):
        if hasattr(exc, term):
            data[term] = getattr(exc, term)
    if hasattr(exc, 'strerror'):
        if isinstance(exc.strerror, Exception):
            data['strerror'] = exception_as_dict(exc.strerror)
        else:
            data['strerror'] = exc.strerror
    return data


def do_auth(username: str, password: str) -> Optional[Dict[str, str]]:
    """Handle the auth check and getting the config"""
    config = auth_and_config_for_user(username, password)
    if not config:
        return {"StatusCode": 403, "Message": "Forbidden"}

    config.update(get_iam_credentials(username, config['role']))
    return config

def get_iam_credentials(user: str, role: str) -> Dict[str, str]:
    """Get IAM credentials for assuming the role"""
    sts = boto3.client('sts')
    role_session_name = user
    response = sts.assume_role(RoleArn=role, RoleSessionName=role_session_name)
    return {
        'AWSAccessKeyID': response['Credentials']['AccessKeyId'],
        'AWSSecretAccessKey': response['Credentials']['SecretAccessKey'],
        'AWSSessionToken': response['Credentials']['SessionToken'],
    }


@lru_cache(maxsize=16)
def get_bucket_region(bucket: str) -> str:
    """Get the bucket region"""
    s3 = boto3.client('s3')
    response = s3.get_bucket_location(Bucket=bucket)
    # AWS API returns null for us-east-1
    return response['LocationConstraint'] or 'us-east-1'


def auth_and_config_for_user(user: str, password: str) -> Optional[Dict[str, str]]:
    """Determine if the username and password are correct, and return the config data if they are"""
    dynamodb = boto3.client('dynamodb')
    response = dynamodb.get_item(TableName=TABLE_NAME, Key={'username': {'S': user}})
    item = response.get('Item', None)
    if not item:
        print(json.dumps({"type": "fail", "cause": "no such user", "resource": user}))
        return None

    if crypt.crypt(password, item['password']['S']) != item['password']['S']:
        print(json.dumps({"type": "fail", "cause": "incorrect password", "resource": user}))
        return None

    reply = {
        'StatusCode': 200,
        'bucket': item['bucket']['S'],
        'prefix': item['bucket_dir']['S'],
        'region': get_bucket_region(item['bucket']['S']),
        'role': item['role']['S'],
    }
    print(json.dumps({"type": "success", "cause": "login ok", "resource": user, "config": reply}))
    return reply


def handler(event, context) -> Dict:
    try:
        reply = do_auth(event['User'], event['Password'])
    except Exception as exc:
        error_data = exception_as_dict(exc)
        print(json.dumps(error_data))
        error_data['StatusCode'] = 500
        return error_data
    if reply is None:
        return {"StatusCode": 403, "Message": "Login failed"}
    return reply
