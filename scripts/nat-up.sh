#!/bin/bash
# Создаёт временный NAT Gateway для выхода db-server в интернет.
set -euo pipefail

AWS_REGION=eu-central-1
SUBNET_ID=subnet-036a2e625527babf0     # timecapsule-dev-public-a
ROUTE_TABLE_ID=rtb-084cf3c7d9f4ac91f   # timecapsule-dev-private-rt
OWNER=bysinka_95
STATE_FILE="$(dirname "$0")/.nat-state"

export AWS_REGION

tags() {
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=timecapsule},{Key=Environment,Value=dev},{Key=Owner,Value=$OWNER},{Key=Lab,Value=lab3}]"
}

if [[ -f "$STATE_FILE" ]]; then
  echo "Файл $STATE_FILE уже существует: NAT Gateway, похоже, поднят. Сначала выполните nat-down.sh." >&2
  exit 1
fi

echo "==> Выделяем Elastic IP"
ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc \
  --tag-specifications "$(tags elastic-ip timecapsule-dev-nat-a-eip)" \
  --query AllocationId --output text)
echo "ALLOCATION_ID=$ALLOCATION_ID" > "$STATE_FILE"

echo "==> Создаём NAT Gateway в public-a"
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "$SUBNET_ID" --allocation-id "$ALLOCATION_ID" \
  --tag-specifications "$(tags natgateway timecapsule-dev-nat-a)" \
  --query NatGateway.NatGatewayId --output text)
echo "NAT_ID=$NAT_ID" >> "$STATE_FILE"

echo "==> Ждём, пока $NAT_ID станет доступен"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

echo "==> Добавляем маршрут 0.0.0.0/0 в private-rt"
aws ec2 create-route --route-table-id "$ROUTE_TABLE_ID" \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" > /dev/null

echo "Готово. NAT Gateway $NAT_ID, Elastic IP $ALLOCATION_ID. Не забудьте выполнить nat-down.sh."
