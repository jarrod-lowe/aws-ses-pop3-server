# Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
from typing import Dict, Union
import rsa
import boto3
import logging
import os
import json
import traceback
import acme


logger = logging.getLogger()
logger.setLevel(logging.INFO)


# Key generation can take minutes! This might speed it up?
#import secrets
#def read_random_bits(nbits: int) -> bytes:
#    """Use secrets instead of urandom"""
#    nbytes, rbits = divmod(nbits, 8)
#    if rbits:
#        nbytes += 1
#    return secrets.token_bytes(nbytes)
#rsa.randnum.read_random_bits = read_random_bits


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


def log(data: Dict, message: Union[Dict, str], error: bool = True) -> None:
    """Log"""
    if error:
        fn = logger.error
        message_key = "error"
    else:
        fn = logger.info
        message_key = "message"
    if isinstance(message, dict):
        merge = message
    else:
        merge = {message_key: message}
    merge.update(data)
    fn(json.dumps(merge))


def lambda_handler(event, context) -> None:
    """Wrap handler in a try"""
    try:
        _lambda_handler(event, context)
    except Exception as exc:
        error_data = exception_as_dict(exc)
        error_data.update(event)
        log(error_data, str(exc))
        raise


def _lambda_handler(event, context) -> None:
    """Secrets Manager Rotation Template

    This is a template for creating an AWS Secrets Manager rotation lambda

    Args:
        event (dict): Lambda dictionary of event parameters. These keys must include the following:
            - SecretId: The secret ARN or identifier
            - ClientRequestToken: The ClientRequestToken of the secret version
            - Step: The rotation step (one of createSecret, setSecret, testSecret, or finishSecret)

        context (LambdaContext): The Lambda runtime information

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

        ValueError: If the secret is not properly configured for rotation

        KeyError: If the event parameters do not contain the expected keys

    """
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']
    log_info = {
        "arn": arn,
        "token": token,
        "step": step,
    }

    # Setup the client
    service_client = boto3.client('secretsmanager', endpoint_url=os.environ.get('SECRETS_MANAGER_ENDPOINT', None))
    log(log_info, "starting", False)

    # Make sure the version is staged correctly
    metadata = service_client.describe_secret(SecretId=arn)
    if not metadata['RotationEnabled']:
        log(log_info, "secret is not enabled for rotation")
        raise ValueError("Secret %s is not enabled for rotation" % arn)
    versions = metadata['VersionIdsToStages']
    if token not in versions:
        log(log_info, "secret version has no stage for rotation of secret")
        raise ValueError("Secret version %s has no stage for rotation of secret %s." % (token, arn))
    if "AWSCURRENT" in versions[token]:
        log(log_info, "secret already set as AWSCURRENT", False)
        return
    elif "AWSPENDING" not in versions[token]:
        log(log_info, "secret version not set as AWSPENDING for rotation")
        raise ValueError("Secret version %s not set as AWSPENDING for rotation of secret %s." % (token, arn))

    if step == "createSecret":
        create_secret(service_client, arn, token)

    elif step == "setSecret":
        set_secret(service_client, arn, token)

    elif step == "testSecret":
        test_secret(service_client, arn, token)

    elif step == "finishSecret":
        finish_secret(service_client, arn, token)

    else:
        raise ValueError("Invalid step parameter")


def create_secret(service_client, arn, token):
    """Create the secret

    This method first checks for the existence of a secret for the passed in token. If one does not exist, it will generate a
    new secret and put it with the passed in token.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

    """
    # Make sure the current secret exists
    # service_client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")
    log_info = {
        "arn": arn,
        "token": token,
        "step": "createSecret"
    }

    # Now try to get the secret version, if that fails, put a new secret
    try:
        service_client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        log(log_info, "successfully retrieved pending secret", False)
    except service_client.exceptions.ResourceNotFoundException:
        log(log_info, "generating keypair", False)
        public_key, private_key = rsa.newkeys(2048)
        log(log_info, "generated keypair", False)
        private_key_pem = private_key.save_pkcs1().decode(),
        public_key_pem = public_key.save_pkcs1().decode(),
    
        secret_data = json.dumps({
            'private_key': ''.join(private_key_pem),
            'public_key': ''.join(public_key_pem),
        })
        log(log_info, {"public_key": public_key_pem}, False)

        # Put the secret
        service_client.put_secret_value(SecretId=arn, ClientRequestToken=token, SecretString=secret_data, VersionStages=['AWSPENDING'])
        log(log_info, "successfully put secret")


def set_secret(service_client, arn, token):
    """Set the secret

    This method should set the AWSPENDING secret in the service that the secret belongs to. For example, if the secret is a database
    credential, this method should take the value of the AWSPENDING secret and set the user's password to this value in the database.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    """
    # This is where the secret should be set in the service
    log_info = {
        "arn": arn,
        "token": token,
        "step": "setSecret",
    }
    log(log_info, "no action")


def test_secret(service_client, arn, token):
    """Test the secret

    This method should validate that the AWSPENDING secret works in the service that the secret belongs to. For example, if the secret
    is a database credential, this method should validate that the user can login with the password in AWSPENDING and that the user has
    all of the expected permissions against the database.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    """
    # This is where the secret should be tested against the service
    log_info = {
        "arn": arn,
        "token": token,
        "step": "testSecret",
    }
    log(log_info, "no action")


def finish_secret(service_client, arn, token):
    """Finish the secret

    This method finalizes the rotation process by marking the secret version passed in as the AWSCURRENT secret.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    Raises:
        ResourceNotFoundException: If the secret with the specified arn does not exist

    """
    log_info = {
        "arn": arn,
        "token": token,
        "step": "finishSecret",
    }

    # First describe the secret to get the current version
    metadata = service_client.describe_secret(SecretId=arn)
    current_version = None
    for version in metadata["VersionIdsToStages"]:
        if "AWSCURRENT" in metadata["VersionIdsToStages"][version]:
            if version == token:
                # The correct version is already marked as current, return
                log(log_info, "version already marked as AWSCURRENT")
                return
            current_version = version
            break

    # Finalize by staging the secret version current
    service_client.update_secret_version_stage(SecretId=arn, VersionStage="AWSCURRENT", MoveToVersionId=token, RemoveFromVersionId=current_version)
    log(log_info, "successfully set AWSCURRENT stage to version", False)
