## Api Documentation

Much of the mapinator data is publicly available through the api at 
website [https://support.econjobmarket.org](https://support.econjobmarket.org).

To access the data you can choose from a number of different requests as listed below. For example, one request is just to retrieve
the data that is used to create the mapinator itself at
[https://sage.microeconomics.ca](https://sage.microeconomics.ca).  To fetch this data you would use an url like the following"
```
https://support.econjobmarket.org/api/mapinator
```
### mapinator

The data is always returned as an array of json formatted strings, like this:

```
{"aid":"51208","to_institution_id":"3295","to_name":"Georgetown University Qatar","to_oid":"5624","startdate":"2021-07-01","to_latitude":null,"to_longitude":null,"to_rank":null,"recruiter_type":"4","description":"Academic organization (other than econ, business, or ag econ)","to_shortname":"Foreign Service, Georgetown Univ","to_department":"All departments","postype":"1","position_name":"Assistant Professor","created_at":"2021-07-04 17:36:07","created_by":"25","from_oid":"36","from_institution_id":"6","latitude":"34.068921","longitude":"-118.4451811","from_institution_name":"University of California Los Angeles (UCLA)","from_shortname":"Economics, UCLA","from_department":"Economics","category_id":"8","name":"International Finance\/Macro","rank":"20"}
```
Most of the elements of this string are self explanatory.  The field `aid` is an id number that can be used to identify records that 
belong to the same graduate.  The field `to_name` refers to the university who hired the applicant.  The `institution_id` identifies the institution by a number.  The field `to_oid` is a number that refers to the organization that hired the applicant. `to_shortname` and `to_department` identify the organization within the university who hired the applicant. 

`postype` is a numeric idetifier for the `position_name` that follows.

The field `category_id` is a numeric identifier for the applicants primary field which is listed in textual form next in the field
`name`.

### placement_data

This will return information that is the same as the property mapinator does.  However, the mapinator data requires at least one of 
organizations involved has longitude and latitude coordinates.  The property placement data does not contain geo-coordinates.  As 
such it includes many placement records that aren't included in the mapinator information.

### Other

You can also use keywords `organizations` and `categories` to find a list of organizations and primary fields.  The data is returned
as an array of json formatted strings with the interpretation of the fields being the same as it is with the placement data.

## Secured information

Some additional information is currently available to researchers who have approved research projects with econjobmarket.org. 
Approved researchers are given accounts at [https://support.econjobmarket.org](https://support.econjobmarket.org) which they can use 
to fetch the access_tokens that are needed to get the information.

## Software
 
A couple of programs are included to help you if you have secure access to the data.  Currently there is a python program that will fetch an access token called `get_token.ipynb` and a julia program called `get_data.ipynb` that will use the access token to fetch the data you want.  Each of these is designed to be used in a jupyter notebook.  They will easily adapt to command line programs or visual basic scripts, whatever you like to use.

Both rely on the same .env file that needs to be stored in the directory where the scripts are running.  If you are using the code to get
data from the econjobmarket api, the .env looks like this before you run the `get_token.ipynb` script:

```
token_url=https://support.econjobmarket.org/oauth2/token
api_url=https://support.econjobmarket.org/api
client_key=support_token_server
client_secret=4support_server2work
username=your_username_at_support.econjobmarket.org
password=your_password_at_support.econjobmarket.org
access_token=
refresh_token=
```

Of course, you'll need to use your actual username and password above.

It will look like this after you run the get_token script

```
token_url=https://support.econjobmarket.org/oauth2/token
api_url=https://support.econjobmarket.org/api
client_key=support_token_server
client_secret=4support_server2work
username=your_username_at_support.econjobmarket.org
password=your_password_at_support.econjobmarket.org
access_token='eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJpZCI6IjE0MzU3NThhZDJiNjJiNmUwNTkwZWYwMTg1Y2NkMmY5MTFjNjJkNzAiLCJqdGkiOiIxNDM1NzU4YWQyYjYyYjZlMDU5MGVmMDE4NWNjZDJmOTExYzYyZDcwIiwiaXNzIjoiaHR0cHM6XC9cL3N1cHBvcnQuZWNvbmpvYm1hcmtldC5vcmdcLyIsImF1ZCI6InN1cHBvcnRfdG9rZW5fc2VydmVyIiwic3ViIjoiNiIsImi4cCI6MTY1NjAxMTU3MywiaWF0IjoxNjU2MDA3OTczLCJ0b2tlbl90eXBlIjoiYmVhcmVyIiwic2NvcGUiOiJiYXNpYyJ9.JuEZI2GyZzf6aMCsvOLg3eeEXRMIZ9pRjbtXY2UxCFBYTejd1fCEvHNBiQ4bZeAUS2AYjLztiKD_HBOgvFsEChqbzwCckZg0cjoc6Y8sGH-g1XFdIRcedrcOKavWuA5WAHZ351wTwWrmsMw10DhT8h_6gntZhXvtg4Si9JL6neUZ6tuHgcidkTj4xcuGQs3bTd9d2_oc_XvSp5PFdxRj-cr_8LPDuvQd6xlcDEIxqQKCLEJIcGCoJGJZk8VRgIi0-yPdq-cWxb4DVvVYSjfe8BwnJXpLbLlWAZ-ZMRllJtrIftzomAQM_quNEsIHZY6l8AseEGkyOjV5q4wY6DYbmQ'
refresh_token='e0df7c722063565be8e1c1d642b9065d4ac1c96c'
```



