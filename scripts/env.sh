export ROOT="$(pwd)"
export SCRIPTS_DIR="$ROOT/scripts"
export CONFIG_FILE="$ROOT/config.json"


source "$SCRIPTS_DIR/utils.sh"


function install-apps() {
  helm template "$ROOT/apps" $@ \
    | kubectl apply -f -
}