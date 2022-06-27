Tali Yaffe 
May 31, 2022

# EJM Button

## Description
This tool enables you to quickly search for the job placement outcomes of economics PhD graduates in the econjobmarket.org database. It automatically launches the site https://support.econjobmarket.org with three different candidate pages, along with corresponding web search tabs for their CVs. The script was originally written by Kieran Weaver, and was modified by Jonah Heyl.

## Prerequisites
You must be logged into your account on https://support.econjobmarket.org before using this tool. As well, you must have Python installed on your computer.

## Downloading the File
1. Go to https://github.com/Jonah-Heyl/EJM_button.
2. Click the green icon titled "Code", then select "Download ZIP" from the dropdown menu.
3. Save the folder "EJM_button-main" to your preferred directory (we will use the Downloads folder in this example).

## Getting Started
1. Open Terminal. Type in `cd /Users/username/Downloads/EJM_button-main`, then hit enter.
2. Type in `python vse_data_entry_tool.py`, then hit enter.
3. A new window will appear with a button that says "Add slice". Click this button. 
4. In the Terminal window, you will be prompted to enter the username for your account on https://support.econjobmarket.org. Type it in, then hit enter.
5. You will then be prompted to enter the password for your account on https://support.econjobmarket.org. Type it in, then hit enter.
6. Three tabs with candidate pages on the EJM support site will launch in your web browser, along with three web search tabs for the candidates' CVs. 

Once logged in, the script will create a file called "user.dat", which will be saved on your computer. This file stores your login credentials, as well as the latest access token. If you delete this file, you will be prompted to log in again once your access token expires. 

## Making Modifications
Open the file `vse_data_entry_tool.py` in your preferred editor. 

* **Changing the search criteria:** Line 32 contains the following code: `SEARCH = "https://www.google.com/search?q={}+{}+economics+cv"`. To search for something else, such as a LinkedIn profile, simply change the `+cv` to `+LinkedIn`.  

* **Changing the number of candidates displayed at a time:** First modify Line 31. For example, if you want to search for 5 candidates, change `slice_length=3` to `slice_length=5`. Next, change the code in Line 191 from `for i in range(0,3)` to `for i in range(0,5)`.

Save the modified file, open a new Terminal window, and then repeat the steps in "Getting Started" to perform a search with the new criteria.

## Navigating the Support Site
* **Applicant Database:** A list of all the applicants on EconJobMarket. Can filter the applicants by their registration date, institution they obtained their PhD from, and whether they have any outcomes recorded.
* **Institutions:** A list of the top 100 institutions, sorted by rank. 
* **FindApplicantByName:** Can search for specific applicants by their last name. 
* **Find a Kim:** Clicking this link opens the page of an applicant who has an incomplete entry. Incomplete entries can be fixed on this page.
* **Find a Legacy Applicant:** Clicking this link opens the page of a Legacy Applicant who has an incomplete entry. Incomplete entries can be fixed on this page.
