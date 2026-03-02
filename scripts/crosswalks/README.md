# Crosswalk Creation Scripts

This directory contains scripts that were used to create occupation code crosswalks.

## Files

- **create_fy2021_to_acs_crosswalk.R**: Creates two-stage SOC 2010 → SOC 2018 → ACS 2018 crosswalk
- **create_oflc_acs_crosswalk_fy2021.R**: Alternative approach to FY2021-2022 crosswalk creation
- **create_oflc_acs_crosswalk.R**: Creates SOC 2018 → ACS 2018 crosswalk
- **create_soc2010_to_soc2018_crosswalk.R**: Processes BLS SOC vintage crosswalk

These scripts were used to generate the crosswalk files in `data/raw/` and are not part of the main pipeline. The crosswalk files they generated are already included in the data directory.

## Note

If you need to regenerate crosswalks (e.g., for updated SOC vintages or ACS occupation codes), these scripts provide a starting point. However, the current pipeline uses the pre-generated crosswalk files and does not require running these scripts.
