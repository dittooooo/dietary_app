import os
import requests
import time
from dotenv import load_dotenv

load_dotenv()
api_key = os.getenv("GOOGLE_API_KEY")

ts_url = "https://maps.googleapis.com/maps/api/place/textsearch/json"
nb_url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"

params = {
    "key": api_key,
    "query": "麵店 near 淡江大學",
    "language": "zh-TW"
}

print(f"Testing Text Search Page 1...")
response = requests.get(ts_url, params=params)
data = response.json()
print(f"Page 1 API Status: {data.get('status')}")

token = data.get("next_page_token")
if token:
    print(f"Got next_page_token, waiting 5 seconds...")
    time.sleep(5)
    
    page2_params = {
        "key": api_key,
        "pagetoken": token
    }
    
    print(f"Testing Page 2 with Text Search URL...")
    response_ts = requests.get(ts_url, params=page2_params)
    print(f"TS Response Status: {response_ts.json().get('status')}")
    
    print(f"Testing Page 2 with Nearby Search URL...")
    response_nb = requests.get(nb_url, params=page2_params)
    print(f"NB Response Status: {response_nb.json().get('status')}")
else:
    print("No next_page_token found.")
