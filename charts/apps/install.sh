set -euo pipefail

find . -name "values.yaml" -type f -print0 | while IFS= read -r -d '' values_file; do
  location=$(dirname "$values_file")
  name=$(basename "$location")
  name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -s '[:punct:][:space:]' '-' | sed -e 's/^-*//' -e 's/-*$//')

  echo "✅ Chart found in: $location"
  echo "   - Generated release name: $name"
  HELM_COMMAND="helm install --namespace prod \"$name\" \"$location\""
  helm upgrade -i --namespace prod "$name" "$location"
done
