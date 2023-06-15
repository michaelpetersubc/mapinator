#!/usr/bin/env python
# coding: utf-8

# In[1]:


import os
import requests
from os import environ as env
import dotenv
import json
from dotenv import load_dotenv
def get_token():
    '''
    get_token()
    returns an access token in a json string, or an error message again as a json string on failure
    
    Configuration values are retrieved from a file called `.env` in the root of the project.
    
    When tokens are successfully returned they are written to the `.env` so that they can be used
    by other functions and programs that can read that file.
    
    The file `.env` must contain the following data
    ```
    token_server=
    api_server=
    client_key=
    client_secret=
    username=
    password=
    access_token=
    refresh_token=
    ```
    The refresh and access token fields can be left blank.  The accompanying documentation describes how to fill out
    the other values
    '''
    load_dotenv()
    req_headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
    }
    token_url = os.environ["token_url"]
    new_token_payload = {
    'client_id' : os.environ["client_key"],
    'client_secret' : os.environ["client_secret"],
    'grant_type' : 'password',
    'username' : os.environ["username"],
    'password' : os.environ["password"]
    }
    refresh_token_payload = {
        'client_id' : os.environ["client_key"],
        'client_secret' : os.environ["client_secret"],
        'grant_type' : 'refresh_token',
        'refresh_token' : os.environ["refresh_token"],
    }
    if ("token_url" in os.environ.keys()) is False:
        response = {
            "error" : "file error",
            "error_description" : ".env file is missing or is malformed not token server"
        }
        return json.dumps(response)
    if os.environ["refresh_token"]:
        response = requests.post(os.environ["token_url"], headers=req_headers, data=refresh_token_payload)
        dotenv_file = dotenv.find_dotenv()
        dotenv.load_dotenv(dotenv_file)
        dotenv.set_key(dotenv_file, "access_token", response.json()["access_token"])
        dotenv.set_key(dotenv_file, "refresh_token", response.json()["refresh_token"])
        success = {
            "success" : "new environment file written",
            "new_access_token" : response.json()["access_token"]
        }
        return json.dumps(success)
    response = requests.post(os.environ["token_url"], headers=req_headers, data=new_token_payload)
    dotenv_file = dotenv.find_dotenv()
    dotenv.load_dotenv(dotenv_file)
    dotenv.set_key(dotenv_file, "access_token", response.json()["access_token"])
    dotenv.set_key(dotenv_file, "refresh_token", response.json()["refresh_token"])
    success = {
        "success" : "new environment file written",
        "new_access_token" : response.json()["access_token"]
    }
    return json.dumps(success)

#print(get_token())


# In[2]:


def get_data(property):
    '''
    get_data(property)
    
    Fetches data from the api at support.econjobmarket.org
    
    property - a string that give one of the properties available through the api. For example if property='mapinator' then the
    function will execute a get requst to 
    ```
    https://support.econjobmarket.org/api/mapinator
    ```
    the function returs either an array of json strings on success, or a single json string with an error message when it fails.
    
    if the request requires an access token, the function retrieves it from environment variables
    '''
    load_dotenv()
    new_headers = {
        "Accept" : "application/json",
        "Authorization" : "Bearer "+os.environ["access_token"],
    }
    api_url = os.environ["api_url"]+"/"+property
    r = requests.get(api_url, headers = new_headers)
    return r.json()


# In[3]:


## the next bit fetches a 'slice' of data from the api and creates a pandas dataframe with it.
import pandas as pd
get_token()
#res = get_data('slice')
#df = pd.json_normalize(res)

