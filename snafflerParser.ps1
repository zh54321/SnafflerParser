<#
	.Synopsis
	Snaffler output file parser
	.Description
	Split, sort and beautify the Snaffler output.
	Adds explorer++ integration for easy file and share browsing (runas /netonly support)
	.Parameter outformat
	Output options: 
		- all : write txt, csv, html and json
		- txt : write txt
		- csv : write csv
		- json : write json
		- html : write html
		- default : write txt, csv, html
	.Parameter in
	Input file (full path or file name)
	Defaults to snafflerout.txt
	.Parameter sort
	Field to sort output:
		- modified: File modified date (default)
		- keyword: Snaffler keyword
		- unc: File UNC Path
	- rule: Snaffler rule name
	.Parameter split
	Will create splitted (by severity black, red, yellow, green) export files
	.Parameter gridview
	Analyze the file and display in PS gridview
	.Parameter gridviewload
	Switch to load an existing PS gridview output (CSV)
	.Parameter gridin
	Input file (full path or filen ame)
	Defaults to snafflerout.txt_loot_gridview.csv
	.Parameter pte
	pte (pass to explorer) exports the shares to Explorer++ as bookmarks (grouped by host)
	Explorer++ must be configured to be in Portable mode (settings saved in xml file) and only one instance is allowed.
	.Parameter snaffel
	Run Snaffler and execute parser with default settings.
	.Parameter unescape
	Un escape the preview content for better redability (Expiremental).
	.Example
	.\snafflerparser.ps1 
	(will try to load snafflerout.txt and output in TXT format)
	.Example
	.\snafflerparser.ps1 -in mysnaffleroutput.tvs
	(will try to load mysnaffleroutput.tvs and output in TXT format)
	.Example
	.\snafflerparser.ps1 outformat csv -split
	(will store results as CSV and split the files by severity)
	.Example
	.\snafflerparser.ps1 -sort unc
	(will sort by the column unc)
	.Example
	.\snafflerparser.ps1 -gridview
	(Will  additionally show the output in PS Gridview and save the gridview for later use)
	.Example
	.\snafflerparser.ps1 -gridviewload
	(Load a existing gridview (defaults to snafflerout.txt_loot_gridview.csv))
	.Example
	.\snafflerparser.ps1 -gridviewload -gridin mygridviewfile.csv
	(Load specific gridview file)
	.Example
	.\snafflerparser.ps1 -pte
	(Add Shares as Bookmarks to explorer++)

	.LINK
	https://github.com/zh54321/snaffler_parser
#>
Param (
	[String[]]
	$in = 'snafflerout.txt',
	[ValidateSet("modified", "keyword", "rule", "unc")]
	[String[]]
	$sort = "modified",
	[ValidateSet("all", "csv", "txt", "json","html")]
	[String[]]
	$outformat = "default",
	[switch]
	$gridview,
	[switch]
	$gridviewload,
	[switch]
	$split,
	[String[]]
	$gridin = 'snafflerout.txt_loot_gridview.csv',
	[String[]]
	$exlorerpp = '.\Explorer++.exe',
	[switch]
	$pte,
	[switch]
	$snaffel,
	[switch]
	$unescape,
	[switch]
	$help
)

# Function section-----------------------------------------------------------------------------------
function gridview($action){
	if ($action -eq "load") {
		write-host "[*] Loading stored Gridview file: $($gridin)"
		if (!(Test-Path -Path $in -PathType Leaf)) {
			write-host "[-] Input file not found $($gridin) use -gridin to specify the file csv"
			exit
		}
		write-host "[*] Starting Gridview (opens in background)"
		$passthruobjec = Import-Csv -Path "$($gridin)" |  Out-GridView -Title "FullView" -PassThru

	} elseif ($action -eq "start") {
		write-host "[*] Writing Gridview output file for further use"
		$fulloutput | select-object severity,rule,keyword,modified,extension,unc,content | Export-Csv -Path "$($outputname)_loot_gridview.csv" -NoTypeInformation
		write-host "[*] Starting Gridview (opens in background)"
		$passthruobjec = $fulloutput | select-object severity,rule,keyword,modified,extension,unc,content |  Out-GridView -Title "FullView" -PassThru
	}
	$countpassthruobjec = $passthruobjec | Measure-Object -Line -Property unc
	if ($countpassthruobjec.lines -ge 1) {
		if (!(Test-Path -Path $exlorerpp -PathType Leaf)) {
			write-host "[-] Explorer++ not found at $exlorerpp use -explorerpp to specify the exe file"
			exit
		} else {
			write-host "[-] Explorer++ found at $exlorerpp"
			write-host "[*] Found $($countpassthruobjec.lines) object. Trying to open them in explorer++"
			write-host "[i] Start the script in console window runas ... /netonly to access the files as different user"
			write-host "[i] Disables the 'Allow multiple instance' in Explorer++ to open multiple location in tabs "
			foreach ($path in $passthruobjec.unc) {
				$pathtoopen = (Split-Path -Path $path -Parent)
				# Danger danger Invoke-Expression
				Invoke-Expression "$exlorerpp $pathtoopen"
				Start-Sleep -Milliseconds 500
			}
		}
	} else {
		write-host "[!] No PassThru object found"
	}
	write-host "[*] Exiting..."
	exit
}

function explorerpp($objects){

	$explorerppfolder = Split-Path $exlorerpp
	if (Test-Path "$explorerppfolder\config.xml") {
		#Read XML
		$xmlfile = [XML](Get-Content "$explorerppfolder\config.xml")


		#Delete existing bookmarks
		write-host "[*] Delete existing bookmarks."
		$todelete = $xmlfile.SelectNodes("//Bookmark[@Type='1']")
		foreach($node in $todelete) {
			$node.ParentNode.RemoveChild($node)| Out-Null
			
		}
		#Delete existing bookmarks folders
		$todelete = $xmlfile.SelectNodes("//Bookmark[@Type='0']")
		foreach($node in $todelete) {
			$node.ParentNode.RemoveChild($node)| Out-Null
		}
		
		#Counter for stats and XML Object IDs
		$counteruncstats = 0
		$counterunc = 0
		$counterhosts = 0


		#Go trough all objects to great booksmarks folder and bookmark entry
		foreach ($element in $objects.unc) {

			# Isolate Server
			$element -match '\\\\(.*?)\\' | Out-Null
			$server= $Matches[1]

			if(!($xmlfile.SelectSingleNode("//Bookmark[@ItemName='$server']"))){
				#Create folder
				$newbookmarkelement = $xmlfile.CreateElement("Bookmark")
				$locationfolder = $xmlfile.ExplorerPlusPlus.Bookmarksv2.PermanentItem | where {$_.name -eq 'BookmarksToolbar'}
				$newbookmarkelementadd = $locationfolder.AppendChild($newbookmarkelement)
				$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("name",$counterhosts)
				$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("Type","0")
				$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("GUID",([guid]::NewGuid().ToString()))
				$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("ItemName",$server)
				$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("DateCreatedLow","3561811627")
				$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("DateCreatedHigh","3561811627")
				$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("DateModifiedLow","3561811627")
				$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("DateModifiedHigh","3561811627")
				$counterunc = 0
				$counterhosts++
			}

			#Add new bookmarks to the folder
			$newbookmarkelement = $xmlfile.CreateElement("Bookmark")
			$location = $xmlfile.SelectSingleNode("//Bookmark[@ItemName='$server']")
			$newbookmarkelementadd = $location.AppendChild($newbookmarkelement)
			$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("name",$counterunc)
			$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("Type","1")
			$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("GUID",([guid]::NewGuid().ToString()))
			$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("ItemName",$element)
			$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("Location",$element)
			$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("DateCreatedLow","3561811627")
			$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("DateCreatedHigh","3561811627")
			$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("DateModifiedLow","3561811627")
			$newbookmarkattribute = $newbookmarkelementadd.SetAttribute("DateModifiedHigh","3561811627")
			$counterunc++
			$counteruncstats++
		}
		
		#Handle local folder because xml.save can't...
		if ($explorerppfolder -eq ".") {
			$xmlfile.Save("$pwd\config.xml")
		} else {
			$xmlfile.Save("$explorerppfolder\config.xml")
		}
		
		write-host "[+] Added $($counterhosts) bookmark-folders with $($counteruncstats) bookmarks"
	
	} else {
		write-host "[!] Aborting: Explorer++ config file not found at $explorerppfolder\config.xml !"
		write-host "[?] Is Explorer++ configured in portable mode (XML file should exist)?"
		exit
	}
	
}

# Function to export as CSV
function exportcsv($object ,$name){
	write-host "[*] Store: $($outputname)_loot_$($name).csv"
	$object | select-object severity,rule,keyword,modified,extension,unc,content | Export-Csv -Path "$($outputname)_loot_$($name).csv" -NoTypeInformation
}

# Function to export as TXT
function exporttxt($object ,$name){
	write-host "[*] Store: $($outputname)_loot_$($name).txt"
	$object | Format-Table severity,rule,keyword,modified,extension,unc,content -AutoSize | Out-String -Width 10000 | Out-File -FilePath "$($outputname)_loot_$($name).txt"
}

# Function to export as JSON
function exportjson($object ,$name){
	write-host "[*] Store: $($outputname)_loot_$($name).json"
	$object | select-object severity,rule,keyword,modified,extension,unc,content | ConvertTo-Json -depth 100  | Out-File -FilePath "$($outputname)_loot_$($name).json"
}

# Function to export as HTML
function exporthtml($object ,$name){
$Header = @"
<style>
    h2 {
        font-family: Arial, Helvetica, sans-serif;
        color: #000099;
        font-size: 20px;
        font-weight: bold;
    }
	table {
		font-size: 14px;
		border: 0px; 
		font-family: Arial, Helvetica, sans-serif;
	} 

    td {
		padding: 4px;
		margin: 0px;
		border: 0;
	}
	
    th {
        background: #395870;
        background: linear-gradient(#49708f, #293f50);
        color: #fff;
        font-size: 11px;
        padding: 5px 7px;
        vertical-align: middle;
        position: sticky;
		top: 0;
		cursor: pointer;
	}

    tbody tr:nth-child(even) {
        background: #f0f0f2;
    }

    tbody tr:hover td {
        background-color: lightblue;
    }

</style>
<script>
document.addEventListener("DOMContentLoaded", function() {
    var tables = document.getElementsByTagName("table");

    if (tables.length > 1) {
        var table = tables[1]; // Select the second table
        var headers = table.getElementsByTagName("th");
        var sortDirections = Array(headers.length).fill("asc"); // Track sort direction for each column

        // Find the column index of the "Extension" and "Severity" columns
        var extensionColumnIndex = -1;
        var severityColumnIndex = -1;

        for (let i = 0; i < headers.length; i++) {
            let headerText = headers[i].innerText.toLowerCase();
            if (headerText === "extension") {
                extensionColumnIndex = i;
            }
            if (headerText === "severity") {
                severityColumnIndex = i;
            }
        }

        if (severityColumnIndex !== -1) {
            generateSeverityFilterMenu(table, severityColumnIndex);
        }

        if (extensionColumnIndex !== -1) {
            generateFilterMenu(table, extensionColumnIndex);
        }

        if (headers.length > 0) { // Check if the second table has headers
            // Loop through the headers and add the onclick event
            for (let i = 0; i < headers.length; i++) {
                headers[i].addEventListener("click", function() {
                    sortTable(table, i, sortDirections[i]);
                    // Toggle sort direction for the next click
                    sortDirections[i] = sortDirections[i] === "asc" ? "desc" : "asc";
                });
            }
        }
    }

    function sortTable(table, columnIndex, direction) {
        var rows = Array.from(table.rows).slice(1); // Convert HTMLCollection to array and skip the header row

        // Define custom order for the first column
        var customOrder = ["Black", "Red", "Yellow", "Green"];

        // Custom sorting function
        rows.sort(function(rowA, rowB) {
            var x = rowA.cells[columnIndex].innerText.trim();
            var y = rowB.cells[columnIndex].innerText.trim();

            if (columnIndex === 0) {
                // Custom sorting logic for the first column
                var xIndex = customOrder.indexOf(x);
                var yIndex = customOrder.indexOf(y);
                return direction === "asc" ? xIndex - yIndex : yIndex - xIndex;
            } else {
                // Alphabetical sorting for other columns
                return direction === "asc" ? x.localeCompare(y) : y.localeCompare(x);
            }
        });

        // Rebuild the table
        var fragment = document.createDocumentFragment();
        rows.forEach(function(row) {
            fragment.appendChild(row);
        });

        table.tBodies[0].appendChild(fragment);
    }

    function generateSeverityFilterMenu(table, severityColumnIndex) {
        var filterMenu = document.getElementById("filter-menu");
        filterMenu.innerHTML = ''; // Clear previous content

        var severityLevels = ["Black", "Red", "Yellow", "Green"];

        // Create severity filter checkboxes
        severityLevels.forEach(function(severity) {
            var label = document.createElement("label");
            label.style.display = "inline-block";
            label.style.marginRight = "10px";

            var checkbox = document.createElement("input");
            checkbox.type = "checkbox";
            checkbox.value = severity;
            checkbox.checked = true; // Default to checked

            label.appendChild(checkbox);
            label.appendChild(document.createTextNode(severity));
            filterMenu.appendChild(label);
        });

        // Add a line break and horizontal separator before the extension filter menu
        filterMenu.appendChild(document.createElement("br"));
        filterMenu.appendChild(document.createElement("hr"));
    }

    function generateFilterMenu(table, extensionColumnIndex) {
        var filterMenu = document.getElementById("filter-menu");

        var uniqueExtensions = new Set();

        // Collect unique extensions from the table, case insensitive
        Array.from(table.rows).slice(1).forEach(function(row) {
            var extension = row.cells[extensionColumnIndex].innerText.trim().toLowerCase();
            if (extension) {
                uniqueExtensions.add(extension);
            }
        });

        // Convert Set to Array and sort alphabetically (case-insensitive)
        var sortedExtensions = Array.from(uniqueExtensions).sort((a, b) => a.localeCompare(b));

        // Create checkboxes for each sorted extension
        sortedExtensions.forEach(function(extension) {
            var label = document.createElement("label");
            label.style.display = "inline-block"; // Display inline for horizontal layout
            label.style.marginRight = "10px"; // Add some space between labels

            var checkbox = document.createElement("input");
            checkbox.type = "checkbox";
            checkbox.className = "extension-checkbox"; // Add class to distinguish from severity checkboxes
            checkbox.value = extension;
            checkbox.checked = true; // Default to checked

            label.appendChild(checkbox);
            label.appendChild(document.createTextNode(extension));
            filterMenu.appendChild(label);
        });

        // Create a container for the buttons
        var buttonContainer = document.createElement("div");
        buttonContainer.style.marginTop = "10px"; // Add space above the container
        buttonContainer.style.display = "flex"; // Align buttons in a single line
        buttonContainer.style.gap = "10px"; // Add space between buttons

        // Add "Select All" button
        var selectAllButton = document.createElement("button");
        selectAllButton.innerText = "Select All";
        selectAllButton.addEventListener("click", function() {
            setAllExtensionCheckboxes(true);
        });
        buttonContainer.appendChild(selectAllButton);

        // Add "Deselect All" button
        var deselectAllButton = document.createElement("button");
        deselectAllButton.innerText = "Deselect All";
        deselectAllButton.addEventListener("click", function() {
            setAllExtensionCheckboxes(false);
        });
        buttonContainer.appendChild(deselectAllButton);

        filterMenu.appendChild(buttonContainer);

		// Line
		filterMenu.appendChild(document.createElement("br"));
        filterMenu.appendChild(document.createElement("hr"));

        // Add one "Apply Filter" button at the end of the filter menu
        var applyButton = document.createElement("button");
        applyButton.innerText = "Apply Filter";
        applyButton.style.marginTop = "5px"; // Add some space above the button
        applyButton.addEventListener("click", function() {
            applyFilters(table, extensionColumnIndex, severityColumnIndex);
        });
        filterMenu.appendChild(applyButton);

        // Add a display for the row count below the apply button
        var rowCountDisplay = document.createElement("div");
        rowCountDisplay.id = "row-count";
        rowCountDisplay.style.marginTop = "15px"; // Space between button and row count
        filterMenu.appendChild(rowCountDisplay);

        updateRowCount(table);
    }

    function setAllExtensionCheckboxes(checked) {
        var checkboxes = document.querySelectorAll("#filter-menu input.extension-checkbox");
        checkboxes.forEach(function(checkbox) {
            checkbox.checked = checked;
        });
    }

    function applyFilters(table, extensionColumnIndex, severityColumnIndex) {
        showLoadingIndicator();

        setTimeout(function() { // Simulate processing time
            var severityCheckboxes = document.querySelectorAll("#filter-menu input[type='checkbox'][value]");
            var selectedSeverities = Array.from(severityCheckboxes)
                                          .filter(checkbox => checkbox.checked)
                                          .map(checkbox => checkbox.value);

            var extensionCheckboxes = document.querySelectorAll("#filter-menu input.extension-checkbox");
            var selectedExtensions = Array.from(extensionCheckboxes)
                                          .filter(checkbox => checkbox.checked)
                                          .map(checkbox => checkbox.value);

            // Apply filters in a single pass
            Array.from(table.rows).slice(1).forEach(function(row) {
                var severity = row.cells[severityColumnIndex].innerText.trim();
                var extension = row.cells[extensionColumnIndex].innerText.trim().toLowerCase();

                var showRow = selectedSeverities.includes(severity) && selectedExtensions.includes(extension);
                row.style.display = showRow ? "" : "none";
            });

            updateRowCount(table);

            hideLoadingIndicator();
        }, 0); // Execute after a short delay
    }

    function showLoadingIndicator() {
        var loadingIndicator = document.createElement("div");
        loadingIndicator.id = "loading-indicator";
        loadingIndicator.innerText = "Filtering, please wait...";
        loadingIndicator.style.position = "fixed";
        loadingIndicator.style.top = "50%";
        loadingIndicator.style.left = "50%";
        loadingIndicator.style.transform = "translate(-50%, -50%)";
        loadingIndicator.style.padding = "20px";
        loadingIndicator.style.backgroundColor = "rgba(0, 0, 0, 0.8)";
        loadingIndicator.style.color = "white";
        loadingIndicator.style.borderRadius = "5px";
        loadingIndicator.style.zIndex = "1000";
        document.body.appendChild(loadingIndicator);
    }

    function hideLoadingIndicator() {
        var loadingIndicator = document.getElementById("loading-indicator");
        if (loadingIndicator) {
            loadingIndicator.remove();
        }
    }

	function updateRowCount(table) {
		var totalRowCount = table.rows.length - 1; // Subtract 1 to exclude the header row
		var visibleRowCount = Array.from(table.rows).slice(1).filter(row => row.style.display !== "none").length;

		var rowCountDisplay = document.getElementById("row-count");
		rowCountDisplay.innerText = "Visible files: " + visibleRowCount + " of " + totalRowCount;
	}

});



document.addEventListener('DOMContentLoaded', () => {

    // ========================= SEVERITY COLORS =========================
    document.querySelectorAll('table td:first-of-type').forEach(td => {
        switch (td.textContent.trim()) {
            case 'Black':
                td.style.backgroundColor = '#333';
                td.style.color = 'white';
                break;
            case 'Red':
                td.style.backgroundColor = '#d9534f';
                td.style.color = 'white';
                break;
            case 'Yellow':
                td.style.backgroundColor = '#CFAD01';
                td.style.color = 'white';
                break;
            case 'Green':
                td.style.backgroundColor = '#79C55B';
                td.style.color = 'white';
                break;
            default:
                td.style.backgroundColor = 'transparent';
                td.style.color = 'black';
        }
    });
	
	// Filter section
	const buttons = document.querySelectorAll('.filter-buttons button');
	const tables = document.querySelectorAll('table');
	
	if (tables.length < 2) {
		console.error('There are less than 2 tables in the document.');
		return;
	}

	const secondTable = tables[1]; // Get the second table
	const rows = secondTable.querySelectorAll('tr');

	buttons.forEach(button => {
		button.addEventListener('click', () => {
			const filter = button.getAttribute('data-filter');
			rows.forEach(row => {
				const firstCell = row.querySelector('td:first-of-type');
				if (firstCell) {
					const cellText = firstCell.textContent.trim();
					if (filter === 'all' || cellText === filter) {
						row.style.display = '';
					} else {
						row.style.display = 'none';
					}
				}
			});
		});
    
	});

	// Set the default filter to 'all'
	buttons.forEach(button => {
		if (button.getAttribute('data-filter') === 'all') {
			button.click(); // Trigger the click event to show all rows
		}
	});

    // ========================= MARK SNAFFLER CONTENT =========================
        const rows2 = document.querySelectorAll('table tbody tr');

    // Find the header row to determine the index of the 'Keyword' and 'Content' columns
    const headerCells = document.querySelectorAll('table thead th, table tbody tr:first-child th');
    
    let keywordIndex = -1;
    let contentIndex = -1;

    headerCells.forEach((headerCell, index) => {
        const headerText = headerCell.textContent.trim().toLowerCase();
        if (headerText === 'keyword') {
            keywordIndex = index;
        }
        if (headerText === 'content') {
            contentIndex = index;
        }
    });

    // If both columns are found
    if (keywordIndex !== -1 && contentIndex !== -1) {
        // Iterate through each row (excluding the header)
        rows2.forEach((row2, rowIndex) => {
            if (rowIndex > 0) { // Skip the header row if it's in tbody
                const cells = row2.querySelectorAll('td');
                const keywordCell = cells[keywordIndex];
                const contentCell = cells[contentIndex];

                if (keywordCell && contentCell) {
                    // Get the text from the keyword and content cells
                    const keyword = keywordCell.textContent.trim();
                    let content = contentCell.innerHTML;

                    // Create a regular expression to find the keyword in the content (case-insensitive)
                    const regex = new RegExp(``(`${keyword})``, 'gi');

                    // Replace the keyword with highlighted keyword in red
                    content = content.replace(regex, '<span style="color: red;">`$1</span>');

                    // Update the content cell with the new HTML
                    contentCell.innerHTML = content;
                }
            }
        });
    }
});

</script>
"@

$titleAndFilter = @"
<h2>Files</h2>
<div id="filter-menu"></div><br>
"@

	write-host "[*] Store: $($outputname)_loot_$($name).html"
	$inputInfo = $baseInfo | ConvertTo-Html -As List -Fragment -PreContent "<h2>Input Information</h2>"
	$mainTable = $object | ConvertTo-Html -Fragment -PreContent $titleAndFilter
	$htmlOutput = ConvertTo-Html -Head $Header -Body "$inputInfo $mainTable"

	#Replace placeholder strings
	$htmlOutput = $htmlOutput -replace '@@o@@','<'
	$htmlOutput = $htmlOutput -replace '@@c@@','>'
	$htmlOutput = $htmlOutput -replace '@@a@@','&'
	

	
	$htmlOutput | Out-File -FilePath "$($outputname)_loot_$($name).html"
}



# Script section-----------------------------------------------------------------------------------

$banner = @"
 ____               __  __ _             ____                          
/ ___| _ __   __ _ / _|/ _| | ___ _ __  |  _ \ __ _ _ __ ___  ___ _ __ 
\___ \|  _ \ / _  | |_| |_| |/ _ \ '__| | |_) / _  | '__/ __|/ _ \ '__|
 ___) | | | | (_| |  _|  _| |  __/ |    |  __/ (_| | |  \__ \  __/ |   
|____/|_| |_|\__,_|_| |_| |_|\___|_|    |_|   \__,_|_|  |___/\___|_|   
																	   																								
"@

Write-Host $banner

# Check if snaffler should be executed
if ($help) {
	get-help $MyInvocation.MyCommand.Definition -full
	exit
}

if ($snaffel) {
	.\Snaffler.exe -o snafflerout.txt -s -y
}

# Check if gridviewfile should be loaded
if ($gridviewload) {
	gridview load
}

# Check snaffler input file and load it
write-host "[*] Check input file $in"
if (!(Test-Path -Path $in -PathType Leaf)) {
	write-host "[-] Input file not found $in"
	exit
} else {
	write-host "[+] Input file exists"
	$inputlines = (Get-Content $in).Length
	if ($inputlines -ge 1) {
		write-host "[+] Input file has $inputlines Lines"
		$data = Import-Csv -Delimiter "`t" -Path $in -Header user, timestamp , typ, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
		$outputname = (Get-Item $in).BaseName

		$baseInfo = [PsCustomObject]@{
			Snaffler_File = Split-Path $in -Leaf
			SHA265 = $(Get-FileHash $in).Hash
		}

		$firstLine = Get-Content $in -TotalCount 1

		# Define the regular expression pattern to extract Computername, User and timestamp
		$pattern = '\[(?<machine>.*?)\\(?<user>.*?)@.*?\]\s+(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}Z)'


		if ($firstLine -match $pattern) {
			$baseInfo | Add-Member -NotePropertyName Snaffler_ComputerName -NotePropertyValue $matches['machine']
			$baseInfo | Add-Member -NotePropertyName Snaffler_User -NotePropertyValue $matches['user']
			$baseInfo | Add-Member -NotePropertyName Snaffler_StartTime -NotePropertyValue $matches['timestamp']
		}
	} else {
		write-host "[!] Input file seems to be empty"
		exit
	}

}

# Processing shares
$shares = foreach ($line in $data) {
    if($line.Typ -eq "[Share]") {
		[PsCustomObject]@{
			unc = $line.2
		}
    }
}

#Sort and perform dedup (in case snaffler was runned twice)
$shares = $shares | Sort-Object -Property unc -Unique

# Check share count and write to file
$sharescount = $shares | Measure-Object -Line -Property unc
if ($sharescount.lines -ge 1) {
	write-host "[+] Shares identified: $($sharescount.lines)"
	write-host "[*] Write share output file"
	$shares | Format-Table -AutoSize | Out-File -FilePath "$($outputname)_shares.txt"
} else {
	write-host "[!] Shares identified: 0"
	write-host "[?] Was Snaffler executed with parameter -y ?"
}


# Processing files
write-host "[*] Processing files"


$files = foreach ($line in $data) {
    if($line.Typ -eq "[File]" -and $line.9 -ne $Null) {
		git rb
		$content = $line.10
		
		#Unescape the content (experimental)
		if ($unescape) {
			try {
				# Attempt to unescape the content
				$content = [System.Text.RegularExpressions.Regex]::Unescape($content)
			} catch {
				# Suppress the error message
				$content = $content
			}
			#Format HTML
			$content = $content -replace ([regex]::Escape("`t")),'@@a@@emsp;'
			$content = $content -replace ([regex]::Escape("`r`n")),'@@o@@br@@c@@'
		}

		[PsCustomObject]@{
			severity = $line.1
			rule = $line.2
			keyword = $line.6
			modified = $line.8
			unc = $line.9
			extension = [System.IO.Path]::GetExtension($($line.9))
			#Since HTML chars are encoded to entities, special strings are used and replaced later
			open = "@@o@@a href=$(Split-Path -Parent $($line.9))\ @@c@@@@o@@span style='font-size:100px;'@@c@@@@a@@#x1F4C2;@@o@@/span@@c@@"
			save = "@@o@@a href=$($line.9) download@@c@@@@o@@span style='font-size:100px;'@@c@@@@a@@#x1F4BE;@@o@@/span@@c@@"
			content = $content			
		}
    }
}

## Ugly hack to default to descending sort, maybe fix
if ($sort -eq "modified") {

	$blacks = $files | where-object severity -EQ "Black" | sort-object -Property $sort -Descending
	$reds = $files | where-object severity -EQ "Red" | sort-object -Property $sort -Descending
	$yellows = $files | where-object severity -EQ "Yellow" | sort-object -Property $sort -Descending
	$greens = $files | where-object severity -EQ "Green" | sort-object -Property $sort -Descending
	$fulloutput = ForEach ($Result in "Black", "Red", "Yellow", "Green") {
		$files | Where-Object {$_.Severity -eq $Result } | sort-object -Property $sort -Descending
	}

} else {
	$blacks = $files | where-object severity -EQ "Black" | sort-object -Property $sort
	$reds = $files | where-object severity -EQ "Red" | sort-object -Property $sort
	$yellows = $files | where-object severity -EQ "Yellow" | sort-object -Property $sort
	$greens = $files | where-object severity -EQ "Green" | sort-object -Property $sort
	$fulloutput = ForEach ($Result in "Black", "Red", "Yellow", "Green") {
		$files | Where-Object {$_.Severity -eq $Result } | sort-object -Property $sort
	}
}

# Check file count for error detection and output
if ($blacks -ne $null) {$blackscount = $blacks | Measure-Object -Line -Property unc | select-object -ExpandProperty Lines} else {$blackscount = 0}
if ($reds -ne $null) {$redscount  = $reds | Measure-Object -Line -Property unc | select-object -ExpandProperty Lines} else {$redscount = 0}
if ($yellows -ne $null) {$yellowscount = $yellows | Measure-Object -Line -Property unc | select-object -ExpandProperty Lines} else {$yellowscount = 0}
if ($greens -ne $null) {$greenscount = $greens | Measure-Object -Line -Property unc | select-object -ExpandProperty Lines} else {$greenscount = 0}

$filesum = $blackscount + $redscount + $yellowscount + $greenscount
if ($filesum -ge 1) {
	write-host "[+] Files total: $filesum "
	write-host "[+] Files with severity BLACK: $blackscount"
	write-host "[+] Files with severity RED: $redscount"
	write-host "[+] Files with severity YELLOW: $yellowscount"
	write-host "[+] Files with severity GREEN: $greenscount"

	#Write outputs depening on desired format
	if ($outformat -eq "all"){
		write-host "[*] Exporting full CSV + TXT + JSON + HTML"
		exporttxt $fulloutput full
		exportcsv $fulloutput full
		exportjson $fulloutput full
		exporthtml $fulloutput full
		if ($split) {
			write-host "[*] Exporting splitted CSV + TXT"
			if ($blackscount -ge 1) {exportcsv $blacks blacks}
			if ($redscount -ge 1) {exportcsv $reds reds}
			if ($yellowscount -ge 1) {exportcsv $yellows yellows}
			if ($greenscount -ge 1) {exportcsv $greens greens}
			if ($blackscount -ge 1) {exporttxt $blacks blacks}
			if ($redscount -ge 1) {exporttxt $reds reds}
			if ($yellowscount -ge 1) {exporttxt $yellows yellows}
			if ($greenscount -ge 1) {exporttxt $greens greens}
			if ($blackscount -ge 1) {exportjson $blacks blacks}
			if ($redscount -ge 1) {exportjson $reds reds}
			if ($yellowscount -ge 1) {exportjson $yellows yellows}
			if ($greenscount -ge 1) {exportjson $greens greens}
			if ($blackscount -ge 1) {exporthtml $blacks blacks}
			if ($redscount -ge 1) {exporthtml $reds reds}
			if ($yellowscount -ge 1) {exporthtml $yellows yellows}
			if ($greenscount -ge 1) {exporthtml $greens greens}
		}
	} elseif ($outformat -eq "default") {
		write-host "[*] Exporting full CSV + TXT + HTML"
		exporttxt $fulloutput full
		exportcsv $fulloutput full
		exporthtml $fulloutput full
		if ($split) {
			write-host "[*] Exporting splitted CSV + TXT"
			if ($blackscount -ge 1) {exportcsv $blacks blacks}
			if ($redscount -ge 1) {exportcsv $reds reds}
			if ($yellowscount -ge 1) {exportcsv $yellows yellows}
			if ($greenscount -ge 1) {exportcsv $greens greens}
			if ($blackscount -ge 1) {exporttxt $blacks blacks}
			if ($redscount -ge 1) {exporttxt $reds reds}
			if ($yellowscount -ge 1) {exporttxt $yellows yellows}
			if ($greenscount -ge 1) {exporttxt $greens greens}
			if ($blackscount -ge 1) {exporthtml $blacks blacks}
			if ($redscount -ge 1) {exporthtml $reds reds}
			if ($yellowscount -ge 1) {exporthtml $yellows yellows}
			if ($greenscount -ge 1) {exporthtml $greens greens}
		}
	} elseif ($outformat -eq "txt") {
		write-host "[*] Exporting full TXT"
		exporttxt $fulloutput full

		if ($split) {
			write-host "[*] Exporting splitted TXT"
			if ($blackscount -ge 1) {exporttxt $blacks blacks}
			if ($redscount -ge 1) {exporttxt $reds reds}
			if ($yellowscount -ge 1) {exporttxt $yellows yellows}
			if ($greenscount -ge 1) {exporttxt $greens greens}
		}
	} elseif ($outformat -eq "csv") {
		write-host "[*] Exporting full CSV"
		exportcsv $fulloutput full
		if ($split) {
			write-host "[*] Exporting splitted CSV"
			if ($blackscount -ge 1) {exportcsv $blacks blacks}
			if ($redscount -ge 1) {exportcsv $reds reds}
			if ($yellowscount -ge 1) {exportcsv $yellows yellows}
			if ($greenscount -ge 1) {exportcsv $greens greens}
		}
	} elseif ($outformat -eq "json") {
		write-host "[*] Exporting full JSON"
		exportjson $fulloutput full
		if ($split) {
			write-host "[*] Exporting splitted JSON"
			if ($blackscount -ge 1) {exportjson $blacks blacks}
			if ($redscount -ge 1) {exportjson $reds reds}
			if ($yellowscount -ge 1) {exportjson $yellows yellows}
			if ($greenscount -ge 1) {exportjson $greens greens}
		}
	} elseif ($outformat -eq "html") {
		write-host "[*] Exporting full HTML"
		exporthtml $fulloutput full
		if ($split) {
			write-host "[*] Exporting splitted HTML"
			if ($blackscount -ge 1) {exporthtml $blacks blacks}
			if ($redscount -ge 1) {exporthtml $reds reds}
			if ($yellowscount -ge 1) {exporthtml $yellows yellows}
			if ($greenscount -ge 1) {exporthtml $greens greens}
		}
	}
} else {
	# Error handling if no files detected
	write-host "[!] Something is wrong. Number of files identified: $filesum"
	write-host "[?] Was Snaffler executed with parameter -y ?"
	exit
}

# Start grid view if desired
if ($gridview) {
	gridview start
}

# Check if shares should be exported as bookmarks to Explorer++
if ($pte) {
	write-host "[*] Will export $($sharescount.lines) shares to explorer."
	explorerpp($shares)
}
