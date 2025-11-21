import http
import os
import json
import requests
import sys 

# Retrieve variables from .env
keys_directory = os.getenv("WEB3SIGNER_KEYS_DIRECTORY")
external_signer_port = os.getenv("WEB3SIGNER_PORT_HTTP")
vc_endpoint = os.getenv("VC_ENDPOINT")

# Load Bearer Token from the txt file
with open("/var/bearer_token.txt", "r") as token_file:
    bearer_token = token_file.read().strip()

# List to store the final results
result_array = []

# Iterate through files in the directory
for filename in os.listdir(keys_directory):
    print(filename)
    if filename.startswith("keystore-") and filename.endswith(".json"):
        filepath = os.path.join(keys_directory, filename)
        with open(filepath, "r") as file:
            data = json.load(file)
            pubkey = data.get("pubkey")
            if pubkey:
                result_array.append({
                    "pubkey": f"0x{pubkey}",
                    "url": f"http://web3signer:{external_signer_port}"
                })

# URL for the POST request
post_url = f"{vc_endpoint}/eth/v1/remotekeys"

print(f"post_url: {post_url}")

headers = {
    "Authorization": f"Bearer {bearer_token}",
    "Content-Type": "application/json"
}

# Send POST request
response = requests.post(post_url, json={"remote_keys": result_array}, headers=headers, verify=False)

if response.status_code == 200:
    print(f"POST request successful - {response.text}")
else:
    print(f"POST request failed: {response.status_code} - {response.text}")
    sys.exit(response.status_code)  # 에러 코드와 함께 스크립트 종료

fee_recipient_path = os.path.join(keys_directory, 'feeRecipient')

# feeRecipient.json 파일 확인 및 처리
if os.path.exists(fee_recipient_path):
    with open(fee_recipient_path, 'r') as file:
        remote_keys = json.load(file)

    # 각 항목에 대해 POST 요청 보내기
    for item in remote_keys:
        pubkey = item['validatorPubKey']
        fee_recipient = item['feeRecipient']

        # POST 요청 URL
        post_url = f"{vc_endpoint}/eth/v1/validator/{pubkey}/feerecipient"

        # POST 요청 보내기
        response = requests.post(post_url, json={"ethaddress": fee_recipient}, headers=headers, verify=False)

        # 응답 처리
        if response.status_code != 202:
            print(f"POST request failed for {pubkey}: {response.status_code} - {response.text}")
            sys.exit(response.status_code)  # 에러 코드와 함께 스크립트 종료

        print(f"POST request successful for {pubkey} - {response.text}")    