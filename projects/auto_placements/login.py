# auth_setup.py
import os
import time
from playwright.sync_api import sync_playwright

def run_auth():
    # Make sure the directory to save the authentication file exists
    os.makedirs(".auth", exist_ok=True)
    auth_file = ".auth/user.json"

    with sync_playwright() as p:
        # Launch a visible browser so you can watch and interact with it
        browser = p.chromium.launch(headless=False, channel="chrome")
        context = browser.new_context()
        page = context.new_page()

        # 1. Navigate to your login page
        print("=" * 60)
        print("INTERACTIVE LOGIN MODE")
        print("=" * 60)
        print("\nOpening login page...")
        page.goto("https://support.econjobmarket.org/user/login")

        # 2. INTERACTIVE: Wait for manual login instead of filling credentials
        print("\nPlease log in manually on the webpage that just opened.")
        print("\nAfter you successfully log in and see your dashboard:")
        print("  1. Make sure you're fully logged in")
        print("  2. Return to this terminal")
        print("  3. Press ENTER to save your session")
        print("=" * 60)
        
        input("\nPress ENTER after you have logged in successfully...")
        
        # Give a moment for any final page loads
        time.sleep(2)

        # 3. Verify login success by checking for "Full Name" in page content
        print("\nVerifying login...")
        current_url = page.url
        print(f"Current URL: {current_url}")
        
        # Check if the page contains "Full Name" text
        try:
            page.wait_for_selector("text=Full Name", timeout=5000)
            print("✓ Login verified! Found 'Full Name' on the page.")
            
            # 4. Save the cookies and local storage state to a JSON file
            context.storage_state(path=auth_file)
            print(f"✓ Saved login session successfully to {auth_file}!")
            print("\nYou can now use this saved session in other scripts.")
            print("Closing browser...")
            
        except:
            print("\nWARNING: Could not find 'Full Name' on the page.")
            print("This may mean login was not successful.")
            
            # Also check if still on login page
            if "login" in current_url.lower():
                print("WARNING: Still on login page URL.")
            
            # Show page content for debugging
            page_text = page.text_content("body")
            if page_text and len(page_text) > 100:
                print(f"\nPage preview: {page_text[:200]}...")
            
            proceed = input("\nContinue anyway and save session? (y/n): ")
            if proceed.lower() != 'y':
                print("Aborting without saving session.")
                browser.close()
                return
            
            # Save session even though verification failed
            context.storage_state(path=auth_file)
            print(f"✓ Saved login session to {auth_file} (unverified)")

        browser.close()
        print("✓ Browser closed.")

if __name__ == "__main__":
    run_auth()
