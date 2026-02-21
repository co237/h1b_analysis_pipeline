# Sharing the H-1B Analysis Pipeline

Instructions for sharing this project with collaborators.

## Google Drive Folder Sharing

### Current Status
✅ Google Drive folder created: `h1b_analysis_pipeline_data` (~8.2 GB)
✅ All large data files copied to Google Drive
✅ README files added to each subfolder

### Location
**Your local path**:
`~/Library/CloudStorage/GoogleDrive-connor@ifp.org/My Drive/h1b_analysis_pipeline_data/`

**In Google Drive web**:
1. Go to https://drive.google.com
2. Navigate to "My Drive"
3. Find folder: `h1b_analysis_pipeline_data`

---

## How to Share with Collaborators

### Option 1: Individual Access (Recommended for Close Collaborators)

1. **Open Google Drive** (web interface)
2. **Navigate to**: My Drive > `h1b_analysis_pipeline_data`
3. **Right-click** on the folder → Select "Share"
4. **Add collaborators**:
   - Enter their email addresses
   - Set permission level:
     - **Viewer**: Can view and download (recommended for most)
     - **Commenter**: Can view and comment
     - **Editor**: Can edit files (only if needed)
5. **Optional**: Uncheck "Notify people" if you want to send a custom message
6. Click **Send**

### Option 2: Shareable Link (Easier for Public/Semi-Public Sharing)

1. **Open Google Drive** (web interface)
2. **Navigate to**: My Drive > `h1b_analysis_pipeline_data`
3. **Right-click** on the folder → Select "Share"
4. Click **"Copy link"** or change "Restricted" to:
   - **"Anyone with the link"** → Can view (recommended for public sharing)
   - **"ifp.org"** → Only people at IFP can view (if using organization account)
5. **Copy the link** and add it to:
   - README.md in GitHub repository
   - DATA_GOOGLE_DRIVE.md
   - Any publication/documentation

**Example link format**:
```
https://drive.google.com/drive/folders/[FOLDER_ID]?usp=sharing
```

---

## Recommended Sharing Settings

### For Academic Collaboration
- **Permission**: Viewer
- **Access**: Specific people (add by email)
- **Why**: Prevents accidental modifications, clear audit trail

### For Public Release
- **Permission**: Viewer
- **Access**: Anyone with the link
- **Why**: Easy access for reproducibility, no Google account required

### For Close Co-Authors
- **Permission**: Editor
- **Access**: Specific people (add by email)
- **Why**: Allow updates to data, but limited to trusted collaborators

---

## What to Share in README

Once you have the sharing link, update these files:

### 1. Main README.md
Add the link in the "Data Files" section:
```markdown
**Google Drive Folder**: [h1b_analysis_pipeline_data](YOUR_LINK_HERE) (~8.2 GB)
```

### 2. DATA_GOOGLE_DRIVE.md
Replace `[INSERT LINK HERE]` with actual link:
```markdown
1. Access the shared Google Drive folder: [h1b_analysis_pipeline_data](YOUR_LINK_HERE)
```

### 3. Google Drive README
The main README in the Google Drive folder already has placeholders for the GitHub link.

---

## Collaborator Instructions (To Share)

**For First-Time Users:**

1. **Get GitHub repository**:
   ```bash
   git clone https://github.com/[YOUR_USERNAME]/h1b_analysis_pipeline.git
   cd h1b_analysis_pipeline
   ```

2. **Access Google Drive data**:
   - Option A: Use the shared link → Download folders to `data/` directory
   - Option B: Use Google Drive Desktop → Create symbolic links

3. **Set up symbolic links** (if using Google Drive Desktop):
   ```bash
   # Mac/Linux:
   cd h1b_analysis_pipeline
   ln -s "~/Google Drive/My Drive/h1b_analysis_pipeline_data/raw" data/raw
   ln -s "~/Google Drive/My Drive/h1b_analysis_pipeline_data/intermediate" data/intermediate
   ln -s "~/Google Drive/My Drive/h1b_analysis_pipeline_data/processed" data/processed
   ```

4. **Run the pipeline**:
   ```r
   source("run_pipeline_simple.R")
   ```

---

## Storage Limits

### Google Drive Free Account
- **Limit**: 15 GB (shared across Gmail, Drive, Photos)
- **Current usage**: ~8.2 GB for this project
- **Status**: ⚠️ Using >50% of free storage

### Recommendations
1. **Use Google Workspace** (unlimited storage with organization account)
2. **Or**: Upload to alternative platforms:
   - **Zenodo** (free, unlimited for research data, gets DOI)
   - **OSF** (Open Science Framework)
   - **Harvard Dataverse**
   - **Figshare**

### If Storage is an Issue
You can selectively share only the most critical files:
- `processed/h1b_fy21_24_with_pumas.csv` (350 MB) - needed for analysis
- `output/tables/h1b_with_native_comparisons_fy2022_2024.csv` (45 MB) - main export
- `raw/usa_00068.dat.gz` (155 MB) - ACS data

Total for just essentials: ~550 MB

---

## Managing Collaborator Access

### View Who Has Access
1. Right-click folder → "Share"
2. See list of people with access
3. Can change permissions or remove access anytime

### Best Practices
- ✅ Use viewer permissions as default
- ✅ Document who has access in a separate file (for your records)
- ✅ Review access quarterly
- ❌ Don't give editor access unless necessary
- ❌ Don't leave "Anyone with link" open indefinitely for sensitive data

---

## Troubleshooting

### "Out of Storage" Error
- Compress files before uploading
- Use Google Workspace account
- Move to alternative platform (Zenodo, OSF)

### Collaborators Can't Access
- Check if they're signed into correct Google account
- Verify link hasn't expired
- Check permission settings
- Try adding them by email directly

### Slow Download Speeds
- Use Google Drive Desktop for automatic sync
- Download during off-peak hours
- Download folders individually rather than all at once

---

## Next Steps

- [ ] Get shareable link from Google Drive
- [ ] Update README.md with the link
- [ ] Update DATA_GOOGLE_DRIVE.md with the link
- [ ] Test link in incognito/private browser window
- [ ] Share with first collaborator to test
- [ ] Consider archiving on Zenodo for DOI and long-term preservation

---

**Questions?** Contact connor@ifp.org
