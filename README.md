# Snaffler Output File Parser
Especially in large environments, the Snaffler output gets very large and time-consuming to analyze.

This script parse the Snaffler outputfile (TSV format required) and:
- Beautify it: Proper tables and different output formats like TXT, CSV, HTML, JSON or PS Gridview.
- The HTML file supports basic sortignand filtering and contains direct links to the parent folder of the file and a download link for the file itself.
- Sort based on the severity (black, red, yellow, green) and then by date or unc.
- Can export all the shares to the Explorer++ config files as bookmarks.
- Generate a list of all shares Snaffler was able to access.

# ShowCase

# Preconditions and usage
Snaffler must be executed with the `-y` switch in order to create an output file in the TSV format.

Example:
`.\Snaffler.exe -o snafflerout.txt -s -y`

## Simple parse
Simple parse the file my_snaffler_output.txt and write output with default sorting (severity, date modified) and default output files (TXT, CSV, HTML).
`.\snafflerparser.ps1 -in my_snaffler_output.txt`

## Output options
The different file output options are:
- `-outformat all` Write txt, csv, html and json
- `-outformat txt` Write txt
- `-outformat csv` Write csv
- `-outformat html` Write html (includes clickable links)
- `-outformat json` Write json

Those files can be splitted regarding the finding severity (black, red, yellow, green) using the `-split` switch.

Additonally a PS gridview output can be showed using ``-gridview`.

## Sorting
The output will always be sorted regarding the severity than it can be sorted by:
- `-sort modified` File modified date (default)
- `-sort keyword` Snaffler keyword
- `-sort unc` File UNC Path
- `-sort rule` Snaffler rule name

## Explorer++ integration

Explorer++ is an alternative file explorer on windows.


The great thing is that unlike the Windows Explorer it can be executed in another user's context including the `/netonly` switch. This is useful when performing a pentest from a dedicated, non-domain joined pentest notebook or VM.

Donwload Explorer++ https://github.com/derceg/explorerplusplus to the same folder and configure the portable mode:

![Configure Explorer++ in portable mode](/images/explorerpp_settings.png "Configure portable mode")
This will create an config.xml in the same folder.

Parse the Snaffler file using the `-pte` switch to export all accessible shares as bookmarks to the Explorer++ config XML: `.\snafflerParser.ps1 -in Snaffler_output.txt -pte`

Explorer++ can then be executed as the user which have access to the shares: `runas /user:domain\user /netonly Explorerpp.exe`
This allows easy access to the shares without authenticate for every share.


