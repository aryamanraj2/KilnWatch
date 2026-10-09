"""Obtain a Cognito ID token for live smoke tests without exposing it.
Prompts for the password (and a new one if Cognito requires it) with getpass and
writes only 'Authorization: <IdToken>' to a mode-600 file. Never prints the token.
Usage: id_token.py --username EMAIL --client-id ID [--region R] [--out PATH]
"""
import argparse
import getpass
import os
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--username',required=True)
parser.add_argument('--client-id',required=True)
parser.add_argument('--region',default='ap-south-1')
parser.add_argument('--out',type=Path,default=Path('.local/integration-2b/auth-header'))
a=parser.parse_args()
import boto3
idp=boto3.client('cognito-idp',region_name=a.region)
r=idp.initiate_auth(ClientId=a.client_id,AuthFlow='USER_PASSWORD_AUTH',
                    AuthParameters={'USERNAME':a.username,'PASSWORD':getpass.getpass('Password: ')})
if r.get('ChallengeName')=='NEW_PASSWORD_REQUIRED':
    new=getpass.getpass('New password: ')
    if new!=getpass.getpass('Repeat new password: '):raise SystemExit('Passwords differ; nothing written.')
    r=idp.respond_to_auth_challenge(ClientId=a.client_id,ChallengeName='NEW_PASSWORD_REQUIRED',Session=r['Session'],
                                    ChallengeResponses={'USERNAME':a.username,'NEW_PASSWORD':new})
if 'AuthenticationResult' not in r:raise SystemExit('Unexpected challenge: '+str(r.get('ChallengeName')))
a.out.parent.mkdir(parents=True,exist_ok=True)
fd=os.open(a.out,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as f:f.write('Authorization: '+r['AuthenticationResult']['IdToken']+'\n')
os.chmod(a.out,0o600)
print('ID token header written to',a.out,'(mode 600). Delete it after the checks.')
