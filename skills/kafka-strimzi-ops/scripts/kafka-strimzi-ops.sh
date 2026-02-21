#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="streaming"
TOPIC=""
PARTITIONS=3
REPLICAS=1
YES=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") <command> [options]

Commands:
  status               Show Strimzi/Kafka resource health
  topics               List KafkaTopic resources
  users                List KafkaUser resources
  describe-topic       Describe one KafkaTopic (--topic)
  create-topic         Create KafkaTopic (--topic, optional --partitions/--replicas, requires --yes)
  delete-topic         Delete KafkaTopic (--topic, requires --yes)

Options:
  -n, --namespace <ns> Namespace (default: streaming)
  -t, --topic <name>   Topic name for topic actions
  --partitions <n>     Partitions for create-topic (default: 3)
  --replicas <n>       Replicas for create-topic (default: 1)
  --yes                Required for mutating commands
  -h, --help           Show help
USAGE
}

need_topic() {
  [[ -n "$TOPIC" ]] || { echo "--topic is required" >&2; exit 1; }
}

need_yes() {
  if [[ "$YES" -ne 1 ]]; then
    echo "Mutating command requires --yes" >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      -t|--topic)
        TOPIC="$2"
        shift 2
        ;;
      --partitions)
        PARTITIONS="$2"
        shift 2
        ;;
      --replicas)
        REPLICAS="$2"
        shift 2
        ;;
      --yes)
        YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done
}

require_kube_api() {
  local context server err

  if kubectl get namespaces --request-timeout=7s >/dev/null 2>&1; then
    return 0
  fi

  context="$(kubectl config current-context 2>/dev/null || echo "<none>")"
  server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "<unknown>")"
  err="$(kubectl get namespaces --request-timeout=7s 2>&1 || true)"
  err="$(printf '%s\n' "$err" | grep -v 'memcache.go:' | tail -n 1 | sed 's/[[:space:]]\+/ /g')"

  cat >&2 <<EOF
Kubernetes API preflight failed.
Context: $context
Server: $server
Error: ${err:-unable to reach API}
Fix: start/select a reachable cluster, then retry.
EOF
  exit 2
}

cmd_status() {
  echo "== Strimzi operator pods =="
  kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=strimzi-cluster-operator -o wide || true
  echo
  echo "== Kafka clusters =="
  kubectl -n "$NAMESPACE" get kafkas.kafka.strimzi.io -o wide || true
  echo
  echo "== KafkaTopic count =="
  kubectl -n "$NAMESPACE" get kafkatopics.kafka.strimzi.io --no-headers 2>/dev/null | wc -l | awk '{print $1}'
  echo "== KafkaUser count =="
  kubectl -n "$NAMESPACE" get kafkausers.kafka.strimzi.io --no-headers 2>/dev/null | wc -l | awk '{print $1}'
  echo
  echo "== Kafka broker pods =="
  kubectl -n "$NAMESPACE" get pods -l strimzi.io/name -o wide | grep kafka || true
}

cmd_topics() {
  kubectl -n "$NAMESPACE" get kafkatopics.kafka.strimzi.io -o wide
}

cmd_users() {
  kubectl -n "$NAMESPACE" get kafkausers.kafka.strimzi.io -o wide
}

cmd_describe_topic() {
  need_topic
  kubectl -n "$NAMESPACE" get kafkatopic "$TOPIC" -o yaml
}

cmd_create_topic() {
  need_topic
  need_yes
  kubectl -n "$NAMESPACE" apply -f - <<YAML
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: ${TOPIC}
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  partitions: ${PARTITIONS}
  replicas: ${REPLICAS}
YAML
}

cmd_delete_topic() {
  need_topic
  need_yes
  kubectl -n "$NAMESPACE" delete kafkatopic "$TOPIC"
}

main() {
  command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

  local command="${1:-}"
  [[ -n "$command" ]] || { usage; exit 1; }
  shift

  case "$command" in
    status|topics|users|describe-topic|create-topic|delete-topic)
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown command: $command" >&2
      usage
      exit 1
      ;;
  esac

  parse_args "$@"
  require_kube_api

  case "$command" in
    status) cmd_status ;;
    topics) cmd_topics ;;
    users) cmd_users ;;
    describe-topic) cmd_describe_topic ;;
    create-topic) cmd_create_topic ;;
    delete-topic) cmd_delete_topic ;;
  esac
}

main "$@"
