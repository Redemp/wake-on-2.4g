#!/bin/bash

# Color codes for messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Deleting dongles.conf if it exists...${NC}"
rm -f /userdata/system/configs/dongles.conf && echo -e "${GREEN}✔ Removed dongles.conf${NC}"

echo -e "${YELLOW}Deleting all *.json files in /userdata/system/dongle_2_4g/dongles/...${NC}"
find /userdata/system/usb_test/dongles/ -type f -name '*.json' -exec rm -v {} \;

echo -e "${YELLOW}Deleting all 30-wake-on*.rules files in /etc/udev/rules.d/...${NC}"
find /etc/udev/rules.d/ -type f -name '30-wake-on*.rules' -exec rm -v {} \;

echo -e "${GREEN}Cleanup complete.${NC}"
