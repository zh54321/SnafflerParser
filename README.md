# Snaffler Output File Parser
Especially in large environments, the Snaffler output gets very large and time-consuming to analyze.

This script parses the Snaffler output file (TSV format required) and:
- Beautifies results into readable tables and exports to TXT, CSV, HTML, JSON or PS Gridview.
- Generates an interactive HTML report with:
  - Filtering (severity, extension, modified year) and full-text search
  - Dynamic sorting
  - Keyword highlighting inside the preview text
  - Direct actions (open parent folder, download file, copy UNC, copy parent UNC)
  - Review workflow with persisted state:
    - ★ flagged (interesting)
    - ✓ done (reviewed)
  - Optional *unescape* mode for improved preview readability (experimental)
  - Pagination for very large datasets
  - Column chooser (persisted per report)
  - Export of the currently filtered view to CSV
  - Snaffler Job metadata (start/end /host/user/timestamps...) 
- Sorts output by *severity (Black/Red/Yellow/Green)* and then by modified date (default) or another field
- Exports all discovered *shares* to a text file
- Can export accessible shares as *Explorer++ bookmarks*

# Show Case
Parsing output file:

![Console Output](/images/parser_console.png "Console Output")

HTML output:
![HTML Output](/images/HTML_output.png "HTML Output")

TXT output:
![TXT Output](/images/TXT_output.png "TXT Output")

# Preconditions and Usage
Snaffler must be executed with the `-y` switch in order to create an output file in the TSV format.

Example:
`.\Snaffler.exe -o snafflerout.txt -s -y`

## Simple Parse
Simple parse the file my_snaffler_output.txt and write output with default sorting (severity, date modified) and default output files (TXT, CSV, HTML).
`.\snafflerparser.ps1 -in my_snaffler_output.txt`

## Output Options
The different file output options are:
- `-outformat all` Write txt, csv, html and json (default)
- `-outformat txt` Write txt
- `-outformat csv` Write csv
- `-outformat html` Write html
- `-outformat json` Write json

Those files can be split by finding severity (black, red, yellow, green) using the `-split` switch.

Additonally a PS gridview output can be showed using ``-gridview`.

## HTML Report

### Features

- Pagination for large reports
- Full-text search (UNC / rule / keyword / content) with highlighting
- Filters:
  - Severity (Black / Red / Yellow / Green)
  - Modified year
  - File extension (with extension search)
  - Status filters: ★ flagged only / hide ✓ done
- Sorting by clicking table headers (severity grouping is preserved unless you switch to global sort)
- Keyword highlighting in preview content
- Actions per row:
  - Copy full UNC path
  - Copy parent UNC path
  - Open parent folder (`file://`)
  - Download file (`file://`)
- Column chooser (persisted per report)
- Export the current filtered view to CSV
- Report metadata header + “Job Info” modal (input file, host/user, hash, timestamps, durations)
- Dark / Light mode toggle


### Review workflow (★ / ✓)

Two checkboxes support a quick review process:

- ★ (flagged): mark interesting files to revisit
- ✓ (done): mark reviewed files

Keyboard navigation:
- Use *W/S* or *↑/↓* to move up/down within the checkbox column
- Use *A/D* or *←/→* to move between ★ and ✓
- Press *Space* to toggle the focused checkbox
- Shortcut keys:
  - `1` toggles ★
  - `2` toggles ✓

Filtering helpers:
- “Show ★ only” to focus on flagged items
- “Hide ✓ done” to remove reviewed items from the view


Persistence: checkbox state is saved in your browser’s *localStorage* for this report.  
To permanently store the current markings, click *Save HTML* in the report (downloads a copy with your state embedded).

### Unescaping preview text (experimental)

Snaffler escapes line breaks and other characters in preview content to display it in the terminal.  
The HTML report includes an **Unescape** toggle that converts common escaped sequences (like `\n`, `\r\n`, `\t`) into readable formatting.


Example:

![Unescape example](/images/unescape.png "Unescape example")

> Note: Unescaping may also change strings that were not originally escaped by Snaffler. Treat it as a readability aid.

## Sorting
Output is always grouped by severity (Black → Red → Yellow → Green).
Within each group you can sort by:
- `-sort modified` File modified date (default)
- `-sort keyword` Snaffler keyword
- `-sort unc` File UNC Path
- `-sort rule` Snaffler rule name

## Explorer++ Integration

Explorer++ is a lightweight alternative file explorer for Windows that supports running in a different user context, including the `/netonly` switch. This is especially useful during assessments where the workstation or VM is not domain-joined.

### What SnafflerParser does

When using the `-pte` switch, SnafflerParser integrates directly with Explorer++ by managing its `config.xml` file:

- Generates `config.xml` if it does not exist (portable mode)
- Ensures the *Bookmarks Toolbar* is enabled
- Removes previously generated bookmarks
- Creates a bookmark folder per host
- Adds all accessible shares as bookmarks under the corresponding host
- Allows quick navigation to shares without repeated authentication prompts

### Usage

1. Download Explorer++ from  
   https://github.com/derceg/explorerplusplus

2. Place `Explorer++.exe` in the same directory as `snafflerParser.ps1`

3. Parse the Snaffler output and export shares to Explorer++:
   ```powershell
   .\snafflerParser.ps1 -in snafflerout.txt -pte
   ```
3. Launch Explorer++ under a different user context:
   ```powershell
   runas /user:DOMAIN\user /netonly Explorer++.exe
   ```
5. Use the Bookmarks Toolbar to browse discovered shares quickly.  
    ![Explorer++ Bookmarks](/images/explorerpp_bookmarks.png "Explorer++ Bookmarks")


Why this is useful:
- No need to authenticate separately for each share
- Works well from non-domain-joined systems


## Changelog

### 2026-01-04

#### Improved
- Faster parsing, processing, and report generation (roughly 50% faster overall)
- Reduced HTML report size (roughly 60% smaller)
- Explorer++ integration: `Config.xml` will be generated if it does not exist. The bookmark bar will be enabled if disabled.
- HTML report overhaul
	- Pagination for large reports (major performance improvement for reports with >100k files)
	- Additional filters: Modified date (year-based filtering)
	- Improved file extension filtering
	- Dark/Light mode toggle directly in the report
	- Proper line wrapping for long UNC paths
	- Export filtered results to CSV
	- Persisted flagged (★) and reviewed (✓) states using local storage
	- Columns can be shown/hidden (settings stored per report)
	- Full-text search with keyword highlighting
	- Improved and more compact filter layout
	- Action bar with additional functions (copy full UNC path / copy parent folder path)
	- Header row with report metadata and an info modal
	- Button to unescape content (experimental)


#### Fixed
- Added checks for illegal UNC paths (fixes issue #5)
- The pagination should fix issue #4

#### Removed
- Removed the `-lightmode` parameter.
- Removed the `-unescape` parameter.

### 2025-01-25

#### Improved
- Slightly improved performance
- Adjusted status messages

### 2025-01-21

#### New
- Custom checkboxes to support with the review process (feature request #3)
- Experimental unescape feature
- Dark mode

#### Improved
- General improvements HTML report


### 2025-01-17

#### Fixed
- Issue #2: Fixed: Spaces breaking in the open or download links