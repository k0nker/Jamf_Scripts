#!/bin/bash

#####
# API_Get_Policy_Info.sh
#
# This script will search through all policies and find any that contain a specific script, package, or process.
# Useful if you need to make a change but don't want to hunt through every policy to see which ones call to the
# script, package, or process you need to change.
#
# - k0nker@SMU
#####

#####
# Begin Bearer Token retrival
#####

## Token Variables

## Get bearer token
getPToken() {
    encodedCredentials=$(printf "$uName:$pWord" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i -)

    authToken=$(/usr/bin/curl "${url}/uapi/auth/tokens" -s --request POST --header "Authorization: Basic $encodedCredentials")
    # parse authToken for token, omit expiration
    bToken=$(/usr/bin/awk -F \" '{ print $4 }' <<<"$authToken" | /usr/bin/xargs)
    if [ -z "$bToken" ]; then
        echo "Token is blank"
    else
        echo "Token is not blank"
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
            url="https://yourprodserver.jamfcloud.com"
            break
            ;;
        "Dev")
            url="https://yourdevserver.jamfcloud.com"
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

# Print a progress bar. First variable is the current count on the loop, second variable is the total number of loops, third variable is the text to display after the progress bar
printProgressBar() {
    local width=40 # Width of the progress bar in characters
    local percent=$(($1 * 100 / $2))
    local numChars=$((width * percent / 100))
    local progressBar="["
    for ((i = 0; i < width; i++)); do
        if ((i < numChars)); then
            progressBar+="="
        else
            progressBar+=" "
        fi
    done
    progressBar+="] $percent%"
    printf "\033[K" # delete till end of line
    # If it's not complete, then just add a carriage return
    if [ $percent -lt 100 ]; then
        echo -ne "$progressBar | $3\r"
    else
        echo "$progressBar | $3"
    fi
}
searchSection="Scripts"
searchTerm="Account"

PS3="Where do you want to search?: "
options=("Packages" "Scripts" "Processes" "Quit")

select opt in "${options[@]}"; do
    case $REPLY in
    1)
        searchSection="Packages"
        break
        ;;
    2)
        searchSection="Scripts"
        break
        ;;
    3)
        searchSection="Processes"
        break
        ;;
    4)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid option. Please select a valid number."
        ;;
    esac
done

echo "What do you want to search for in Policy->$searchSection?: "
read searchTerm

allPolicies=$(curl -s -X 'GET' $url/JSSResource/policies -H 'accept: application/json' -H "Authorization: Bearer ${bToken}")

# Get the total number of policies
totalPolicies=$(echo "$allPolicies" | jq -r '.policies | length')
processedPolicies=0
totalInvolvedPolicies=0
involvedPolicies=""

echo ""
echo "Searching in Policy->$searchSection for: $searchTerm"
# Loop through the "id" values
for id in $(echo "$allPolicies" | jq -r '.policies[].id'); do
    policyJson=$(curl -s -X 'GET' $url/JSSResource/policies/id/$id -H 'accept: application/json' -H "Authorization: Bearer ${bToken}")
    # Get name of policy from policyJson
    policyName=$(echo "$policyJson" | jq -r '.policy.general.name')
    # echo "Policy: $id - $policyName"
    # if searchterm is Scripts then search for scripts
    if [[ $searchSection == *"Scripts"* ]]; then
        # Get number of scripts in policy
        scriptCount=$(echo "$policyJson" | jq -r '.policy.scripts | length')
        # echo "Script Count: $scriptCount"
        # get script names and ignore case
        shopt -s nocasematch
        for ((i = 0; i < $scriptCount; i++)); do
            scriptName=$(echo "$policyJson" | jq -r ".policy.scripts[$i].name")
            #echo "Script: $scriptName"
            # If scriptName contains searchTerm then add the name of the policy to the involvedPolicies
            if [[ $scriptName == *"$searchTerm"* ]]; then
                if [[ $involvedPolicies != *"$id - $policyName"* ]]; then
                    totalInvolvedPolicies=$((totalInvolvedPolicies + 1))
                    involvedPolicies+="\n$id - $policyName\n"
                fi
                involvedPolicies+="    ↳ $scriptName\n"
            fi
        done
        # reenable case matching
        shopt -u nocasematch

    elif [[ $searchSection == *"Packages"* ]]; then
        # Get number of packages in policy
        packageCount=$(echo "$policyJson" | jq -r '.policy.package_configuration.packages | length')
        #echo "Package Count: $packageCount"
        # get package names and ignore case
        shopt -s nocasematch
        for ((i = 0; i < $packageCount; i++)); do
            packageName=$(echo "$policyJson" | jq -r ".policy.package_configuration.packages.[$i].name")
            #echo "Package: $packageName"
            # If packageName contains searchTerm then add the name of the policy to the involvedPolicies
            if [[ $packageName == *"$searchTerm"* ]]; then
                if [[ $involvedPolicies != *"$id - $policyName"* ]]; then
                    totalInvolvedPolicies=$((totalInvolvedPolicies + 1))
                    involvedPolicies+="\n$id - $policyName\n"
                fi
                involvedPolicies+="    ↳ $packageName\n"
            fi
        done
        # reenable case matching
        shopt -u nocasematch
    elif [[ $searchSection == *"Processes"* ]]; then
        # get process command and ignore case
        shopt -s nocasematch
        processCommand=$(echo "$policyJson" | jq -r ".policy.files_processes.run_command")
        #echo "Process: $processCommand"
        # If processCommand contains searchTerm then add the name of the policy to the involvedPolicies
        if [[ $processCommand == *"$searchTerm"* ]]; then
            if [[ $involvedPolicies != *"$id - $policyName"* ]]; then
                totalInvolvedPolicies=$((totalInvolvedPolicies + 1))
                involvedPolicies+="\n$id - $policyName\n"
            fi
            involvedPolicies+="    ↳ $processCommand\n"
        fi
        # reenable case matching
        shopt -u nocasematch
    fi

    processedPolicies=$((processedPolicies + 1))
    remainingPolicies=$((totalPolicies - processedPolicies))
    percentageCompleted=$((processedPolicies * 100 / totalPolicies))
    printProgressBar $processedPolicies $totalPolicies "$processedPolicies/$totalPolicies processed | $totalInvolvedPolicies found."
done
echo ""
echo "Involved Policies: $totalInvolvedPolicies"
echo -e $involvedPolicies

invalidateToken
exit 0
