"""
Rebuild of applicant_search
"""
from playwright.sync_api import sync_playwright
import time
import sys
import os
import re
from datetime import datetime
import builtins
import json
import argparse
from urllib.parse import urlparse
import mariadb
from dotenv import load_dotenv



def get_placements(json_file):
    print(f"Reading placement data from: {json_file}")
    try:
        with open(json_file, 'r') as f:
            placements_data = json.load(f)
        
        print(f"✓ Loaded {len(placements_data)} placement records")
        
    except Exception as e:
        print(f"⚠ Error reading JSON file: {e}")
        print("Using default values...")
        placements_data = [{
            'name': 'ryan steven toronto',
            'initial_employment': 'University of Toronto',
            'university': 'University of Toronto',
            'source_url': '',
            'placement_year': '2026'
        }]
    return placements_data
def start_session(auth_file):
  if not os.path.exists(auth_file):
    print(f"WARNING: Authentication file not found at {auth_file}")
    print("You may need to run login.py first to save your session.")
    print("Continuing without authentication...\n")
    return None, None
  else:
    print(f"✓ Found authentication file: {auth_file}")
    print("Loading saved session...\n")      
    # Start Playwright context manager
    p = sync_playwright().start()
    # Launch browser (headless=False to see the browser window)
    print(f"Launching browser...")
    browser = p.chromium.launch(headless=False, channel="chrome")      
    # Create a new context with saved authentication state (if available)
    if auth_file:
      context = browser.new_context(storage_state=auth_file)
      print("✓ Logged in using saved session")    
  return browser, context
#
def get_graduate(entry):
  name = entry['name']
  initial_employment = entry['initial_employment']
  university = entry['university']
  source_url = entry['source_url']
  placement_year = entry['placement_year']
  # Split name into first and last
  name_parts = name.split()
  fname = name_parts[0]
  lname = name_parts[-1]
  # Create search query (last name first)
  search_query = f"{lname} {fname} {university}"
  return initial_employment, university, source_url,placement_year, search_query
#
def extract_aid(url):
   path = urlparse(url).path
   path_parts = path.strip("/").split("/")
   return path_parts[1]
#
def extract_institution_id(url):
   path = urlparse(url).path
   path_parts = path.strip("/").split("/")
   return path_parts[2]
#
def set_dropdown(page, label, preferred_element):
  dropdown = page.get_by_label(label)
  available_options = dropdown.locator("option").all_inner_texts()
  if preferred_element in available_options:
    dropdown.select_option(label=preferred_element)
  else:
    dropdown.select_option(label= available_options[0])
  return page
#
def find_applicant_form(find_applicant_url, search_query, context):
  page = context.new_page()
  page.goto(find_applicant_url)
  page.get_by_label("Find the aid for an applicant").fill(search_query)
  page.wait_for_url(lambda url: url != find_applicant_url, timeout=300000)
  aid = extract_aid(page.url)
  return page, aid
#
def pre_outcome_form(aid, initial_employment, preoutcome_url, page):
    new_url = preoutcome_url + aid
    page.goto(new_url)
    page.get_by_label("Choose the university which hired the applicant").fill(initial_employment)
    page.wait_for_url(lambda url: url != new_url, timeout=300000)
    institution_id = extract_institution_id(page.url)
    #fill form elements
    return page, institution_id
   
if __name__ == "__main__":
  parser = argparse.ArgumentParser(description="A sample script demonstrating command-line options.")
  parser.add_argument("-f", "--file", type=str, required=True, help="use -f data filename")
  parser.add_argument("-s", "--skip", type=str, required=False, help="use -s namestring to skip through entries until name matches your namestring")
  args = parser.parse_args()
  json_file = args.file
  load_dotenv()
  db_config = {\
    "user": os.getenv("DB_USER"),\
    "password": os.getenv("DB_PASSWORD"),\
    "host": os.getenv("DB_HOST", "127.0.0.1"),\
    "port": int(os.getenv("DB_PORT", 3306)),\
    "database": os.getenv("DB_NAME")\
  }
  if not db_config["user"] or not db_config["password"]:
    print("Error: DB_USER or DB_PASSWORD is missing from your .env file.")
    sys.exit(1)
  try:                                                                  
    conn = mariadb.connect(**db_config)
    print("Successfully connected to MariaDB using secure .env credentials!")                                                                                     
    cursor = conn.cursor()
  except mariadb.Error as e:
    print(f"Error connecting to MariaDB Platform: {e}")
    cursor.close()
    conn.close()
    sys.exit(1)
  query = """
    SELECT to_institution_id 
    from to_data t join from_data f on t.aid=f.aid 
    where t.aid = ?
    """                                                                             
  candidate_url = "https://support.econjobmarket.org/candidate/"
  preoutcome_url = "https://support.econjobmarket.org/preoutcome/"
  newoutcome_url = "https://support.econjobmarket.org/newoutcome/"
  find_applicant_url = "https://support.econjobmarket.org/find_applicant_form"
  placements_data = get_placements(json_file)
  auth_file = ".auth/user.json"
  #
    
  browser, context = start_session(auth_file)   
  current_index = 0
  total_entries = len(placements_data)
  find_name = args.skip
  if find_name is not None:
     skip_entry = True
  else:
     skip_entry = False
  for placement in placements_data:
    if skip_entry:
      if placement["name"] == find_name:
        skip_entry = False
      else:
         continue      
    initial_employment, university, source_url,placement_year, search_query =\
      get_graduate(placement)
    page, aid = find_applicant_form(find_applicant_url, search_query, context)
    if int(aid) == 0:
      continue
    try:
      cursor.execute(query, [aid])
      rows = cursor.fetchall()
    except mariadb.Error as e:
      print(f"Error in query: {e}")
      cursor.close()
      conn.close()
      sys.exit(1)
    if len(rows) > 0:
      flat_values = [r[0] for r in rows]
      target = 754
      if target not in flat_values:
        continue    
    print(f"Found aid {aid} to process\n")  
    page, institution_id = pre_outcome_form(aid, initial_employment, preoutcome_url, page)
    print(f"Found {institution_id}")
    page = set_dropdown(page, "Choose the department which hosts the job" , "Economics")
    page = set_dropdown(page, "Choose a position type" , "Assistant Professor")
    page = set_dropdown(page, "Choose the year the job started" , placement_year)
    page.get_by_label("A url where you found your information").fill(source_url)
    page.get_by_label("Notes").fill(search_query)
    page.wait_for_url("**find_applicant_form*",  timeout=300000)
  #page.close()  
  context.close()
  browser.close()
      

