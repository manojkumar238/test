#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <json_file_1> <json_file_2> <output_json>"
    exit 1
fi

# Input files
JSON1=$1
JSON2=$2
OUTPUT_JSON=$3

# Declare associative array for rating order
declare -A rating_order=( ["A"]=1 ["B"]=2 ["C"]=3 ["D"]=4 ["E"]=5 )

# Define metrics where higher/lower is worse
WORSE_WHEN_HIGHER=("sonar-blocker-violations-actual" "sonar-critical_violations-check" "duplicated-lines-density-percent-actual" "sonar-code-smell-actual" "sonar-vulnerabilities-actual")
WORSE_WHEN_LOWER=("sonar-coverage-percent-actual" "sonar-tests-actual" "sonar-reliability-rating-actual" "sonar-maintainability-rating-actual")

# Function to determine comparison rules
is_worse_when_higher() { for metric in "${WORSE_WHEN_HIGHER[@]}"; do [[ "$1" == "$metric" ]] && return 0; done; return 1; }
is_worse_when_lower() { for metric in "${WORSE_WHEN_LOWER[@]}"; do [[ "$1" == "$metric" ]] && return 0; done; return 1; }

# Function to extract numeric values from strings like ">=30"
extract_numeric_value() {
    echo "$1" | grep -oE '[0-9]+'
}

# Function to get the worst value based on rules
get_worst_value() {
    local key="$1"
    local val1="$2"
    local val2="$3"

    # If either value is empty, keep the other
    if [[ -z "$val1" ]]; then echo "$val2"; return; fi
    if [[ -z "$val2" ]]; then echo "$val1"; return; fi

    # Extract numbers and preserve `>=` or `<=`
    num1=$(extract_numeric_value "$val1")
    num2=$(extract_numeric_value "$val2")
    op1=$(echo "$val1" | grep -oE '>=|<=')
    op2=$(echo "$val2" | grep -oE '>=|<=')

    # Compare numeric values correctly
    if [[ "$num1" =~ ^[0-9]+$ ]] && [[ "$num2" =~ ^[0-9]+$ ]]; then
        if is_worse_when_higher "$key"; then
            [[ "$num1" -gt "$num2" ]] && echo "$val1" || echo "$val2"
            return
        elif is_worse_when_lower "$key"; then
            [[ "$num1" -lt "$num2" ]] && echo "$val1" || echo "$val2"
            return
        fi
    fi

    # Handle Pass/Fail cases
    if [[ "$val1" == "Fail" || "$val2" == "Fail" ]]; then
        echo "Fail"
        return
    fi
    if [[ "$val1" == "Pass" && "$val2" == "Pass" ]]; then
        echo "Pass"
        return
    fi

    # Handle reliability rating (A/B/C/D/E)
    if [[ -n "${rating_order[$val1]}" && -n "${rating_order[$val2]}" ]]; then
        if [ "${rating_order[$val1]}" -ge "${rating_order[$val2]}" ]; then
            echo "$val1"
        else
            echo "$val2"
        fi
        return
    fi

    # Default: Keep first file's value
    echo "$val1"
}

# Read JSON files into associative arrays (handling nested keys)
declare -A json1 json2 result_json
while IFS=':' read -r key value; do
    key=$(echo "$key" | sed 's/[" ,]//g')
    value=$(echo "$value" | sed 's/[" ,]//g')
    json1["$key"]="$value"
    echo "DEBUG: File1 Key='$key' | Value='$value'"  # Debugging line
done < <(grep -oP '"[^"]+":\s*\[?.*?\]?,?' "$JSON1")

while IFS=':' read -r key value; do
    key=$(echo "$key" | sed 's/[" ,]//g')
    value=$(echo "$value" | sed 's/[" ,]//g')
    json2["$key"]="$value"
    echo "DEBUG: File2 Key='$key' | Value='$value'"  # Debugging line
done < <(grep -oP '"[^"]+":\s*\[?.*?\]?,?' "$JSON2")

# Compare values and store the worst ones
for key in "${!json1[@]}"; do
    val1="${json1[$key]}"
    val2="${json2[$key]}"
    result_json["$key"]=$(get_worst_value "$key" "$val1" "$val2")
done

# Construct final JSON output
echo "{" > "$OUTPUT_JSON"
for key in "${!result_json[@]}"; do
    echo "  \"$key\": \"${result_json[$key]}\"," >> "$OUTPUT_JSON"
done
sed -i '$ s/,$//' "$OUTPUT_JSON"  # Remove trailing comma
echo "}" >> "$OUTPUT_JSON"

echo "Comparison complete. Output saved in $OUTPUT_JSON"
