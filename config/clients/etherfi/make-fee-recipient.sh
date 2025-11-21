#!/bin/bash

# data.json에서 validator.phase가 "LIVE"인 항목들을 추출하고, etherfiNode를 feeRecipient로 이름 변경
jq '[.data.bids[] | select(.validator.phase == "LIVE") | {validatorPubKey: .validator.validatorPubKey, feeRecipient: .validator.etherfiNode}]' data.json > feeRecipient