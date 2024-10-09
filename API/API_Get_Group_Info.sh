#!/bin/bash

# Script to search groups on Jamf Pro API that includes a specific criteria or value
# Requires jq to parse JSON data: https://jqlang.github.io/jq/


#####
# Begin Bearer Token retrival
#####

## Token Variables
url="https://YOURINSTANCE.jamfcloud.com"

## Get bearer token
getPToken() {
    encodedCredentials=$(printf "$uName:$pWord" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i -)

    authToken=$(/usr/bin/curl "${url}/api/v1/auth/token" -s --request POST --header "Authorization: Basic $encodedCredentials")
    # parse authToken for token, omit expiration
    bTokenExtracted=$(/usr/bin/awk -F \" '{ print $4 }' <<<"$authToken" | /usr/bin/xargs)
    bToken=$(echo $bTokenExtracted | /usr/bin/awk '{print $1}')
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

########################################
# Start Print progress bar
########################################

progressStartTimeUnix=0
progressCurrTimeUnix=0

# Print a progress bar. First variable is the current count on the loop, second variable is the total number of loops, third variable is the text to display after the progress bar
printProgressBar() {
    itemsToGo=$2
    itemsTotal=$3
    if [ $progressStartTimeUnix -eq 0 ]; then
        progressStartTimeUnix=$(date +%s)
    fi
    progressCurrTimeUnix=$(date +%s)
    progressElapsedTime=$((progressCurrTimeUnix - progressStartTimeUnix))
    # if over 60 seconds, then calculate minutes
    if [ $progressElapsedTime -ge 60 ]; then
        progressElapsedTimeMinutes=$((progressElapsedTime / 60))
        progressElapsedTimeSeconds=$((progressElapsedTime % 60))
    else
        progressElapsedTimeMinutes=00
        progressElapsedTimeSeconds=$((progressElapsedTime % 60))
    fi

    # Create an estimated time to finish, based on the seconds that have elapsed divided by the current iteration, then multiplied by the total number of iterations
    if [ $2 -gt 0 ]; then
        # if $itemsToGo is the same as $itemsTotal or equal to $itemsTotal - 1, then echo No time estimated
        if [ $itemsToGo -eq $itemsTotal ] || [ $itemsToGo -eq $((itemsTotal - 1)) ]; then
            progressEstimatedTimeValue="~~:~~"
        elif [ $((itemsToGo % 5)) -eq 0 ]; then
            progressEstimatedTime=$((progressElapsedTime * $3 / $2))
            progressEstimatedTimeMinutes=$((progressEstimatedTime / 60))
            progressEstimatedTimeSeconds=$((progressEstimatedTime % 60))
            progressEstimatedTimeValue=$(printf "%02d:%02d" $progressEstimatedTimeMinutes $progressEstimatedTimeSeconds)
        #echo "Estimated time to finish: $progressEstimatedTimeValue"
        fi
    fi

    # Tell how much time is left
    if [ $itemsToGo -eq $itemsTotal ] || [ $itemsToGo -eq $((itemsTotal - 1)) ]; then
        progressTimeLeft="~~:~~"
    elif [ $((itemsToGo % 5)) -eq 0 ]; then
        progressTimeLeft=$((progressEstimatedTime - progressElapsedTime))
        progressTimeLeftMinutes=$((progressTimeLeft / 60))
        progressTimeLeftSeconds=$((progressTimeLeft % 60))
        progressTimeLeft=$(printf "%02d:%02d" $progressTimeLeftMinutes $progressTimeLeftSeconds)
    fi
    #echo "Time left: $progressTimeLeft"

    # The time should always be formatted as 2 digits. So 2 digits for minutes, and 2 digits for seconds. ie. 1 minute and 1 second should be 01:01
    progressElapsedTime=$(printf "%02d:%02d" $progressElapsedTimeMinutes $progressElapsedTimeSeconds)
    #echo "Elapsed time: $progressElapsedTime"
    timeText="⏱ $progressElapsedTime/$progressTimeLeft"

    # Save the curser position
    echo -en "\033[s"

    # Move to a fixed position
    #tput cuu1  # Move up one line
    #tput cuf $(tput cols)  # Move to the end of the line
    echo -ne "\r"
    height=$(tput lines)
    eraseHeight=$((height - 10))

    for ((i = 1; i <= eraseHeight; i++)); do
        echo -en "\r"
        #printf "\033[K"    # delete till end of line
        echo -en "\033[1B" # move down one line
    done
    echo -en "\033[u" # restore cursor position
    echo -en "\r"

    # Define ANSI color escape sequences
    green='\033[0;32m'
    blue='\033[0;36m'
    reset='\033[0m' # Reset text formatting

    cols=$(tput cols)
    progText=$1
    progTextLength=${#progText}
    maxAllowedProgTextLength=$((cols - 20))
    if [ $progTextLength -gt $maxAllowedProgTextLength ]; then
        progText=""
        progTextLength=0
    fi
    if [ -z "$percent" ]; then
        rotateIter=1
    else
        rotateIter=$((rotateIter + 1))
    fi
    if [ $rotateIter -gt 6 ]; then
        rotateIter=1
    fi
    case $rotateIter in
    1)
        rotateChar="⠶"
        ;;
    2)
        rotateChar="⠧"
        ;;
    3)
        rotateChar="⠏"
        ;;
    4)
        rotateChar="⠛"
        ;;
    5)
        rotateChar="⠹"
        ;;
    6)
        rotateChar="⠼"
        ;;
    esac

    percent=$(($2 * 100 / $3))
    if [ $percent -eq 100 ]; then
        rotateChar="๏"
    fi
    numChars=$((width * percent / 100))
    # percent text will be 3 characters long always, using printf to pad with spaces if needed
    percText=$(printf "%3d" $percent)

    if [ $percent -lt 100 ]; then
        timeText="⏱ $progressElapsedTime/$progressTimeLeft"
    else
        timeText="⏱ $progressElapsedTime"
    fi

    local progressBar="$2/$3 | $timeText | $percText% $rotateChar "
    percLength=${#progressBar}
    width=$((cols - progTextLength - percLength - 6))

    for ((i = 0; i < width; i++)); do
        if ((i < numChars)); then
            progressBar+="${blue}▰${reset}"
        else
            progressBar+="▱"
        fi
    done

    # If it's not complete, then just add a carriage return
    if [ $progTextLength -eq 0 ]; then
        if [ $percent -lt 100 ]; then
            echo -ne "[ $progressBar]\r"
            echo -en "\033[u" # restore cursor position
        else
            echo -ne "[ $progressBar]\n"
        fi
    else
        if [ $percent -lt 100 ]; then
            echo -ne "[ $progText | $progressBar]\r"
            echo -en "\033[u" # restore cursor position

        else
            echo -en "\033[u" # restore cursor position
            printf "\033[K"   # delete till end of line
            echo -ne "[ $progText | $2/$3 | ${green}$timeText${reset} | ${green}100% ๏ Complete${reset} ]\n"
            progressStartTimeUnix=0
        fi
    fi

}

########################################
# End Print progress bar
########################################

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

searchChoices=("Criteria" "Value" "Exit")

PS3="What do you want to search for in Smart Groups?: "
select searchChoice in "${searchChoices[@]}"; do
    case $searchChoice in
    "Criteria")
        searchChoice="Criteria"
        break
        ;;
    "Value")
        searchChoice="Value"
        break
        ;;
    "Exit")
        echo "Exiting"
        exit 0
        ;;
    *)
        echo "Invalid option, please select 1, 2, or 3."
        ;;
    esac
done

searchTerm="Asset Tag"
echo "What wording do you want to search for in $searchChoice?: "
read searchTerm

allGroups=$(curl -s -X 'GET' $url/JSSResource/computergroups -H 'accept: application/json' -H "Authorization: Bearer ${bToken}")
# echo "allGroups: $allGroups"
# Get the total number of policies
totalGroups=$(echo "$allGroups" | jq -r '.computer_groups | length')
processedGroups=0
totalInvolvedGroups=0
involvedGroups=""

echo ""
echo "Searching in Smart Groups->$searchChoice for: $searchTerm"
# Loop through the "id" values
for id in $(echo "$allGroups" | jq -r '.computer_groups[].id'); do
    groupJson=$(curl -s -X 'GET' $url/JSSResource/computergroups/id/$id -H 'accept: application/json' -H "Authorization: Bearer ${bToken}")
    # Get name of policy from groupJson
    groupName=$(echo "$groupJson" | jq -r '.computer_group.name')
    groupSmart=$(echo "$groupJson" | jq -r '.computer_group.is_smart')
    if [[ $groupSmart == "false" ]]; then
        processedGroups=$((processedGroups + 1))
        printProgressBar "$totalInvolvedGroups found" $processedGroups $totalGroups

        continue
    fi
    #echo "group: $id - $groupName"
    # Get number of criteria in policy
    criteriaCount=$(echo "$groupJson" | jq -r '.computer_group.criteria | length')
    shopt -s nocasematch
    for ((i = 0; i < $criteriaCount; i++)); do
        criteriaName=$(echo "$groupJson" | jq -r ".computer_group.criteria[$i].name")
        criteriaValue=$(echo "$groupJson" | jq -r ".computer_group.criteria[$i].value")
        criteriaSearchType=$(echo "$groupJson" | jq -r ".computer_group.criteria[$i].search_type")
        if [[ $searchChoice == *"Criteria"* ]]; then
            if [[ $criteriaName == *"$searchTerm"* ]]; then
                if [[ $involvedGroups != *"$id - $groupName"* ]]; then
                    totalInvolvedGroups=$((totalInvolvedGroups + 1))
                    involvedGroups+="\n$id - $groupName - $url/smartComputerGroups.html?id=$id&o=r\n"
                fi
                involvedGroups+="    ↳ $criteriaName $criteriaSearchType $criteriaValue\n"
            fi
        fi
        if [[ $searchChoice == *"Value"* ]]; then
            if [[ $criteriaValue == *"$searchTerm"* ]]; then
                if [[ $involvedGroups != *"$id - $groupName"* ]]; then
                    totalInvolvedGroups=$((totalInvolvedGroups + 1))
                    involvedGroups+="\n$id - $groupName - $url/smartComputerGroups.html?id=$id&o=r\n"
                fi
                involvedGroups+="    ↳ $criteriaName $criteriaSearchType $criteriaValue\n"
            fi
        fi
    done
    # reenable case matching
    shopt -u nocasematch

    processedGroups=$((processedGroups + 1))
    #remainingGroups=$((totalGroups - processedGroups))
    #percentageCompleted=$((processedGroups * 100 / totalGroups))
    printProgressBar "$totalInvolvedGroups found" $processedGroups $totalGroups
done
echo ""

if [[ "$totalInvolvedGroups" -le 0 ]]; then
    echo "No groups found containing $searchTerm"
    exit 0
fi
echo "Involved Policies: $totalInvolvedGroups"
echo -e $involvedGroups

invalidateToken
exit 0
