"""
Rebuild semi automate individual search
structured around following institutions list
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
import threading
from camoufox.sync_api import Camoufox


def get_graduates_without_outcomes(cursor, oid):
  print(f"Fetching unplaced graduates: {oid}")
  query = """
        select distinct a.fname,a.lname,a.aid,a.degreeinst_oid,year(a.enrolldate) as enrolldate,r.aid as raid,
        i.name,o.department 
        from ftrecruiter.applicants a left join econjobmarket_research.applicant_results r
        on a.aid=r.aid join ftrecruiter.organizations o 
        on o.oid=a.degreeinst_oid 
        join ftrecruiter.institutions i on i.institution_id=o.institution_id 
        where a.degreeinst_oid=? and year(a.enrolldate)>='2018' and degree_id=13 and r.aid is null 
      """
  try:
    cursor.execute(query, [oid])
    rows = cursor.fetchall()
  except mariadb.Error as e:
    print(f"Error in query: {e}")
    cursor.close()
    conn.close()
    sys.exit(1)
  return rows
# claude didn't work just debugging
def get_claude_suggestion(client, row): 
  url = "https:www.google.com/search?q="
  query = url+row[0]+"+"+row[1]+"+"+row[6]+"+"+row[7]
  print(query)
#
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
    #p = sync_playwright().start()
    # Launch browser (headless=False to see the browser window)
    print(f"Launching browser...")
    #browser = p.chromium.launch(headless=False, channel="chrome")
    browser_context = Camoufox(headless=False)      
    # Create a new context with saved authentication state (if available)
    #if auth_file:
    browser = browser_context.start()
    #  playwright_browser = browser.browser
    context = browser.new_context(storage_state=auth_file)
    #  print("✓ Logged in using saved session")    
  return browser, context, browser_context
#
def set_dropdown(page, label, preferred_element):
  dropdown = page.get_by_label(label)
  print(f"Trying to set {label}")
  available_options = dropdown.locator("option").all_inner_texts()
  if preferred_element in available_options:
    dropdown.select_option(label=preferred_element)
  else:
    dropdown.select_option(label= available_options[0])
#
def handle_page_error(exc):
  print(f"[Frontend JS Exception] Uncaught error:{exc.message}")
#
def applicant_forms(candidate_url, row, context):
  page0 = context.new_page()
  url = candidate_url+str(row[2])
  page0.goto(url)
  print(f"Opened {page0.url}")
  #page1 = context.new_page()
  #google_url = "https://www.google.com/search?q="+row[0]+"+"+row[1]+"+"+row[6]+"+"+row[7]
  #page1.goto(google_url)
  #errors1 = [msg.text for msg in page1.console_messages() if msg.type == "error"]
  #exceptions1 = [err.message for err in page1.page_errors()]
  #print(errors1)
  #print(exceptions1)
  page2 = context.new_page()
  outcome_url = preoutcome_url+str(row[2])
  page2.goto(outcome_url)
  print(f"Opened {page2.url}")

  #return page0, page1, page2
  return page0,page2
#
def handle_new_page(new_page: page, find_applicant_form, newoutcome_form, row):
  global terminate_signal
  new_page.wait_for_load_state("domcontentloaded")
  url = new_page.url
  print(f"Looking for {newoutcome_form+str(row[2])}")
  print(f"Seeing {url}")
  if find_applicant_form in url:
    terminate_signal = url
    return
  elif newoutcome_form+str(row[2]) in url:
    parsed = urlparse(url)
    parts = parsed.path
    p = parts.split("/")
    num = len(p)
    institution_id = p[num - 1]
    aid = p[num - 2]
    labels = ["Choose the department which hosts the job",
              "Choose a position type",
              "Choose the year the job started"]
    institution_type = find_institution_type(cursor, institution_id)
    set_dropdown(new_page, labels[0], "Economics")
    if institution_type == 1:
      set_dropdown(new_page, labels[1], "Assistant Professor")
    else:
      set_dropdown(new_page, labels[1], "Other Non-Academic")
    set_dropdown(new_page, labels[2], "2026")
  #else:
  #  return
#
def find_institution_type(cursor, institution_id):
  query = """
    select academic from ftrecruiter.institutions where institution_id=?
    """
  cursor.execute(query, [institution_id])
  row = cursor.fetchone()
  return row[0]
# 
def get_degreeendyear(cursor, aid):
  query ="""
    select degreeendyear from ftrecruiter.applicants where aid = ?
    """
  cursor.execute(query, [aid])
  row = cursor.fetchone()
  return row[0]
#
if __name__ == "__main__":
  parser = argparse.ArgumentParser()
  parser.add_argument("-o", "--oid", type=int, required=True, help="use -o and add an organization id")
  args = parser.parse_args()
  oid = args.oid
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
  candidate_url = "https://support.econjobmarket.org/candidate/"
  preoutcome_url = "https://support.econjobmarket.org/preoutcome/"
  newoutcome_url = "https://support.econjobmarket.org/newoutcome/"
  find_applicant_url = "https://support.econjobmarket.org/find_applicant_form"
  graduate_data = get_graduates_without_outcomes(cursor, oid)
  auth_file = ".auth/user.json"
  #
  browser, context, browser_context = start_session(auth_file)   
  rows = get_graduates_without_outcomes(cursor, oid)
  total_entries = len(rows)
  print(f"Found {total_entries} placements")
  #terminate_signal = threading.Event()
  
  for row in rows:
    terminate_signal = None
    print(f"\n{'='*60}")
    print(f"Processing candidate {total_entries}")
    print(f"Name: {row[0]} {row[1]}")
    print(f"Institution: {row[6]}, Department: {row[7]}")
    print(f"{'='*60}\n")
    #context.on("page", lambda page: handle_new_page(page, find_applicant_form=find_applicant_url, newoutcome_form=newoutcome_url, row = row))
    # Open candidate page and new outcome form
    #while not terminate_signal.is_set():  
    page0, page2 = applicant_forms(candidate_url, row, context)
    while not terminate_signal:
      try:
        #event_info = context.wait_for_event("page", timeout=500000)
        #new_page = event_info
        current_url = page2.url
        page2.wait_for_url(
          lambda url: (find_applicant_url in url or newoutcome_url in url) and (url != current_url),
          timeout = 500000
          )
        #new_page.wait_for_load_state("domcontentloaded")
        print(f"Found {page2.url}")
        handle_new_page(page2, find_applicant_url, newoutcome_url, row) 
        #handle_new_page(new_page, find_applicant_url, newoutcome_url, row)
        #if find_applicant_url in new_page.url:
        #  terminate_signal = find_applicant_url
        #  print(f"Found {terminate_signal}")
      except Exception as e:
        print(f"An error ocurred: {str(e)}")
        break
        #terminate_signal.wait(timeout=5.0)
    
    # Close pages before moving to next candidate
    for page in context.pages:
      page.close()
    continue
  context.close()
  browser.close()
  browser_context.close()
  cursor.close()


