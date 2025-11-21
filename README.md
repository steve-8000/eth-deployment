# Ethereum Node Infrastructure

엔터프라이즈급 이더리움 노드 운영을 위한 구조화된 인프라스트럭처입니다.

## 빠른 시작

```bash
./deploy.sh
```

스크립트를 실행하면 단계별로 선택할 수 있는 메뉴가 표시됩니다.

## 사용 가이드

### 최초 배포

```bash
./deploy.sh
```

메뉴에서 New Deployment를 선택한 후 단계별로 구성합니다:

- 네트워크 선택 (Mainnet, Sepolia, Holesky 등)
- Execution Client 선택 (Geth, Nethermind, Reth)
- Consensus Client 선택 (Lighthouse, Teku, Prysm, Lodestar)
- MEV 옵션 선택 (MEV-Boost, Commit Boost, Both, None)
- Validator Client / DVT 선택 (VC, Obol DVT, SSV DVT, Web3Signer, None)

모든 선택이 완료되면 Deploy를 선택하여 배포합니다.

### 재시작 및 관리

```bash
./deploy.sh
```

메뉴에서 Restart / Manage Existing을 선택하면 다음 기능을 사용할 수 있습니다:

- View Status: 현재 상태 확인
- Stop Services: 서비스 중지
- Restart Services: 서비스 재시작
- View Logs: 실시간 로그 확인 (최소 1000줄부터 표시)
- Save Logs: 최신 1000줄 로그를 파일로 저장
- Complete Removal: 완전 삭제 (데이터 포함)

### 설정 변경 후 재시작

1. 환경 설정 파일 편집
```bash
vi .env
```

2. 배포 스크립트 실행
```bash
./deploy.sh
```

3. Restart / Manage Existing → Restart Services 선택

## 배포 후 관리

### 상태 확인

```bash
docker compose -f docker-compose.generated.yaml ps
```

### 로그 확인

메뉴를 통한 로그 확인:
```bash
./deploy.sh → Restart / Manage Existing → View Logs
```

직접 명령어로 확인:
```bash
docker compose -f docker-compose.generated.yaml logs -f
```

### 서비스 제어

```bash
# 중지
docker compose -f docker-compose.generated.yaml stop

# 재시작
docker compose -f docker-compose.generated.yaml restart

# 완전 제거
docker compose -f docker-compose.generated.yaml down
```

## 프로젝트 구조

```
ethereum-node/
├── .env                    # 환경 설정 파일
├── deploy.sh               # 배포 스크립트
├── bin/deploy              # 메인 배포 스크립트
├── lib/deploy/             # 배포 라이브러리
├── config/                 # 설정 파일
│   ├── templates/         # 설정 템플릿
│   └── clients/           # 클라이언트별 설정
├── docker/compose/         # Docker Compose 파일
├── monitoring/            # 모니터링 설정
└── scripts/               # 운영 스크립트
```

## 환경 설정

`.env` 파일을 최상위 폴더에서 수정하여 환경 변수를 설정합니다.

주요 설정 항목:
- 네트워크 및 클라이언트 버전
- 포트 설정
- MEV-Boost 릴레이 주소
- 수수료 수신 주소

## 로그 관리

실시간 로그 확인 시 최소 1000줄부터 표시되며, 전체 로그, Error 레벨만, Warning 레벨만 선택할 수 있습니다.

로그 저장 기능을 사용하면 `logs/` 디렉토리에 최신 1000줄이 자동으로 저장됩니다.
