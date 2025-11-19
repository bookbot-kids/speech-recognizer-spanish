#!/bin/bash

# Build Documentation Script
# This script generates Flutter API documentation and builds the MkDocs site

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Documentation Build Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Step 1: Generate Flutter API Documentation
echo -e "${YELLOW}Step 1: Generating Flutter API documentation...${NC}"
dart doc speech_recognizer --output speech_recognizer/doc/api

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Flutter documentation generated successfully${NC}"
else
    echo -e "${RED}✗ Failed to generate Flutter documentation${NC}"
    exit 1
fi
echo ""

# Step 2: Copy documentation to docs directory
echo -e "${YELLOW}Step 2: Copying documentation to docs directory...${NC}"
rm -rf docs/speech_recognizer/doc/api
mkdir -p docs/speech_recognizer/doc
cp -r speech_recognizer/doc/api docs/speech_recognizer/doc/

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Documentation copied successfully${NC}"
else
    echo -e "${RED}✗ Failed to copy documentation${NC}"
    exit 1
fi
echo ""

# Step 3: Build MkDocs site
echo -e "${YELLOW}Step 3: Building MkDocs site...${NC}"
mkdocs build

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ MkDocs site built successfully${NC}"
else
    echo -e "${RED}✗ Failed to build MkDocs site${NC}"
    exit 1
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ All documentation generated successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Documentation locations:"
echo -e "  - Flutter API: ${YELLOW}speech_recognizer/doc/api/${NC}"
echo -e "  - MkDocs source: ${YELLOW}docs/speech_recognizer/doc/api/${NC}"
echo -e "  - Built site: ${YELLOW}site/${NC}"
echo ""
echo -e "Next steps:"
echo -e "  - Preview: ${YELLOW}mkdocs serve${NC}"
echo -e "  - Deploy: ${YELLOW}mkdocs gh-deploy${NC}"
echo ""

