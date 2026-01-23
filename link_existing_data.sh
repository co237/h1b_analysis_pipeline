#!/bin/bash
# Script to create symbolic links to existing data files
# This avoids duplicating large data files

# =============================================================================
# CONFIGURATION: Update these paths to match your existing data locations
# =============================================================================

# Where your existing data is currently located
EXISTING_DATA="$HOME/Documents/Github/h1b-npv-wage-ranking-simulations/Data"

# Where the new pipeline expects data
PIPELINE_DATA="$HOME/Documents/GitHub/h1b_analysis_pipeline/data/raw"

# =============================================================================
# Create symbolic links
# =============================================================================

echo "Creating symbolic links to existing data files..."
echo ""

# Change to pipeline data directory
cd "$PIPELINE_DATA" || exit 1

# Link FOIA files (if they exist in your old location)
echo "Linking H-1B FOIA files..."
if [ -d "$EXISTING_DATA/FOIA Data" ]; then
    ln -sf "$EXISTING_DATA/FOIA Data"/TRK_13139_FY*.csv . 2>/dev/null
    echo "  ✓ FOIA files linked"
else
    echo "  ⚠ FOIA Data directory not found at: $EXISTING_DATA/FOIA Data"
fi

# Link LCA Data directory
echo "Linking LCA data..."
if [ -d "$EXISTING_DATA/LCA Data" ]; then
    # Remove the empty directory first
    rmdir LCA_Data 2>/dev/null
    # Create symlink to entire directory
    ln -sf "$EXISTING_DATA/LCA Data" LCA_Data
    echo "  ✓ LCA Data directory linked"
else
    echo "  ⚠ LCA Data directory not found at: $EXISTING_DATA/LCA Data"
fi

# Link crosswalk files from "Other Data" directory
echo "Linking geographic and occupation crosswalk files..."
if [ -d "$EXISTING_DATA/Other Data" ]; then
    ln -sf "$EXISTING_DATA/Other Data/soc_2018_definitions.xlsx" . 2>/dev/null
    ln -sf "$EXISTING_DATA/Other Data/ZIP_COUNTY_122024.xlsx" . 2>/dev/null
    ln -sf "$EXISTING_DATA/Other Data/ZIP_CBSA_122024.xlsx" . 2>/dev/null
    ln -sf "$EXISTING_DATA/Other Data/area_definitions_m2023.xlsx" . 2>/dev/null
    ln -sf "$EXISTING_DATA/Other Data/soc_2010_to_2018_crosswalk.xlsx" . 2>/dev/null
    ln -sf "$EXISTING_DATA/Other Data/DOT_to_ONET_SOC.xlsx" . 2>/dev/null
    echo "  ✓ Crosswalk files linked"
else
    echo "  ⚠ Other Data directory not found at: $EXISTING_DATA/Other Data"
fi

# Link OFLC wage data directory
echo "Linking OFLC wage data..."
if [ -d "$EXISTING_DATA/Other Data/OFLC_Wages_2024-25" ]; then
    # Remove the empty directory first
    rmdir OFLC_Wages_2024-25 2>/dev/null
    # Create symlink to entire directory
    ln -sf "$EXISTING_DATA/Other Data/OFLC_Wages_2024-25" OFLC_Wages_2024-25
    echo "  ✓ OFLC wage data directory linked"
else
    echo "  ⚠ OFLC_Wages_2024-25 directory not found at: $EXISTING_DATA/Other Data/OFLC_Wages_2024-25"
fi

# Link ACS IPUMS files (adjust filename as needed)
echo "Linking ACS IPUMS files..."
if [ -f "$EXISTING_DATA/usa_00061.xml" ]; then
    ln -sf "$EXISTING_DATA/usa_00061.xml" .
    echo "  ✓ ACS DDI file linked"
else
    echo "  ⚠ ACS DDI file not found (you may need to update the filename)"
fi

if [ -f "$EXISTING_DATA/usa_00061.dat.gz" ]; then
    ln -sf "$EXISTING_DATA/usa_00061.dat.gz" .
    echo "  ✓ ACS data file linked"
else
    echo "  ⚠ ACS data file not found (you may need to update the filename)"
fi

echo ""
echo "==================================================================="
echo "Symbolic links created!"
echo "==================================================================="
echo ""
echo "Your pipeline will now use the existing data files without"
echo "duplicating them. Your original workflow is not affected."
echo ""
echo "To verify the links, run:"
echo "  ls -la $PIPELINE_DATA"
echo ""
