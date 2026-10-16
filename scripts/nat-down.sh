#!/bin/bash
# Удаляет временный NAT Gateway, созданный nat-up.sh.
set -euo pipefail

AWS_REGION=eu-central-1
ROUTE_TABLE_ID=rtb-084cf3c7d9f4ac91f   # timecapsule-dev-private-rt
STATE_FILE="$(dirname "$0")/.nat-state"

export AWS_REGION

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Файл $STATE_FILE не найден: нечего удалять." >&2
  exit 1
fi
source "$STATE_FILE"

if [[ -n "${NAT_ID:-}" ]]; then
  echo "==> Удаляем маршрут 0.0.0.0/0 из private-rt"
  aws ec2 delete-route --route-table-id "$ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 \
    || echo "Маршрута нет, продолжаем"

  echo "==> Удаляем NAT Gateway $NAT_ID"
  aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" > /dev/null

  echo "==> Ждём удаления $NAT_ID"
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"
fi

echo "==> Освобождаем Elastic IP $ALLOCATION_ID"
# Шлюз отпускает адрес не сразу после перехода в Deleted, поэтому несколько попыток.
for attempt in 1 2 3 4 5 6; do
  if aws ec2 release-address --allocation-id "$ALLOCATION_ID"; then
    rm "$STATE_FILE"
    echo "Готово. NAT Gateway удалён, Elastic IP освобождён."
    exit 0
  fi
  echo "Адрес ещё занят, попытка $attempt из 6, ждём 20 секунд"
  sleep 20
done

echo "Не удалось освободить $ALLOCATION_ID. Освободите его вручную в консоли (Elastic IPs)." >&2
exit 1
