#!/usr/bin/python3 -u
"""Authentication Proxy for the POP3 Server"""
from typing import Optional, Dict
from http.server import HTTPServer, BaseHTTPRequestHandler
from base64 import b64decode
import os
import json
import boto3
import crypt
from functools import lru_cache


PORT = 8000
TABLE_NAME = os.environ['TABLE_NAME']


def exception_as_dict(exc):
    data = {
        "type": exc.__class__.__name__,
        "str": str(exc),
        "keys": dir(exc),
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


class RequestHandler(BaseHTTPRequestHandler):
    """HTTP Server Request Handler"""
    def log_message(self, format, *args):
        return json.dumps({
            "type": "access_log",
            "addr": self.address_string(),
            "datetime": self.log_date_time_string(),
            "message": format%args,
        })

    def do_GET(self) -> None:
        """Handle the GET"""
        try:
            reply = self.do_auth()
        except Exception as exc:
            print(json.dumps(exception_as_dict(exc)))
            self.send_response(500)
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(exc)}).encode('utf-8'))
            return

        if reply is None:
            self.send_response(401)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Unauthorized")
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(reply).encode('utf-8'))
        
    def do_auth(self) -> Optional[Dict[str, str]]:
        """Handle the auth check and getting the config"""
        if "Authorization" not in self.headers:
            return None

        auth = self.headers["Authorization"].split()[1]
        decoded_auth = b64decode(auth).decode("utf-8")
        username, password = decoded_auth.split(":")

        config = self.auth_and_config_for_user(username, password)
        if not config:
            return None

        config.update(self.get_iam_credentials(username, config['role']))
        return config

    @staticmethod
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

    @staticmethod
    @lru_cache(maxsize=16)
    def get_bucket_region(bucket: str) -> str:
        """Get the bucket region"""
        s3 = boto3.client('s3')
        response = s3.get_bucket_location(Bucket=bucket)
        # AWS API returns null for us-east-1
        return response['LocationConstraint'] or 'us-east-1'

    @classmethod
    def auth_and_config_for_user(cls, user: str, password: str) -> Optional[Dict[str, str]]:
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
            'bucket': item['bucket']['S'],
            'prefix': item['bucket_dir']['S'],
            'region': cls.get_bucket_region(item['bucket']['S']),
            'role': item['role']['S'],
        }
        print(json.dumps({"type": "success", "cause": "login ok", "resource": user, "config": reply}))
        return reply

    def respond_unauth(self) -> None:
        """Respond with 401 unauthorised"""


# Create and start the server
if __name__ == "__main__":
    server = HTTPServer(("localhost", PORT), RequestHandler)
    print(json.dumps({"type": "success", "cause": "started server", "port": PORT}))
    server.serve_forever()
