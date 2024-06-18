#!/bin/bash

#####
# Begin Bearer Token retrival
#####

## Token Variables
url="https://smujamf.jamfcloud.com"

## Get bearer token
getPToken() {
    encodedCredentials=$(printf "$uName:$pWord" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i -)

    authToken=$(/usr/bin/curl "${url}/api/v1/auth/token" -s --request POST --header "Authorization: Basic $encodedCredentials")
    # parse authToken for token, omit expiration
    bToken=$(echo "$authToken" | plutil -extract token raw -)
    if [ -z "$bToken" ]; then
        echo "Token is invalid"
    else
        echo "Token is valid"
    fi
}

invalidateToken() {
    response_code=$(curl -silent -w "%{http_code}" -H "Authorization: Bearer ${bToken}" $url/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
    if echo "$response_code" | grep -q "204"; then
        echo "Token successfully invalidated"
    elif echo "$response_code" | grep -q "401"; then
        echo "Token already invalid"
    else
        echo "An unknown error occurred invalidating the token"
        echo "Response Code: $response_code"
    fi
}

# Call getPToken later in script after credentials are gathered!

#####
# End Bearer Token retrival
#####

# Get Jamf username and password via bash
login_creds() {
    # Define the options
    options=("Prod" "Dev")

    # Prompt the user to select an instance
    PS3="Which instance? "
    select instance in "${options[@]}"; do
        case $instance in
        "Prod")
            url="https://smujamf.jamfcloud.com"
            break
            ;;
        "Dev")
            url="https://smujamfdev.jamfcloud.com"
            break
            ;;
        *)
            echo "Invalid option, please select 1 or 2."
            ;;
        esac
    done

    # Output the selected URL
    echo "You selected: $url"
    echo "Please enter your Jamf username:"
    read uName
    echo "Please enter your Jamf password:"
    read -s pWord

    getPToken
}

login_creds

while true; do
    if [ -z "$bToken" ]; then
        echo "--Error. Please check credentials."
        login_creds
    else
        break
    fi
done

# Get the ID of the computer group from user
get_groupID() {
    echo "Please enter the Jamf ID of the computer group you want to get app usage data for:"
    read groupID
    json_data=$(curl -s -X 'GET' $url/JSSResource/computergroups/id/$groupID -H 'accept: application/json' -H "Authorization: Bearer ${bToken}")
}

get_groupID

# Check if the response contains the text "The server has not found anything matching the request URI". Then loop back to ask for the ID again.
while true; do
    if echo "$json_data" | grep -q "The server has not found anything matching the request URI"; then
        echo "No computer group found with ID $groupID. Please try again."
        get_groupID
    else
        #get the group name from the json
        group_name=$(echo "$json_data" | jq -r '.computer_group.name')
        echo "Found group with ID $groupID - $group_name"
        #echo "$json_data"
        break
    fi
done

# Get the start_date from user
echo "Please enter the start date in the format YYYY-MM-DD:"
read start_date

# Get the end_date from user
echo "Please enter the end date in the format YYYY-MM-DD:"
read end_date

date_range="${start_date}_${end_date}"

# Extract IDs and names from the JSON data
ids=$(echo "$json_data" | jq -r '.computer_group.computers[].id')
names=$(echo "$json_data" | jq -r '.computer_group.computers[].name')

echo "Found $(echo "$ids" | wc -l | xargs) computers in group $group_name"
#echo "IDs: $ids"
#echo "Names: $names"

user=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }')
userHome="/Users/$user"

# Check if a directory exists for the group name on the current users desktop folder. If not, create it.
if [ ! -d "$userHome/Desktop/AppUsage" ]; then
    mkdir "$userHome/Desktop/AppUsage"
fi
if [ -d "$userHome/Desktop/AppUsage/$group_name" ]; then
    rm -rf "$userHome/Desktop/AppUsage/$group_name"
fi

mkdir "$userHome/Desktop/AppUsage/$group_name"

output_Dir="$userHome/Desktop/AppUsage/$group_name"

# Loop through each ID
for computer in $(echo "$json_data" | jq -c '.computer_group.computers[]'); do
    # Extract ID and name for the current computer
    id=$(echo "$computer" | jq -r '.id')
    name=$(echo "$computer" | jq -r '.name')
    #echo "Getting app usage data for computer ID $id - $name"

    # Define the filename for the output CSV file based on the name field from JSON
    output_file="$output_Dir/$name.csv"

    # Execute the curl command to fetch XML data for the current ID and store it in a variable
    app_data=$(curl -s -X 'GET' $url/JSSResource/computerapplicationusage/id/$id/$date_range -H 'accept: application/json' -H "Authorization: Bearer ${bToken}")
    #echo "App usage data for computer ID $id has been fetched."
    #echo "$app_data"

    # Extract date from JSON data
    #date=$(echo "$app_data" | jq -r '.computer_application_usage[0].date')

    # Print CSV header
    echo "Date,Application,Version,Minutes Active" >"$output_file"

    # Extract data from JSON and append it to the CSV file
    echo "$app_data" | jq -r '.computer_application_usage[] | .date as $date | .apps[] | [$date, .name, .version, .foreground] | @csv' >>"$output_file"

    echo "CSV data for Jamf computer $id has been appended to '$output_file'."
done

# Define the output CSV file
output_file="$output_Dir/${group_name}_compiled.csv"

# Create the CSV file with headers
echo "Computer,Date,Minutes Active" > "$output_file"

# Loop through each CSV file in the specified directory
for csv_file in "$output_Dir"/*.csv; do
    # Get the computer name from the CSV filename
    computer=$(basename "$csv_file" .csv)

    # Skip the compiled CSV file
    if [ "$computer" = "${group_name}_compiled" ]; then
        echo "Skipping $csv_file..."
        continue
    fi
    # Skip the header row and calculate total minutes active for each date
    tail -n +2 "$csv_file" | awk -F',' -v comp="$computer" '{date[$1","comp]+=$4} END {for (d in date) print d, date[d]}' OFS=',' >> "$output_file"
done

# Sort the output file by the Date column, skipping the header row
{ head -n 1 "$output_file"; tail -n +2 "$output_file" | sort -t',' -k1,1; } > "$output_file.tmp" && mv "$output_file.tmp" "$output_file"

echo "Compilation completed. Output file: $output_file"

exit 0