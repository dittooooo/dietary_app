import os
import requests
from dotenv import load_dotenv

load_dotenv()
api_key = os.getenv("GOOGLE_API_KEY")

url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
params = {
    "key": api_key,
    "query": "restaurant",
    "location": "25.1759,121.4505",
    "radius": 1500,
    "language": "zh-TW"
}

print(f"Testing URL: {url}")
print(f"Params: {params}")

try:
    response = requests.get(url, params=params)
    print(f"Page 1 Status: {response.status_code}")
    data = response.json()
    print(f"Page 1 API Status: {data.get('status')}")
    
    token = data.get("next_page_token")
    if token:
        print(f"Got next_page_token, waiting 10 seconds...")
        import time
        time.sleep(10)
        
        # Test WITHOUT original parameters (clean request)
        page2_params = {
            "key": api_key,
            "pagetoken": token,
        }
        print(f"Testing Page 2 with params: {page2_params}")
        response2 = requests.get(url, params=page2_params)
        data2 = response2.json()
        print(f"Page 2 API Status: {data2.get('status')}")
        print(f"Page 2 Error Message: {data2.get('error_message', 'N/A')}")
    else:
        print("No next_page_token found.")
except Exception as e:
    print(f"Error: {e}")
