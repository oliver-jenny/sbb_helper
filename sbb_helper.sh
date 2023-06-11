#!/bin/bash

# Define color codes
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get user's geolocation based on IP
geo_location=$(curl -s ip-api.com/json/?fields=lat,lon | jq -r '"\(.lat),\(.lon)"')

if [[ -z "$geo_location" ]]; then
  echo -e "${RED}Failed to retrieve geolocation.${NC}"
  exit 1
fi

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  -d | --destination)
    destination="$2"
    shift
    shift
    ;;
  -t | --time)
    time="$2"
    shift
    shift
    ;;
  *)
    echo "Invalid argument: $1"
    exit 1
    ;;
  esac
done

# Check if required arguments are provided
if [[ -z "$destination" ]] || [[ -z "$time" ]]; then
  echo -e "${RED}Missing arguments. Usage: $0 -d|--destination <destination> -t|--time <time>${NC}"
  exit 1
fi

echo -e "${YELLOW}Looking for connections - specific destinations might take a few seconds${NC}"

# Encode the destination for URL using Python
encoded_destination=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$destination', safe=''))")

# Get connections to the specified destination closest to the specified time
current_time=$(date +%H:%M)

connections=$(curl -s "https://transport.opendata.ch/v1/connections?from=$geo_location&to=$encoded_destination&limit=10&time=$time")

# Process the connections data
echo -e "${CYAN}Connections to $destination closest to $time:${NC}"
echo

# Extract relevant information from the connections JSON
connection_count=$(echo "$connections" | jq '.connections | length')

if [[ "$connection_count" -eq 0 ]]; then
  echo -e "${YELLOW}No connections found.${NC}"
else
  # Function to display a connection
  displayConnection() {
    connection=$(echo "$connections" | jq -r ".connections[$1]")
    transfer_count=$(echo "$connection" | jq '.sections | length')

    echo -e "${GREEN}Connection${NC}"
    echo -e "├ ${YELLOW}From:${NC} $(echo "$connection" | jq -r ".from.station.name")"
    echo -e "├ ${YELLOW}To:${NC} $(echo "$connection" | jq -r ".to.station.name")"
    echo -e "├ ${YELLOW}Departure:${NC} $(date -d "$(echo "$connection" | jq -r ".from.departure")" +%H:%M)"
    echo -e "├ ${YELLOW}Arrival:${NC} $(date -d "$(echo "$connection" | jq -r ".to.arrival")" +%H:%M)"
    echo -e "├ ${YELLOW}Transfers:${NC} $transfer_count"

    # Iterate over the transfers
    for ((i = 0; i < $transfer_count; i++)); do
      transfer=$(echo "$connection" | jq -r ".sections[$i]")

      transfer_mode=$(echo "$transfer" | jq -r ".journey.category")
      transfer_number=$(echo "$transfer" | jq -r ".journey.number")
      transfer_departure=$(echo "$transfer" | jq -r ".departure.departure")
      transfer_arrival=$(echo "$transfer" | jq -r ".arrival.arrival")
      transfer_duration=$(echo "$transfer" | jq -r ".duration")
      transfer_platform=$(echo "$transfer" | jq -r ".departure.platform")
      transfer_walk_duration=$(echo "$transfer" | jq -r ".walk")
      transfer_walk_distance=$(echo "$transfer" | jq -r ".walk.distance")

      echo -e "│├ ${BLUE}Transfer $(($i + 1)):${NC}"

      if [[ "$transfer_walk_duration" != null ]]; then
        # If the transfer involves walking
        echo -e "││├ ${YELLOW}Walk${NC}"
        echo -e "││├ ${YELLOW}From:${NC} $(echo "$transfer" | jq -r ".departure.station.name")"
        echo -e "││├ ${YELLOW}To:${NC} $(echo "$transfer" | jq -r ".arrival.station.name")"
        if [[ "$transfer_walk_distance" != null ]]; then
          echo -e "││└ ${YELLOW}Distance:${NC} $transfer_walk_distance meters"
        else
          echo -e "││└ ${YELLOW}Distance: ${RED}Could not be estimated${NC}"
        fi
      elif [[ "$transfer_walk_duration" == null && "$transfer_mode" != null ]]; then
        # If the transfer involves public transport
        echo -e "││├ ${YELLOW}$transfer_mode$transfer_number${NC}"
        echo -e "││├ ${YELLOW}From:${NC} $(echo "$transfer" | jq -r ".departure.station.name")"
        echo -e "││├ ${YELLOW}To:${NC} $(echo "$transfer" | jq -r ".arrival.station.name")"
        echo -e "││├ ${YELLOW}Departure:${NC} $(date -d "$transfer_departure" +%H:%M)"
        echo -e "││├ ${YELLOW}Arrival:${NC} $(date -d "$transfer_arrival" +%H:%M)"
        if [[ "$transfer_platform" != null ]]; then
          echo -e "││└ ${YELLOW}Platform:${NC} $transfer_platform"
        else
          echo -e "││└ ${YELLOW}Platform: ${RED}Could not be estimated${NC}"
        fi
      fi
    done
    echo
  }

  # Prompt the user for options
  declare -i currPage=0
  displayConnection $currPage # initially load first connection
  while true; do
    echo -e "Enter an option: (${GREEN}next${NC} or ${GREEN}>${NC}) Load next connection, (${GREEN}previous${NC} or ${GREEN}<${NC}) Load previous connection, (${RED}exit${NC} or ${RED}/${NC}) Exit the program"
    read -r option

    case $option in
    next | \>)
      if [[ $currPage < 9 ]]; then
        currPage=$((currPage + 1))
        displayConnection $currPage
      else
        echo -e "${RED}Already on last page. If you want a later connection, you will have to update your specified time.${NC}"
      fi
      ;;
    previous | \<)
      if [[ $currPage > 0 ]]; then
        currPage=$((currPage - 1))
        displayConnection $currPage
      else
        echo -e "${RED}Already on first page. If you want an earlier connection, you will have to update your specified time.${NC}"
      fi
      ;;
    exit | \/)
      echo "Exiting the program."
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid option.${NC}"
      ;;
    esac
  done
fi
