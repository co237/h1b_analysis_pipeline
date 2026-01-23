# Using Your Existing Data Files

You don't need to move or duplicate your data files! Here are two ways to use existing data without disrupting your current workflow.

## Option 1: Symbolic Links (Recommended) ⭐

**Advantages:**
- ✓ No duplicate files (saves disk space)
- ✓ Original files stay in place
- ✓ Both workflows use the same data
- ✓ Updates to data in one location reflect everywhere

**How to do it:**

1. Edit `link_existing_data.sh` and update this line to point to your data:
   ```bash
   EXISTING_DATA="$HOME/Documents/Github/h1b-npv-wage-ranking-simulations/Data"
   ```

2. Run the script:
   ```bash
   cd ~/Documents/GitHub/h1b_analysis_pipeline
   ./link_existing_data.sh
   ```

3. The script will create symbolic links (shortcuts) to your existing files

**What it looks like:**
```
data/raw/
├── TRK_13139_FY2021.csv -> ~/Documents/.../FOIA Data/TRK_13139_FY2021.csv
├── LCA_Data -> ~/Documents/.../LCA Data
└── soc_2018_definitions.xlsx -> ~/Documents/.../Other Data/soc_2018_definitions.xlsx
```

The `->` means these are links to your original files, not copies.

---

## Option 2: Copy Files (Simple but uses more space)

**Advantages:**
- ✓ Simple to understand
- ✓ Completely independent datasets

**Disadvantages:**
- ✗ Uses extra disk space (data files can be large)
- ✗ Updates don't sync between locations

**How to do it:**

```bash
# Set your paths
OLD_DATA="$HOME/Documents/Github/h1b-npv-wage-ranking-simulations/Data"
NEW_DATA="$HOME/Documents/GitHub/h1b_analysis_pipeline/data/raw"

# Copy FOIA files
cp "$OLD_DATA/FOIA Data"/TRK_13139_FY*.csv "$NEW_DATA/"

# Copy LCA files
cp -r "$OLD_DATA/LCA Data"/* "$NEW_DATA/LCA_Data/"

# Copy Other Data files
cp "$OLD_DATA/Other Data/soc_2018_definitions.xlsx" "$NEW_DATA/"
cp "$OLD_DATA/Other Data/ZIP_COUNTY_122024.xlsx" "$NEW_DATA/"
cp "$OLD_DATA/Other Data/ZIP_CBSA_122024.xlsx" "$NEW_DATA/"
cp "$OLD_DATA/Other Data/area_definitions_m2023.xlsx" "$NEW_DATA/"
cp "$OLD_DATA/Other Data/soc_2010_to_2018_crosswalk.xlsx" "$NEW_DATA/"
cp "$OLD_DATA/Other Data/DOT_to_ONET_SOC.xlsx" "$NEW_DATA/"

# Copy OFLC wage data
cp -r "$OLD_DATA/Other Data/OFLC_Wages_2024-25" "$NEW_DATA/"

# Copy ACS IPUMS files (adjust filenames if needed)
cp "$OLD_DATA"/usa_*.xml "$NEW_DATA/"
cp "$OLD_DATA"/usa_*.dat.gz "$NEW_DATA/"
```

---

## Option 3: Update config.R to Use Existing Locations

You can also just change the paths in `config.R` to point to your existing data:

```r
# Edit config.R
data_raw <- "~/Documents/Github/h1b-npv-wage-ranking-simulations/Data"
lca_data_path <- file.path(data_raw, "LCA Data")
# ... etc
```

**Advantages:**
- ✓ No copying or linking needed
- ✓ Uses existing data directly

**Disadvantages:**
- ✗ Mixes old and new workflows
- ✗ Less portable (hardcoded paths)

---

## Recommendation

**Use Option 1 (Symbolic Links)** because:
1. Your large data files (especially ACS and LCA) won't be duplicated
2. Both your old and new workflows can work simultaneously
3. Any data updates benefit both projects
4. Easy to set up with the provided script

## Verifying Links

After creating symlinks, check they work:

```bash
cd ~/Documents/GitHub/h1b_analysis_pipeline/data/raw
ls -lh  # Shows file sizes and link targets

# Check a specific link
file TRK_13139_FY2021.csv
# Should say: "symbolic link to ..."
```

## Troubleshooting

**"File not found" errors:**
- Check that paths in `link_existing_data.sh` match your actual data locations
- Use absolute paths (starting with `/` or `~`)

**"Operation not permitted":**
- Make sure you have read access to the original files
- Try copying instead if symlinks don't work

**Want to undo symlinks?**
```bash
cd ~/Documents/GitHub/h1b_analysis_pipeline/data/raw
rm TRK_13139_FY*.csv  # Removes links, not original files
rm LCA_Data  # Removes link to directory, not the directory itself
```

Don't worry - removing symlinks doesn't delete the original files!
