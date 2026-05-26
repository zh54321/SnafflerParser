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
	Input file (full path or filename)
	Defaults to snafflerout.txt_loot_gridview.csv
	.Parameter pte
	pte (pass to explorer) exports the shares to Explorer++ as bookmarks (grouped by host)
	Explorer++ must be configured to be in Portable mode (settings saved in xml file) and only one instance is allowed.
	.Parameter snaffel
	Run Snaffler and execute parser with default settings.
	.Example
	.\snafflerparser.ps1 
	(will try to load snafflerout.txt and output in HTML, CSV and TXT format)
	.Example
	.\snafflerparser.ps1 -in mysnaffleroutput.tvs
	(will try to load mysnaffleroutput.tvs in HTML, CSV and TXT format)
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
	[String]
	$in = 'snafflerout.txt',
	[ValidateSet("modified", "keyword", "rule", "unc")]
	[String]
	$sort = "modified",
	[ValidateSet("all", "csv", "txt", "json","html","default")]
	[String]
	$outformat = "default",
	[switch]
	$gridview,
	[switch]
	$gridviewload,
	[switch]
	$split,
	[String]
	$gridin = 'snafflerout.txt_loot_gridview.csv',
	[String]
	$exlorerpp = '.\Explorer++.exe',
	[switch]
	$pte,
	[switch]
	$snaffel,
	[switch]
	$help
)

# Resolve input file path
if ([System.IO.Path]::IsPathRooted($in)) {
    # Absolute path provided
    $inPath = $in
} else {
    # Relative path or filename only → current directory
    $inPath = Join-Path -Path (Get-Location) -ChildPath $in
}

# Normalize (removes .\, ..\, etc.)
$inPath = [System.IO.Path]::GetFullPath($inPath)


# Function section-----------------------------------------------------------------------------------

function Format-TimePrettyUtc {
    param([object]$value)

    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return "" }

    try {
        switch ($value.GetType().FullName) {
            'System.DateTimeOffset' { return $value.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'") }
            'System.DateTime'       { return ([DateTime]$value).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'") }
            default {
                # Try to parse string as DateTimeOffset first (handles Z nicely)
                $dto = [DateTimeOffset]::Parse(
                    [string]$value,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AssumeUniversal
                )
                return $dto.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")
            }
        }
    } catch {
        # If parsing fails, just return original string
        return [string]$value
    }
}

function Format-DurationPretty {
    param([TimeSpan]$ts)

    if ($null -eq $ts) { return "" }

    $parts = @()

    if ($ts.Days    -gt 0) { $parts += "$($ts.Days)d" }
    if ($ts.Hours   -gt 0) { $parts += "$($ts.Hours)h" }
    if ($ts.Minutes -gt 0) { $parts += "$($ts.Minutes)m" }

    # Round to whole seconds (0.5s rounds up)
    $totalSecondsRounded = [int][math]::Round($ts.TotalSeconds, 0, [MidpointRounding]::AwayFromZero)

    if ($parts.Count -gt 0) {
        # show remaining seconds within the minute (also whole)
        $secWithinMinute = $totalSecondsRounded % 60
        $parts += ("{0}s" -f $secWithinMinute)
    } else {
        # only seconds (whole)
        $parts += ("{0}s" -f $totalSecondsRounded)
    }

    return ($parts -join " ")
}



function gridview($action){
	if ($action -eq "load") {
		write-host "[*] Loading stored Gridview file: $($gridin)"
		if (!(Test-Path -LiteralPath $inpath -PathType Leaf)) {
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
			write-host "[*] Found $($countpassthruobjec.lines) object. Trying to open them in Explorer++ "
			write-host "[i] Start the script in console window runas ... /netonly to access the files as different user"
			write-host "[i] Disables the 'Allow multiple instance' in Explorer++ to open multiple location in tabs "
			foreach ($path in $passthruobjec.unc) {
				$pathtoopen = (Split-Path -Path $path -Parent)
				# Danger danger Invoke-Expression
				& $exlorerpp $pathtoopen
				Start-Sleep -Milliseconds 500
			}
		}
	} else {
		write-host "[!] No PassThru object found"
	}
	write-host "[*] Exiting"
	exit
}


function explorerpp($objects) {

    $explorerppfolder = Split-Path $exlorerpp
    $configPath = Join-Path $explorerppfolder "config.xml"

    # If exlorerpp is ".\Explorer++.exe", Split-Path returns "."
    if ($explorerppfolder -eq ".") {
        $configPath = Join-Path $pwd "config.xml"
    }

    # -----------------------------
    # Default config.xml template
    # -----------------------------
    $defaultConfig = @'
<?xml version="1.0"?>
<!-- Preference file for Explorer++ generated by Snafflerparser-->
<ExplorerPlusPlus>
	<Settings>
		<Setting name="AllowMultipleInstances">yes</Setting>
		<Setting name="AlwaysOpenInNewTab">no</Setting>
		<Setting name="AlwaysShowTabBar">yes</Setting>
		<Setting name="AutoArrangeGlobal">yes</Setting>
		<Setting name="CheckBoxSelection">no</Setting>
		<Setting name="CloseMainWindowOnTabClose">yes</Setting>
		<Setting name="ConfirmCloseTabs">no</Setting>
		<Setting name="DisableFolderSizesNetworkRemovable">no</Setting>
		<Setting name="DisplayCentreColor" r="255" g="255" b="255"/>
		<Setting name="DisplayFont" Height="-13" Width="0" Weight="500" Italic="no" Underline="no" Strikeout="no" Font="Segoe UI"/>
		<Setting name="DisplaySurroundColor" r="0" g="94" b="138"/>
		<Setting name="DisplayTextColor" r="0" g="0" b="0"/>
		<Setting name="DisplayWindowWidth">300</Setting><Setting name="DisplayWindowHeight">90</Setting>
		<Setting name="DisplayWindowVertical">no</Setting>
		<Setting name="DoubleClickTabClose">yes</Setting>
		<Setting name="ExtendTabControl">no</Setting>
		<Setting name="ForceSameTabWidth">no</Setting>
		<Setting name="ForceSize">no</Setting>
		<Setting name="HandleZipFiles">no</Setting>
		<Setting name="HideLinkExtensionGlobal">no</Setting>
		<Setting name="HideSystemFilesGlobal">no</Setting>
		<Setting name="InfoTipType">0</Setting>
		<Setting name="InsertSorted">yes</Setting>
		<Setting name="Language">9</Setting>
		<Setting name="LargeToolbarIcons">no</Setting>
		<Setting name="LastSelectedTab">0</Setting>
		<Setting name="LockToolbars">yes</Setting>
		<Setting name="NextToCurrent">no</Setting>
		<Setting name="NewTabDirectory">::{20D04FE0-3AEA-1069-A2D8-08002B30309D}</Setting>
		<Setting name="OneClickActivate">no</Setting>
		<Setting name="OneClickActivateHoverTime">500</Setting>
		<Setting name="OverwriteExistingFilesConfirmation">yes</Setting>
		<Setting name="PlayNavigationSound">yes</Setting>
		<Setting name="ReplaceExplorerMode">1</Setting>
		<Setting name="ShowAddressBar">yes</Setting>
		<Setting name="ShowApplicationToolbar">yes</Setting>
		<Setting name="ShowBookmarksToolbar">yes</Setting>
		<Setting name="ShowDrivesToolbar">yes</Setting>
		<Setting name="ShowDisplayWindow">yes</Setting>
		<Setting name="ShowExtensions">yes</Setting>
		<Setting name="ShowFilePreviews">yes</Setting>
		<Setting name="ShowFolders">yes</Setting>
		<Setting name="ShowFolderSizes">no</Setting>
		<Setting name="ShowFriendlyDates">yes</Setting>
		<Setting name="ShowFullTitlePath">no</Setting>
		<Setting name="ShowGridlinesGlobal">yes</Setting>
		<Setting name="ShowHiddenGlobal">yes</Setting>
		<Setting name="ShowInfoTips">yes</Setting>
		<Setting name="ShowInGroupsGlobal">no</Setting>
		<Setting name="ShowPrivilegeLevelInTitleBar">no</Setting>
		<Setting name="ShowStatusBar">yes</Setting>
		<Setting name="ShowTabBarAtBottom">no</Setting>
		<Setting name="ShowTaskbarThumbnails">yes</Setting>
		<Setting name="ShowToolbar">yes</Setting>
		<Setting name="ShowUserNameTitleBar">no</Setting>
		<Setting name="SizeDisplayFormat">1</Setting>
		<Setting name="SortAscendingGlobal">yes</Setting>
		<Setting name="StartupMode">1</Setting>
		<Setting name="SynchronizeTreeview">yes</Setting>
		<Setting name="TVAutoExpandSelected">no</Setting>
		<Setting name="UseFullRowSelect">no</Setting>
		<Setting name="IconTheme">0</Setting>
		<Setting name="ToolbarState" Button0="Back" Button1="Forward" Button2="Up" Button3="Separator" Button4="Folders" Button5="Separator" Button6="Cut" Button7="Copy" Button8="Paste" Button9="Delete" Button10="Delete Permanently" Button11="Properties" Button12="Search" Button13="Separator" Button14="New Folder" Button15="Copy To" Button16="Move To" Button17="Separator" Button18="Views" Button19="Open Command Prompt" Button20="Refresh" Button21="Separator" Button22="Bookmark the current tab" Button23="Organize Bookmarks"/>
		<Setting name="TreeViewDelayEnabled">no</Setting>
		<Setting name="TreeViewWidth">208</Setting>
		<Setting name="ViewModeGlobal">1</Setting>
	</Settings>
	<WindowPosition>
		<Setting name="Position" Flags="0" ShowCmd="1" MinPositionX="0" MinPositionY="0" MaxPositionX="-1" MaxPositionY="-1" NormalPositionLeft="68" NormalPositionTop="64" NormalPositionRight="3368" NormalPositionBottom="1113"/>
	</WindowPosition>
	<Tabs>
		<Tab name="0" Directory="::{20D04FE0-3AEA-1069-A2D8-08002B30309D}" ApplyFilter="no" AutoArrange="yes" Filter="" FilterCaseSensitive="no" ShowHidden="yes" ShowInGroups="no" SortAscending="yes" SortMode="1" ViewMode="1" Locked="no" AddressLocked="no" UseCustomName="no" CustomName="">
			<Columns>
				<Column name="Generic" Name="yes" Name_Width="150" Type="yes" Type_Width="150" Size="yes" Size_Width="150" DateModified="yes" DateModified_Width="150" Attributes="no" Attributes_Width="150" SizeOnDisk="no" SizeOnDisk_Width="150" ShortName="no" ShortName_Width="150" Owner="no" Owner_Width="150" ProductName="no" ProductName_Width="150" Company="no" Company_Width="150" Description="no" Description_Width="150" FileVersion="no" FileVersion_Width="150" ProductVersion="no" ProductVersion_Width="150" ShortcutTo="no" ShortcutTo_Width="150" HardLinks="no" HardLinks_Width="150" Extension="no" Extension_Width="150" Created="no" Created_Width="150" Accessed="no" Accessed_Width="150" Title="no" Title_Width="150" Subject="no" Subject_Width="150" Author="no" Author_Width="150" Keywords="no" Keywords_Width="150" Comment="no" Comment_Width="150" CameraModel="no" CameraModel_Width="150" DateTaken="no" DateTaken_Width="150" Width="no" Width_Width="150" Height="no" Height_Width="150" MediaBitrate="no" MediaBitrate_Width="150" MediaCopyright="no" MediaCopyright_Width="150" MediaDuration="no" MediaDuration_Width="150" MediaProtected="no" MediaProtected_Width="150" MediaRating="no" MediaRating_Width="150" MediaAlbumArtist="no" MediaAlbumArtist_Width="150" MediaAlbum="no" MediaAlbum_Width="150" MediaBeatsPerMinute="no" MediaBeatsPerMinute_Width="150" MediaComposer="no" MediaComposer_Width="150" MediaConductor="no" MediaConductor_Width="150" MediaDirector="no" MediaDirector_Width="150" MediaGenre="no" MediaGenre_Width="150" MediaLanguage="no" MediaLanguage_Width="150" MediaBroadcastDate="no" MediaBroadcastDate_Width="150" MediaChannel="no" MediaChannel_Width="150" MediaStationName="no" MediaStationName_Width="150" MediaMood="no" MediaMood_Width="150" MediaParentalRating="no" MediaParentalRating_Width="150" MediaParentalRatingReason="no" MediaParentalRatingReason_Width="150" MediaPeriod="no" MediaPeriod_Width="150" MediaProducer="no" MediaProducer_Width="150" MediaPublisher="no" MediaPublisher_Width="150" MediaWriter="no" MediaWriter_Width="150" MediaYear="no" MediaYear_Width="150"/>
				<Column name="MyComputer" Name="yes" Name_Width="150" Type="yes" Type_Width="150" TotalSize="yes" TotalSize_Width="150" FreeSpace="yes" FreeSpace_Width="150" VirtualComments="no" VirtualComments_Width="150" FileSystem="no" FileSystem_Width="150"/>
				<Column name="ControlPanel" Name="yes" Name_Width="150" VirtualComments="yes" VirtualComments_Width="150"/>
				<Column name="RecycleBin" Name="yes" Name_Width="150" OriginalLocation="yes" OriginalLocation_Width="150" DateDeleted="yes" DateDeleted_Width="150" Size="yes" Size_Width="150" Type="yes" Type_Width="150" DateModified="yes" DateModified_Width="150"/>
				<Column name="Printers" Name="yes" Name_Width="150" Documents="yes" Documents_Width="150" Status="yes" Status_Width="150" PrinterComments="yes" PrinterComments_Width="150" PrinterLocation="yes" PrinterLocation_Width="150" PrinterModel="yes" PrinterModel_Width="150"/>
				<Column name="Network" Name="yes" Name_Width="150" Type="yes" Type_Width="150" NetworkAdaptorStatus="yes" NetworkAdaptorStatus_Width="150" Owner="yes" Owner_Width="150"/>
				<Column name="NetworkPlaces" Name="yes" Name_Width="150" VirtualComments="yes" VirtualComments_Width="150"/>
			</Columns>
		</Tab>
	</Tabs>
	<DefaultColumns>
		<Column name="Generic" Name="yes" Name_Width="150" Type="yes" Type_Width="150" Size="yes" Size_Width="150" DateModified="yes" DateModified_Width="150" Attributes="no" Attributes_Width="150" SizeOnDisk="no" SizeOnDisk_Width="150" ShortName="no" ShortName_Width="150" Owner="no" Owner_Width="150" ProductName="no" ProductName_Width="150" Company="no" Company_Width="150" Description="no" Description_Width="150" FileVersion="no" FileVersion_Width="150" ProductVersion="no" ProductVersion_Width="150" ShortcutTo="no" ShortcutTo_Width="150" HardLinks="no" HardLinks_Width="150" Extension="no" Extension_Width="150" Created="no" Created_Width="150" Accessed="no" Accessed_Width="150" Title="no" Title_Width="150" Subject="no" Subject_Width="150" Author="no" Author_Width="150" Keywords="no" Keywords_Width="150" Comment="no" Comment_Width="150" CameraModel="no" CameraModel_Width="150" DateTaken="no" DateTaken_Width="150" Width="no" Width_Width="150" Height="no" Height_Width="150" MediaBitrate="no" MediaBitrate_Width="150" MediaCopyright="no" MediaCopyright_Width="150" MediaDuration="no" MediaDuration_Width="150" MediaProtected="no" MediaProtected_Width="150" MediaRating="no" MediaRating_Width="150" MediaAlbumArtist="no" MediaAlbumArtist_Width="150" MediaAlbum="no" MediaAlbum_Width="150" MediaBeatsPerMinute="no" MediaBeatsPerMinute_Width="150" MediaComposer="no" MediaComposer_Width="150" MediaConductor="no" MediaConductor_Width="150" MediaDirector="no" MediaDirector_Width="150" MediaGenre="no" MediaGenre_Width="150" MediaLanguage="no" MediaLanguage_Width="150" MediaBroadcastDate="no" MediaBroadcastDate_Width="150" MediaChannel="no" MediaChannel_Width="150" MediaStationName="no" MediaStationName_Width="150" MediaMood="no" MediaMood_Width="150" MediaParentalRating="no" MediaParentalRating_Width="150" MediaParentalRatingReason="no" MediaParentalRatingReason_Width="150" MediaPeriod="no" MediaPeriod_Width="150" MediaProducer="no" MediaProducer_Width="150" MediaPublisher="no" MediaPublisher_Width="150" MediaWriter="no" MediaWriter_Width="150" MediaYear="no" MediaYear_Width="150"/>
		<Column name="MyComputer" Name="yes" Name_Width="150" Type="yes" Type_Width="150" TotalSize="yes" TotalSize_Width="150" FreeSpace="yes" FreeSpace_Width="150" VirtualComments="no" VirtualComments_Width="150" FileSystem="no" FileSystem_Width="150"/>
		<Column name="ControlPanel" Name="yes" Name_Width="150" VirtualComments="yes" VirtualComments_Width="150"/>
		<Column name="RecycleBin" Name="yes" Name_Width="150" OriginalLocation="yes" OriginalLocation_Width="150" DateDeleted="yes" DateDeleted_Width="150" Size="yes" Size_Width="150" Type="yes" Type_Width="150" DateModified="yes" DateModified_Width="150"/>
		<Column name="Printers" Name="yes" Name_Width="150" Documents="yes" Documents_Width="150" Status="yes" Status_Width="150" PrinterComments="yes" PrinterComments_Width="150" PrinterLocation="yes" PrinterLocation_Width="150" PrinterModel="yes" PrinterModel_Width="150"/>
		<Column name="Network" Name="yes" Name_Width="150" Type="yes" Type_Width="150" NetworkAdaptorStatus="yes" NetworkAdaptorStatus_Width="150" Owner="yes" Owner_Width="150"/>
		<Column name="NetworkPlaces" Name="yes" Name_Width="150" VirtualComments="yes" VirtualComments_Width="150"/>
	</DefaultColumns>
	<Bookmarksv2>
		<PermanentItem name="BookmarksToolbar" DateCreatedLow="1671045276" DateCreatedHigh="31227119" DateModifiedLow="1671045276" DateModifiedHigh="31227119">
		</PermanentItem>
		<PermanentItem name="BookmarksMenu" DateCreatedLow="1671045276" DateCreatedHigh="31227119" DateModifiedLow="1671045276" DateModifiedHigh="31227119">
		</PermanentItem>
		<PermanentItem name="OtherBookmarks" DateCreatedLow="1671045276" DateCreatedHigh="31227119" DateModifiedLow="1671045276" DateModifiedHigh="31227119">
		</PermanentItem>
	</Bookmarksv2>
	<ApplicationToolbar>
		<ApplicationButton name="Notepad" Command="C:\Windows\System32\notepad.exe" ShowNameOnToolbar="yes"/>
		<ApplicationButton name="Notepad++" Command="&quot;C:\Program Files\Notepad++\notepad++.exe&quot;" ShowNameOnToolbar="yes"/>
	</ApplicationToolbar>
	<Toolbars>
		<Toolbar name="0" id="0" Style="769" Length="604"/>
		<Toolbar name="1" id="1" Style="257" Length="0"/>
		<Toolbar name="2" id="2" Style="769" Length="0"/>
		<Toolbar name="3" id="3" Style="769" Length="84"/>
		<Toolbar name="4" id="4" Style="777" Length="0"/>
	</Toolbars>
	<ColorRules>
		<ColorRule name="Compressed files" FilenamePattern="" CaseInsensitive="no" Attributes="2048" r="0" g="0" b="255"/>
		<ColorRule name="Encrypted files" FilenamePattern="" CaseInsensitive="no" Attributes="16384" r="0" g="128" b="0"/>
	</ColorRules>
	<State>
	</State>
</ExplorerPlusPlus>
'@

    # -----------------------------
    # Load or create config.xml
    # -----------------------------
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Write-Host "[*] Explorer++ config.xml not found. Creating default at: $configPath"
        $defaultConfig | Out-File -FilePath $configPath -Encoding UTF8
    } else {
        Write-Host "[*] Found Explorer++ config.xml: $configPath"
    }

    # Load XML
    try {
        $xmlfile = [xml](Get-Content -LiteralPath $configPath)
    } catch {
        Write-Host "[-] Failed to read XML at $configPath"
        Write-Host "    $($_.Exception.Message)"
        exit
    }

    # -----------------------------
    # Ensure Settings/ShowBookmarksToolbar=yes
    # -----------------------------
    $settingsNode = $xmlfile.SelectSingleNode("/ExplorerPlusPlus/Settings")
    if (-not $settingsNode) {
        $settingsNode = $xmlfile.CreateElement("Settings")
        [void]$xmlfile.ExplorerPlusPlus.AppendChild($settingsNode)
    }

    $showBm = $xmlfile.SelectSingleNode("/ExplorerPlusPlus/Settings/Setting[@name='ShowBookmarksToolbar']")
    if (-not $showBm) {
        $showBm = $xmlfile.CreateElement("Setting")
        [void]$showBm.SetAttribute("name", "ShowBookmarksToolbar")
        $showBm.InnerText = "yes"
        [void]$settingsNode.AppendChild($showBm)
        Write-Host "[*] Added Setting ShowBookmarksToolbar=yes"
    } else {
        if ($showBm.InnerText -ne "yes") {
            $showBm.InnerText = "yes"
            Write-Host "[*] Updated Setting ShowBookmarksToolbar=yes"
        }
    }

    # -----------------------------
    # Ensure Bookmarksv2 + BookmarksToolbar node exists
    # -----------------------------
    $bmRoot = $xmlfile.SelectSingleNode("/ExplorerPlusPlus/Bookmarksv2")
    if (-not $bmRoot) {
        $bmRoot = $xmlfile.CreateElement("Bookmarksv2")
        [void]$xmlfile.ExplorerPlusPlus.AppendChild($bmRoot)
    }

    $toolbarNode = $xmlfile.SelectSingleNode("/ExplorerPlusPlus/Bookmarksv2/PermanentItem[@name='BookmarksToolbar']")
    if (-not $toolbarNode) {
        $toolbarNode = $xmlfile.CreateElement("PermanentItem")
        [void]$toolbarNode.SetAttribute("name", "BookmarksToolbar")
        # Minimal timestamps (Explorer++ seems fine with any ints; keeping your style)
        [void]$toolbarNode.SetAttribute("DateCreatedLow", "3561811627")
        [void]$toolbarNode.SetAttribute("DateCreatedHigh", "3561811627")
        [void]$toolbarNode.SetAttribute("DateModifiedLow", "3561811627")
        [void]$toolbarNode.SetAttribute("DateModifiedHigh", "3561811627")
        [void]$bmRoot.AppendChild($toolbarNode)
        Write-Host "[*] Created BookmarksToolbar container"
    }

    # -----------------------------
    # Delete existing bookmarks ONLY under BookmarksToolbar
    # -----------------------------
    Write-Host "[*] Deleting existing bookmarks in BookmarksToolbar"
    $existing = $toolbarNode.SelectNodes("./Bookmark")
    foreach ($node in @($existing)) {
        [void]$toolbarNode.RemoveChild($node)
    }

    # -----------------------------
    # Add new bookmarks grouped by host
    # -----------------------------
    $counteruncstats = 0
    $counterhosts    = 0

    # We'll keep folder "name" indexes stable per host, and bookmark "name" indexes per folder
    $hostFolders = @{}  # server => folderNode
    $hostCounters = @{} # server => nextBookmarkIndex

    foreach ($element in $objects.unc) {

        if ([string]::IsNullOrWhiteSpace($element)) { continue }

        # Isolate Server: \\server\share\...
        $server = $null
        if ($element -match '^\\\\([^\\]+)\\') {
            $server = $Matches[1]
        } else {
            # If it's not a UNC, just bucket it under "(local/other)"
            $server = "(other)"
        }

        if (-not $hostFolders.ContainsKey($server)) {
            # Create folder bookmark (Type=0) under BookmarksToolbar
            $folder = $xmlfile.CreateElement("Bookmark")
            [void]$folder.SetAttribute("name", [string]$counterhosts)
            [void]$folder.SetAttribute("Type", "0")
            [void]$folder.SetAttribute("GUID", ([guid]::NewGuid().ToString()))
            [void]$folder.SetAttribute("ItemName", $server)
            [void]$folder.SetAttribute("DateCreatedLow", "3561811627")
            [void]$folder.SetAttribute("DateCreatedHigh", "3561811627")
            [void]$folder.SetAttribute("DateModifiedLow", "3561811627")
            [void]$folder.SetAttribute("DateModifiedHigh", "3561811627")

            [void]$toolbarNode.AppendChild($folder)

            $hostFolders[$server]  = $folder
            $hostCounters[$server] = 0
            $counterhosts++
        }

        # Add the actual bookmark (Type=1) inside the server folder
        $folderNode = $hostFolders[$server]
        $idx = [int]$hostCounters[$server]

        $bm = $xmlfile.CreateElement("Bookmark")
        [void]$bm.SetAttribute("name", [string]$idx)
        [void]$bm.SetAttribute("Type", "1")
        [void]$bm.SetAttribute("GUID", ([guid]::NewGuid().ToString()))
        [void]$bm.SetAttribute("ItemName", $element)
        [void]$bm.SetAttribute("Location", $element)
        [void]$bm.SetAttribute("DateCreatedLow", "3561811627")
        [void]$bm.SetAttribute("DateCreatedHigh", "3561811627")
        [void]$bm.SetAttribute("DateModifiedLow", "3561811627")
        [void]$bm.SetAttribute("DateModifiedHigh", "3561811627")

        [void]$folderNode.AppendChild($bm)

        $hostCounters[$server] = $idx + 1
        $counteruncstats++
    }

    # -----------------------------
    # Save
    # -----------------------------
    try {
        $xmlfile.Save($configPath)
        Write-Host "[+] Added $counterhosts bookmark-folders with $counteruncstats bookmarks"
        Write-Host "[+] Saved: $configPath"
    } catch {
        Write-Host "[-] Failed to save XML: $($_.Exception.Message)"
        exit
    }
}


# Function to export as CSV
function exportcsv($object ,$name){
	write-host "[*] Storing: $($outputname)_loot_$($name).csv"
	$object | select-object severity,rule,keyword,modified,extension,unc,content | Export-Csv -Path "$($outputname)_loot_$($name).csv" -NoTypeInformation
}

# Function to export as TXT
function exporttxt($object ,$name){
	write-host "[*] Storing: $($outputname)_loot_$($name).txt"
	$object | Format-Table severity,rule,keyword,modified,extension,unc,content -AutoSize | Out-String -Width 10000 | Out-File -FilePath "$($outputname)_loot_$($name).txt"
}

# Function to export as JSON
function exportjson($object ,$name){
	write-host "[*] Storing: $($outputname)_loot_$($name).json"
	$object | select-object severity,rule,keyword,modified,extension,unc,content | ConvertTo-Json -depth 50  | Out-File -FilePath "$($outputname)_loot_$($name).json"
}

# Function to export as HTML
function exporthtml($object ,$name){

# ---------------- JS: data-driven table with pagination ----------------
$Header = @'
<meta charset="utf-8">
<script>
  document.addEventListener("DOMContentLoaded", () => {
    // ----------------------------
    // Data bootstrap
    // ----------------------------
    const dataEl = document.getElementById("loot-data");
    if (!dataEl) {
      console.error("loot-data element not found");
      return;
    }
    const data = JSON.parse(dataEl.textContent);

    // ----------------------------
    // Report identity + storage keys
    // ----------------------------
    function getReportSha256() {
      const el = document.getElementById("report-sha256");
      const sha = (el ? el.textContent : "").trim();
      return sha || "";
    }

    function getCurrentFileName() {
      const path = window.location.pathname;
      return path.substring(path.lastIndexOf("/") + 1);
    }

    function getProgressKey() {
      const sha = getReportSha256();
      return sha
        ? `snaffler_progress::sha256::${sha}`
        : `snaffler_progress::file::${getCurrentFileName()}`;
    }

    // ----------------------------
    // Column visibility
    // ----------------------------
    const COLS = [
      { key: "check", label: "\u2605 (flagged)" },
      { key: "done", label: "\u2713 (done)" },
      { key: "severity", label: "Severity" },
      { key: "rule", label: "Rule" },
      { key: "keyword", label: "Keyword" },
      { key: "modified", label: "Modified" },
      { key: "unc", label: "UNC" },
      { key: "extension", label: "Extensions" },
      { key: "actions", label: "Actions" },
      { key: "content", label: "Content" }
    ];

    function getColsKey() {
      const sha = getReportSha256();
      return sha ? `snaffler_cols::${sha}` : `snaffler_cols::${getCurrentFileName()}`;
    }

    let visibleCols = new Set(COLS.map(c => c.key)); // default: all

    function loadCols() {
      try {
        const raw = localStorage.getItem(getColsKey());
        if (!raw) return;
        const arr = JSON.parse(raw);
        if (Array.isArray(arr) && arr.length) visibleCols = new Set(arr);
      } catch {}
    }

    function saveCols() {
      try {
        localStorage.setItem(getColsKey(), JSON.stringify(Array.from(visibleCols)));
      } catch {}
    }

    function applyColsToTable() {
      const t = document.getElementById("loot-table");
      if (!t) return;

      // remove any previous hide-col-* classes
      t.className = t.className
        .split(/\s+/)
        .filter(c => c && !c.startsWith("hide-col-"))
        .join(" ");

      // add hide classes for columns NOT in visibleCols
      for (const c of COLS) {
        if (!visibleCols.has(c.key)) t.classList.add(`hide-col-${c.key}`);
      }
    }

    // ----------------------------
    // Progress persistence (check/done)
    // ----------------------------
    let progressSaveTimer = null;

    function loadProgressFromLocalStorage() {
      try {
        const raw = localStorage.getItem(getProgressKey());
        if (!raw) return;

        const saved = JSON.parse(raw);
        // saved.items is array of { i, c, d } where i = row index
        if (!saved || !Array.isArray(saved.items)) return;

        for (const it of saved.items) {
          const i = it.i;
          if (!Number.isInteger(i) || i < 0 || i >= data.length) continue;
          data[i].check = !!it.c;
          data[i].done = !!it.d;
        }
      } catch (e) {
        console.warn("Failed to load progress:", e);
      }
    }

    function saveProgressToLocalStorageDebounced() {
      clearTimeout(progressSaveTimer);
      progressSaveTimer = setTimeout(() => {
        try {
          // store only rows that have check or done = true (keeps storage small)
          const items = [];
          for (let i = 0; i < data.length; i++) {
            const r = data[i];
            if (r.check || r.done) items.push({ i, c: r.check ? 1 : 0, d: r.done ? 1 : 0 });
          }
          localStorage.setItem(getProgressKey(), JSON.stringify({ v: 1, items }));
        } catch (e) {
          console.warn("Failed to save progress:", e);
        }
      }, 150);
    }

    function resetProgressEverywhere() {
      // clear memory
      for (let i = 0; i < data.length; i++) {
        data[i].check = false;
        data[i].done = false;
      }

      // clear storage
      try { localStorage.removeItem(getProgressKey()); } catch {}

      // refresh UI
      page = 1;
      applyAll();
    }

    // ----------------------------
    // Small UI helpers
    // ----------------------------
    function flashCopied(btn) {
      if (!btn) return;

      const ico = btn.querySelector(".ico");
      if (!ico) return;

      if (!btn.dataset.orig) btn.dataset.orig = ico.textContent;

      ico.textContent = "\u2705";
      btn.classList.add("copied", "show-tip");

      clearTimeout(btn._copiedTimer);
      btn._copiedTimer = setTimeout(() => {
        ico.textContent = btn.dataset.orig;
        btn.classList.remove("copied", "show-tip");
      }, 800);
    }

    // faster compares than localeCompare on every call
    const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

    function toTime(s) {
      if (!s) return 0;
      const iso = String(s).replace(" ", "T");
      const t = Date.parse(iso);
      return Number.isFinite(t) ? t : 0;
    }

    // ----------------------------
    // State
    // ----------------------------
    const severityOrder = { Black: 0, Red: 1, Yellow: 2, Green: 3 };

    let sortCol = "modified";
    let sortDir = "desc"; // default for modified
    let severityPrimary = true; // default on load

    let page = 1;
    let pageSize = parseInt(document.getElementById("pageSize").value, 10);
    let searchQ = "";
    let searchTimer = null;
    let actionsWired = false;

    // Filters
    let selectedSeverities = new Set(["Black", "Red", "Yellow", "Green"]);
    let selectedYears = null; // Set, built from data
    let selectedExtensions = null; // Set, built from data
    let filterCheckOnly = false;
    let filterHideDone = false;

    const DEFAULT_SEVERITIES = ["Black", "Red", "Yellow", "Green"];
    let view = []; // indexes into data[]


    // ----------------------------
    // Readable content toggle
    // ----------------------------
    const READABLE_KEY = (() => {
      const sha = getReportSha256();
      return sha ? `snaffler_readable::${sha}` : `snaffler_readable::${getCurrentFileName()}`;
    })();

    let readableMode = false;


    // ----------------------------
    // Theme
    // ----------------------------
    const THEME_KEY = "snaffler_theme";

    function applyTheme(theme) {
      const t = (theme === "light") ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", t);
      localStorage.setItem(THEME_KEY, t);

      // update button label if it exists
      const btn = document.getElementById("theme-toggle");
      if (btn) btn.textContent = (t === "dark") ? "Light mode" : "Dark mode";
    }

    function initTheme() {
      const saved = localStorage.getItem(THEME_KEY);
      applyTheme(saved || "dark");
    }

    // ----------------------------
    // Data helpers
    // ----------------------------
    function getYear(modified) {
      const s = String(modified ?? "");
      const m = s.match(/(19|20)\d{2}/);
      return m ? m[0] : "(unknown)";
    }

    function normSeverity(s) {
      const x = String(s ?? "").trim().toLowerCase();
      if (x === "black") return "Black";
      if (x === "red") return "Red";
      if (x === "yellow") return "Yellow";
      if (x === "green") return "Green";
      return "";
    }

    function escapeHtml(s) {
      return String(s ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
    }

    function applyReadableMode(on) {
      readableMode = !!on;
      document.documentElement.classList.toggle("readable-on", readableMode);

      const btn = document.getElementById("toggle-readable");
      if (btn) btn.textContent = readableMode ? "Unescape: ON" : "Unescape: OFF";

      try { localStorage.setItem(READABLE_KEY, readableMode ? "1" : "0"); } catch {}
    }

    function initReadableMode() {
      try {
        const raw = localStorage.getItem(READABLE_KEY);
        applyReadableMode(raw === "1");
      } catch {
        applyReadableMode(false);
      }
    }

    // Function to unescape snaffler preview text
    function makeReadablePreviewText(input) {
      let s = String(input ?? "");
      if (!s) return "";

      // 1) Normalize PowerShell line-continuation + escaped newline: `\r\n  -> \n
      s = s.replace(/`\r\n/g, "\n");

      // 2) Convert escaped newlines into real newlines
      s = s.replace(/\\r\\n/g, "\n");
      s = s.replace(/\\n/g, "\n");

      // 3) Convert escaped tabs to real tabs
      s = s.replace(/\\t/g, "\t");

      // 4) Convert escaped spaces "\ " to real spaces
      s = s.replace(/\\ /g, " ");

      // unescape common "backslash-escaped" punctuation: \$ \. \{ \} \( \) etc.
      s = s.replace(/\\([#$.{},()[\]|+*?^=!<>:;'"`-])/g, "$1");

      // unescape double-backslashes to single backslash (\\ -> \)
      s = s.replace(/\\\\/g, "\\");

      // 5) Merge multiple newlines into a single newline
      s = s.replace(/\n{2,}/g, "\n");

      return s;
    }

    
    function highlightKeyword(content, keyword) {
      const safe = escapeHtml(content);
      if (!keyword) return safe;
      const k = String(keyword).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp(`(${k})`, "gi");
      return safe.replace(re, `<span style="color:red;">$1</span>`);
    }

    function highlightSearchEscaped(escapedText, query) {
      // escapedText MUST already be escaped via escapeHtml()
      const q = String(query || "").trim();
      if (!q) return escapedText;

      const tokens = q.toLowerCase().split(/\s+/).filter(t => t.length >= 2);
      if (!tokens.length) return escapedText;

      let out = escapedText;
      for (const tok of tokens) {
        const re = new RegExp(`(${tok.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi");
        out = out.replace(re, `<mark class="hit">$1</mark>`);
      }
      return out;
    }

    function parentOfUNC(unc) {
      if (!unc) return "";
      const p = unc.lastIndexOf("\\");
      return p > 1 ? unc.slice(0, p) : unc;
    }

    // ----------------------------
    // Actions column + clipboard helpers
    // ----------------------------
    function fallbackCopy(text) {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed";
      ta.style.top = "-9999px";
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand("copy"); } catch {}
      document.body.removeChild(ta);
    }

    function copyToClipboard(text) {
      const t = String(text || "");
      if (!t) return;

      // Modern clipboard API (works in secure contexts; file:// may vary)
      if (navigator.clipboard) {
        navigator.clipboard.writeText(t).catch(() => fallbackCopy(t));
      } else {
        fallbackCopy(t);
      }
    }

    function openLink(unc) {
      const parent = parentOfUNC(unc).replaceAll(" ", "%20");
      return `<a class="act act-open"
                target="_blank"
                href="file://${parent}/"
                title="Open folder"
                aria-label="Open folder">
                &#x1F4C2;
              </a>`;
    }

    function saveLink(unc) {
      const u = (unc || "").replaceAll(" ", "%20");
      return `<a class="act act-save"
                target="_blank"
                href="file://${u}"
                download
                title="Save file"
                aria-label="Save file">
                &#x1F4BE;
              </a>`;
    }

    function actionsHtml(unc) {
      const u = String(unc || "");
      const parent = parentOfUNC(u);

      const uAttr = escapeHtml(u);
      const pAttr = escapeHtml(parent);

      return `
        <div class="row-actions" data-unc="${uAttr}" data-parent="${pAttr}">
          <button class="act act-copy-unc" type="button" title="Copy UNC">
            <span class="ico">&#x1F4CB;</span><span class="tip">Copied</span>
          </button>
          <button class="act act-copy-parent" type="button" title="Copy parent UNC">
            <span class="ico">&#x1F4DD;</span><span class="tip">Copied</span>
          </button>
          ${openLink(u)}
          ${saveLink(u)}
        </div>
      `;
    }

    function colorSeverityVisible() {
      document.querySelectorAll("#loot-body tr td:nth-child(3)").forEach(td => {
        // ALWAYS reset first
        td.style.backgroundColor = "";
        td.style.color = "";

        const sev = td.textContent.trim();
        switch (sev) {
          case "Black":
            td.style.backgroundColor = "#333";
            td.style.color = "white";
            break;
          case "Red":
            td.style.backgroundColor = "#d9534f";
            td.style.color = "white";
            break;
          case "Yellow":
            td.style.backgroundColor = "#CFAD01";
            td.style.color = "white";
            break;
          case "Green":
            td.style.backgroundColor = "#79C55B";
            td.style.color = "white";
            break;
        }
      });
    }

    // ----------------------------
    // Save HTML (with embedded state)
    // ----------------------------
    function updateCheckboxAttributesForSave() {
      // Ensure current page checkboxes have checked attrs
      document.querySelectorAll("#loot-body input[type='checkbox']").forEach(cb => {
        if (cb.checked) cb.setAttribute("checked", "checked");
        else cb.removeAttribute("checked");
      });

      // IMPORTANT: write all checkbox states into JSON blob so saved HTML reloads state
      dataEl.textContent = JSON.stringify(data);
    }

    function saveStateToHTML() {
      updateCheckboxAttributesForSave();
      const html = document.documentElement.outerHTML;
      const blob = new Blob([html], { type: "text/html" });

      const currentFileName = getCurrentFileName();
      const newFileName = currentFileName.replace(/\.html$/, "") + "_save.html";

      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = newFileName;
      link.click();
    }

    // ----------------------------
    // Export current view to CSV
    // ----------------------------
    function csvEscape(v) {
      const s = String(v ?? "");
      // Always quote; escape quotes by doubling them
      return `"${s.replace(/"/g, '""')}"`;
    }

    function buildCsvFromRows(rows) {
      // Keep stable ordering, but only include visible columns
      const cols = COLS.filter(c => visibleCols.has(c.key));

      // Map column keys to row fields (actions is UI-only)
      const headers = cols
        .filter(c => c.key !== "actions")
        .map(c => c.key);

      let csv = headers.join(",") + "\r\n";

      for (const r of rows) {
        const line = headers.map(k => {
          if (k === "check") return csvEscape(r.check ? 1 : 0);
          if (k === "done") return csvEscape(r.done ? 1 : 0);
          return csvEscape(r[k]);
        }).join(",");
        csv += line + "\r\n";
      }
      return csv;
    }

    function exportCurrentViewToCsv() {
      // view[] contains indexes into data[] for the current filtered/sorted dataset
      const rows = view.map(i => data[i]);

      const csv = buildCsvFromRows(rows);
      const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });

      const currentFileName = getCurrentFileName();
      const base = currentFileName.replace(/\.html$/i, "");
      const outName = `${base}_filtered_${rows.length}.csv`;

      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = outName;
      a.click();

      // (optional) cleanup
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    }

    // ----------------------------
    // Columns modal
    // ----------------------------
    function wireColumnsUi() {
      const btn = document.getElementById("cols-btn");
      const modal = document.getElementById("cols-modal");
      const close = document.getElementById("cols-close");
      const list = document.getElementById("cols-list");
      const allBtn = document.getElementById("cols-all");
      const noneBtn = document.getElementById("cols-none");
      const applyBtn = document.getElementById("cols-apply");

      if (!btn || !modal || !close || !list || !allBtn || !noneBtn || !applyBtn) return;

      function open() {
        // rebuild list each time so it reflects current state
        list.innerHTML = "";
        for (const c of COLS) {
          const label = document.createElement("label");
          label.className = "filter-inline";

          const cb = document.createElement("input");
          cb.type = "checkbox";
          cb.value = c.key;
          cb.checked = visibleCols.has(c.key);

          cb.addEventListener("change", () => {
            if (cb.checked) visibleCols.add(c.key);
            else visibleCols.delete(c.key);
          });

          label.appendChild(cb);
          label.appendChild(document.createTextNode(c.label));
          list.appendChild(label);
        }

        modal.classList.add("open");
        modal.setAttribute("aria-hidden", "false");
      }

      function closeModal() {
        modal.classList.remove("open");
        modal.setAttribute("aria-hidden", "true");
      }

      btn.addEventListener("click", open);
      close.addEventListener("click", closeModal);
      modal.addEventListener("click", (e) => { if (e.target === modal) closeModal(); });
      document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeModal(); });

      allBtn.addEventListener("click", () => {
        visibleCols = new Set(COLS.map(c => c.key));
        open(); // re-render
      });

      noneBtn.addEventListener("click", () => {
        visibleCols = new Set(); // allow empty; table will look blank
        open(); // re-render
      });

      applyBtn.addEventListener("click", () => {
        saveCols();
        applyColsToTable();
        closeModal();
      });
    }

    // ----------------------------
    // Header wiring (buttons + modals)
    // ----------------------------
    function wireHeader() {
      const saveBtn = document.getElementById("save-html");
      if (saveBtn) saveBtn.addEventListener("click", saveStateToHTML);

      const exportCsvBtn = document.getElementById("export-csv");
      if (exportCsvBtn) exportCsvBtn.addEventListener("click", exportCurrentViewToCsv);

      const themeBtn = document.getElementById("theme-toggle");
      if (themeBtn) {
        themeBtn.addEventListener("click", () => {
          const current = document.documentElement.getAttribute("data-theme") || "dark";
          applyTheme(current === "dark" ? "light" : "dark");
        });
      }

      // Reset progress (localStorage + current session)
      const resetProgressBtn = document.getElementById("reset-progress");
      if (resetProgressBtn) {
        resetProgressBtn.addEventListener("click", () => {
          if (!confirm("Reset stored progress (\u2605 flagged / \u2713 reviewed) for this report?")) return;
          resetProgressEverywhere();
        });
      }

      // Toggle Readability
      const readableBtn = document.getElementById("toggle-readable");
      if (readableBtn) {
        readableBtn.addEventListener("click", () => {
          applyReadableMode(!readableMode);
          // recompute on render: just re-render the current page
          renderPage();
          updatePager();
        });
      }


      // Input Info modal
      const infoBtn = document.getElementById("show-input-info");
      const modal = document.getElementById("input-info-modal");
      const closeBtn = document.getElementById("modal-close");

      if (infoBtn && modal && closeBtn) {
        function openModal() {
          modal.classList.add("open");
          modal.setAttribute("aria-hidden", "false");
        }

        function closeModal() {
          modal.classList.remove("open");
          modal.setAttribute("aria-hidden", "true");
        }

        infoBtn.addEventListener("click", openModal);
        closeBtn.addEventListener("click", closeModal);

        modal.addEventListener("click", (e) => {
          if (e.target === modal) closeModal();
        });

        document.addEventListener("keydown", (e) => {
          if (e.key === "Escape") closeModal();
        });
      }
    }

    // ----------------------------
    // Filter UI (built from data)
    // ----------------------------
    function buildFilterMenu() {
      const filterMenu = document.getElementById("filter-menu");
      filterMenu.innerHTML = "";

      // Top bar: search + reset
      const topbar = document.createElement("div");
      topbar.className = "filter-topbar";

      const spacer = document.createElement("div");
      spacer.className = "spacer";

      const searchInput = document.createElement("input");
      searchInput.id = "q";
      searchInput.type = "text";
      searchInput.placeholder = "Search (unc / rule / keyword / content)...";

      const clearBtn = document.createElement("button");
      clearBtn.id = "clearSearch";
      clearBtn.textContent = "Clear";

      const resetBtn = document.createElement("button");
      resetBtn.id = "resetFilters";
      resetBtn.textContent = "Reset filters";

      topbar.appendChild(spacer);
      topbar.appendChild(searchInput);
      topbar.appendChild(clearBtn);
      topbar.appendChild(resetBtn);
      filterMenu.appendChild(topbar);

      // quick search wiring
      searchInput.addEventListener("input", () => {
        searchQ = searchInput.value.trim().toLowerCase();
        page = 1;
        clearTimeout(searchTimer);
        searchTimer = setTimeout(() => applyAll(), 350);
      });

      clearBtn.addEventListener("click", () => {
        searchInput.value = "";
        searchQ = "";
        page = 1;
        applyAll();
      });

      // Filter cards grid
      const grid = document.createElement("div");
      grid.className = "filter-grid";
      filterMenu.appendChild(grid);

      // Helper to create a collapsible card
      function makeCard(title, countText, openByDefault = true) {
        const d = document.createElement("details");
        d.className = "filter-card";
        if (openByDefault) d.open = true;

        const s = document.createElement("summary");
        s.textContent = title;

        const meta = document.createElement("span");
        meta.className = "meta";
        meta.textContent = countText || "";
        s.appendChild(meta);

        const body = document.createElement("div");
        body.style.marginTop = "8px";

        d.appendChild(s);
        d.appendChild(body);
        return { details: d, body, meta };
      }

      // Severity card
      const sevCard = makeCard("Severity", "", true);
      const sevList = document.createElement("div");
      sevList.className = "filter-list";

      ["Black", "Red", "Yellow", "Green"].forEach(sev => {
        const label = document.createElement("label");
        label.className = "filter-inline";

        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.value = sev;
        cb.checked = true;

        cb.addEventListener("change", () => {
          if (cb.checked) selectedSeverities.add(sev);
          else selectedSeverities.delete(sev);
          page = 1;
          applyAll();
          updateMetaCounts();
        });

        label.appendChild(cb);
        label.appendChild(document.createTextNode(sev));
        sevList.appendChild(label);
      });

      const sevActions = document.createElement("div");
      sevActions.className = "filter-actions-row";

      const sevAll = document.createElement("button");
      sevAll.textContent = "All";
      sevAll.addEventListener("click", () => {
        selectedSeverities = new Set(["Black", "Red", "Yellow", "Green"]);
        sevList.querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = true);
        page = 1;
        applyAll();
        updateMetaCounts();
      });

      const sevNone = document.createElement("button");
      sevNone.textContent = "None";
      sevNone.addEventListener("click", () => {
        selectedSeverities = new Set();
        sevList.querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = false);
        page = 1;
        applyAll();
        updateMetaCounts();
      });

      sevActions.appendChild(sevAll);
      sevActions.appendChild(sevNone);

      sevCard.body.appendChild(sevList);
      sevCard.body.appendChild(sevActions);
      grid.appendChild(sevCard.details);

      // Years card
      const yearSet = new Set();
      data.forEach(r => yearSet.add(getYear(r.modified)));

      const years = Array.from(yearSet).sort((a, b) => b.localeCompare(a));
      selectedYears = new Set(years);

      const yrCard = makeCard("Modified", years.length ? `${years.length} years` : "", true);
      const yrScroll = document.createElement("div");
      yrScroll.className = "filter-scroll";

      const yrList = document.createElement("div");
      yrList.className = "filter-list threecol";

      years.forEach(y => {
        const label = document.createElement("label");
        label.className = "filter-inline";

        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.className = "year-checkbox";
        cb.value = y;
        cb.checked = true;

        cb.addEventListener("change", () => {
          if (cb.checked) selectedYears.add(y);
          else selectedYears.delete(y);
          page = 1;
          applyAll();
          updateMetaCounts();
        });

        label.appendChild(cb);
        label.appendChild(document.createTextNode(y));
        yrList.appendChild(label);
      });

      yrScroll.appendChild(yrList);

      const yrActions = document.createElement("div");
      yrActions.className = "filter-actions-row";

      const yrAll = document.createElement("button");
      yrAll.textContent = "All";
      yrAll.addEventListener("click", () => {
        selectedYears = new Set(years);
        yrList.querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = true);
        page = 1;
        applyAll();
        updateMetaCounts();
      });

      const yrNone = document.createElement("button");
      yrNone.textContent = "None";
      yrNone.addEventListener("click", () => {
        selectedYears = new Set();
        yrList.querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = false);
        page = 1;
        applyAll();
        updateMetaCounts();
      });

      yrActions.appendChild(yrAll);
      yrActions.appendChild(yrNone);

      yrCard.body.appendChild(yrScroll);
      yrCard.body.appendChild(yrActions);
      grid.appendChild(yrCard.details);

      // Extensions card (scroll + mini-search)
      const extSet = new Set();
      data.forEach(r => {
        const e = (r.extension || "").toLowerCase().trim();
        extSet.add(e ? e : "(no ext)");
      });

      const exts = Array.from(extSet).sort((a, b) => a.localeCompare(b));
      selectedExtensions = new Set(exts);

      const extCard = makeCard("Extension", exts.length ? `${exts.length} types` : "", true);

      const extFilterInput = document.createElement("input");
      extFilterInput.className = "ext-search";
      extFilterInput.type = "text";
      extFilterInput.placeholder = "Filter extensions... (e.g. .ps1)";

      const extScroll = document.createElement("div");
      extScroll.className = "filter-scroll";

      const extList = document.createElement("div");
      extList.className = "filter-list threecol";

      function renderExtList(filterText = "") {
        extList.innerHTML = "";
        const ft = filterText.trim().toLowerCase();

        exts
          .filter(ext => !ft || ext.includes(ft))
          .forEach(ext => {
            const label = document.createElement("label");
            label.className = "filter-inline";

            const cb = document.createElement("input");
            cb.type = "checkbox";
            cb.className = "extension-checkbox";
            cb.value = ext;
            cb.checked = selectedExtensions.has(ext);

            cb.addEventListener("change", () => {
              if (cb.checked) selectedExtensions.add(ext);
              else selectedExtensions.delete(ext);
              page = 1;
              applyAll();
              updateMetaCounts();
            });

            label.appendChild(cb);
            label.appendChild(document.createTextNode(ext));
            extList.appendChild(label);
          });
      }

      renderExtList("");
      extFilterInput.addEventListener("input", () => renderExtList(extFilterInput.value));
      extScroll.appendChild(extList);

      const extActions = document.createElement("div");
      extActions.className = "filter-actions-row";

      const extAll = document.createElement("button");
      extAll.textContent = "All";
      extAll.addEventListener("click", () => {
        selectedExtensions = new Set(exts);
        renderExtList(extFilterInput.value);
        page = 1;
        applyAll();
        updateMetaCounts();
      });

      const extNone = document.createElement("button");
      extNone.textContent = "None";
      extNone.addEventListener("click", () => {
        selectedExtensions = new Set();
        renderExtList(extFilterInput.value);
        page = 1;
        applyAll();
        updateMetaCounts();
      });

      extActions.appendChild(extAll);
      extActions.appendChild(extNone);

      extCard.body.appendChild(extFilterInput);
      extCard.body.appendChild(extScroll);
      extCard.body.appendChild(extActions);
      grid.appendChild(extCard.details);

      // Status card (check/done filters)
      const statusCard = makeCard("Status", "", true);

      const statusList = document.createElement("div");
      statusList.className = "filter-list onecol";

      const checkOnlyLabel = document.createElement("label");
      checkOnlyLabel.className = "filter-inline";

      const checkOnlyCb = document.createElement("input");
      checkOnlyCb.type = "checkbox";
      checkOnlyCb.checked = filterCheckOnly;

      checkOnlyCb.addEventListener("change", () => {
        filterCheckOnly = checkOnlyCb.checked;
        page = 1;
        applyAll();
      });

      checkOnlyLabel.appendChild(checkOnlyCb);
      checkOnlyLabel.appendChild(document.createTextNode("Show \u2605 (flagged) only"));

      const hideDoneLabel = document.createElement("label");
      hideDoneLabel.className = "filter-inline";

      const hideDoneCb = document.createElement("input");
      hideDoneCb.type = "checkbox";
      hideDoneCb.checked = filterHideDone;

      hideDoneCb.addEventListener("change", () => {
        filterHideDone = hideDoneCb.checked;
        page = 1;
        applyAll();
      });

      hideDoneLabel.appendChild(hideDoneCb);
      hideDoneLabel.appendChild(document.createTextNode("Hide \u2713 (done)"));

      statusList.appendChild(checkOnlyLabel);
      statusList.appendChild(hideDoneLabel);

      statusCard.body.appendChild(statusList);
      grid.appendChild(statusCard.details);

      // Row count display
      const rowCountDisplay = document.createElement("div");
      rowCountDisplay.id = "row-count";
      rowCountDisplay.style.marginTop = "10px";
      rowCountDisplay.className = "filter-mini";
      filterMenu.appendChild(rowCountDisplay);

      // Meta counts (optional)
      function updateMetaCounts() {
        sevCard.meta.textContent = `${selectedSeverities.size}/4`;
        yrCard.meta.textContent = years.length ? `${selectedYears.size}/${years.length}` : "";
        extCard.meta.textContent = exts.length ? `${selectedExtensions.size}/${exts.length}` : "";
      }
      updateMetaCounts();

      // Reset filters button needs access to these built elements/arrays
      resetBtn.addEventListener("click", () => {
        searchInput.value = "";
        searchQ = "";

        selectedSeverities = new Set(DEFAULT_SEVERITIES);
        selectedYears = new Set(years);
        selectedExtensions = new Set(exts);
        filterCheckOnly = false;
        filterHideDone = false;

        sevList.querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = true);
        yrList.querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = true);

        extFilterInput.value = "";
        renderExtList("");
        extList.querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = true);

        checkOnlyCb.checked = false;
        hideDoneCb.checked = false;

        page = 1;
        applyAll();
        updateMetaCounts();
      });
    }

    // ----------------------------
    // Filtering + sorting (build view[])
    // ----------------------------
    function applyAll() {
      view = [];

      for (let i = 0; i < data.length; i++) {
        const r = data[i];

        if (!selectedSeverities.has(r.severity)) continue;

        if (selectedYears) {
          const y = getYear(r.modified);
          if (!selectedYears.has(y)) continue;
        }

        if (selectedExtensions) {
          const e = (r.extension || "").toLowerCase().trim();
          const key = e ? e : "(no ext)";
          if (!selectedExtensions.has(key)) continue;
        }

        if (filterCheckOnly && !r.check) continue;
        if (filterHideDone && r.done) continue;

        if (searchQ) {
          const hay = `${r.unc || ""} ${r.rule || ""} ${r.keyword || ""} ${r.content || ""}`.toLowerCase();
          if (!hay.includes(searchQ)) continue;
        }

        view.push(i);
      }

      view.sort((ia, ib) => {
        const a = data[ia], b = data[ib];

        const sa = severityOrder[normSeverity(a.severity)] ?? 999;
        const sb = severityOrder[normSeverity(b.severity)] ?? 999;

        if (severityPrimary) {
          if (sa !== sb) return sa - sb;

          if (sortCol === "modified") {
            const ta = toTime(a.modified), tb = toTime(b.modified);
            return (sortDir === "asc") ? (ta - tb) : (tb - ta);
          }

          if (sortCol === "check" || sortCol === "done") {
            const va = !!a[sortCol], vb = !!b[sortCol];
            if (va === vb) return 0;
            return (sortDir === "asc") ? (va ? -1 : 1) : (va ? 1 : -1);
          }

          const va = (a[sortCol] ?? "").toString();
          const vb = (b[sortCol] ?? "").toString();
          const cmp = collator.compare(va, vb);
          return (sortDir === "asc") ? cmp : -cmp;
        }

        // global sort mode
        if (sortCol === "check" || sortCol === "done") {
          const va = !!a[sortCol], vb = !!b[sortCol];
          if (va !== vb) return (sortDir === "asc") ? (va ? -1 : 1) : (va ? 1 : -1);
        } else if (sortCol === "modified") {
          const ta = toTime(a.modified), tb = toTime(b.modified);
          if (ta !== tb) return (sortDir === "asc") ? (ta - tb) : (tb - ta);
        } else if (sortCol === "severity") {
          if (sa !== sb) return (sortDir === "asc") ? (sa - sb) : (sb - sa);
        } else {
          const va = (a[sortCol] ?? "").toString();
          const vb = (b[sortCol] ?? "").toString();
          const cmp = collator.compare(va, vb);
          if (cmp !== 0) return (sortDir === "asc") ? cmp : -cmp;
        }

        if (sa !== sb) return sa - sb;
        return toTime(b.modified) - toTime(a.modified);
      });

      const totalPages = Math.max(1, Math.ceil(view.length / pageSize));
      page = Math.min(Math.max(page, 1), totalPages);

      renderPage();
      updatePager();
      updateRowCount();
    }

    // ----------------------------
    // Render current page
    // ----------------------------
    function renderPage() {
      const tbody = document.getElementById("loot-body");
      tbody.innerHTML = "";

      const start = (page - 1) * pageSize;
      const end = Math.min(view.length, start + pageSize);

      const frag = document.createDocumentFragment();

      for (let k = start; k < end; k++) {
        const idx = view[k];
        const r = data[idx];

        const sevHtml = escapeHtml(r.severity);
        const ruleHtml = highlightSearchEscaped(escapeHtml(r.rule), searchQ);
        const keywordHtml = highlightSearchEscaped(escapeHtml(r.keyword), searchQ);
        const modHtml = escapeHtml(r.modified);
        const uncHtml = highlightSearchEscaped(escapeHtml(r.unc), searchQ);
        const extHtml = highlightSearchEscaped(escapeHtml(r.extension), searchQ);

        // content: keep keyword highlight, then also apply search highlight on top
        const rawContent = readableMode ? makeReadablePreviewText(r.content) : String(r.content ?? "");
        const contentKeyHtml = highlightKeyword(rawContent, r.keyword);
        const contentHtml = highlightSearchEscaped(contentKeyHtml, searchQ);

        const tr = document.createElement("tr");

        // apply row classes based on saved state
        if (r.check) tr.classList.add("flagged");
        if (r.done) tr.classList.add("done");

        tr.innerHTML = `
          <td><input type="checkbox" class="chk-check" title="Flag" data-idx="${idx}" ${r.check ? "checked" : ""}></td>
          <td><input type="checkbox" class="chk-done"  title="Reviewed" data-idx="${idx}" ${r.done ? "checked" : ""}></td>
          <td>${sevHtml}</td>
          <td>${ruleHtml}</td>
          <td>${keywordHtml}</td>
          <td>${modHtml}</td>
          <td>${uncHtml}</td>
          <td>${extHtml}</td>
          <td>${actionsHtml(r.unc)}</td>
          <td>${contentHtml}</td>
        `;

        frag.appendChild(tr);
      }

      tbody.appendChild(frag);

      // checkbox wiring (only visible page)
      tbody.querySelectorAll(".chk-check").forEach(cb => {
        cb.addEventListener("change", (e) => {
          const i = parseInt(e.target.dataset.idx, 10);
          data[i].check = e.target.checked;

          const tr = e.target.closest("tr");
          if (tr) tr.classList.toggle("flagged", e.target.checked);

          saveProgressToLocalStorageDebounced();
          if (filterCheckOnly) applyAll();
        });
      });

      tbody.querySelectorAll(".chk-done").forEach(cb => {
        cb.addEventListener("change", (e) => {
          const i = parseInt(e.target.dataset.idx, 10);
          data[i].done = e.target.checked;

          const tr = e.target.closest("tr");
          if (tr) tr.classList.toggle("done", e.target.checked);

          saveProgressToLocalStorageDebounced();
          if (filterHideDone) applyAll();
        });
      });

      colorSeverityVisible();
    }

    function updatePager() {
      const totalPages = Math.max(1, Math.ceil(view.length / pageSize));
      document.getElementById("pageInfo").textContent =
        `Page ${page}/${totalPages} - ${view.length} rows (filtered)`;

      document.getElementById("prevPage").disabled = (page <= 1);
      document.getElementById("nextPage").disabled = (page >= totalPages);

      syncPageJumpUi();
    }

    function updateRowCount() {
      const el = document.getElementById("row-count");
      if (el) el.textContent = `Visible files: ${view.length} of ${data.length}`;
    }


    function getTotalPages() {
      return Math.max(1, Math.ceil(view.length / pageSize));
    }

    function syncPageJumpUi() {
      const input = document.getElementById("pageJump");
      if (!input) return;

      const total = getTotalPages();
      input.max = String(total);

      // Keep input value in sync without being annoying.
      // Only overwrite if empty or invalid.
      const n = parseInt(input.value, 10);
      if (!Number.isInteger(n) || n < 1 || n > total) {
        input.value = String(page);
      }
    }

    function gotoPage(n) {
      const total = getTotalPages();
      const next = Math.min(Math.max(parseInt(n, 10) || 1, 1), total);
      if (next === page) {
        syncPageJumpUi();
        return;
      }

      page = next;
      renderPage();
      updatePager();
      syncPageJumpUi();
    }

    function wirePageJump() {
      const input = document.getElementById("pageJump");
      const btn = document.getElementById("pageJumpGo");
      if (!input || !btn) return;

      btn.addEventListener("click", () => gotoPage(input.value));

      input.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          gotoPage(input.value);
          e.preventDefault();
        }
      });

      input.addEventListener("blur", () => {
        // Clamp on blur so the user can type freely.
        gotoPage(input.value);
      });

      syncPageJumpUi();
    }


    // ----------------------------
    // Sorting + paging controls
    // ----------------------------
    document.querySelectorAll("#loot-table thead th").forEach(th => {
      th.style.cursor = "pointer";
      th.addEventListener("click", () => {
        const col = th.getAttribute("data-col");
        if (!col) return;
        if (col === "actions") return;

        const mapped = (col === "content") ? "content" : col;

        if (sortCol === mapped) {
          sortDir = (sortDir === "asc") ? "desc" : "asc";
        } else {
          sortCol = mapped;
          sortDir = (sortCol === "modified") ? "desc" : "asc";
        }

        severityPrimary = false;
        page = 1;
        applyAll();
      });
    });

    document.getElementById("prevPage").addEventListener("click", () => {
      gotoPage(page - 1);
    });

    document.getElementById("nextPage").addEventListener("click", () => {
      gotoPage(page + 1);
    });

    document.getElementById("pageSize").addEventListener("change", (e) => {
      pageSize = parseInt(e.target.value, 10);
      page = 1;
      applyAll();
    });

    // ----------------------------
    // Keyboard nav (checkbox columns)
    // ----------------------------
    document.addEventListener("keydown", (event) => {
      const active = document.activeElement;
      if (!active || active.type !== "checkbox") return;

      const td = active.closest("td");
      const tr = active.closest("tr");
      if (!td || !tr) return;

      const colIndex = td.cellIndex;
      let targetRow = null;

      if (event.key === "ArrowUp" || event.key.toLowerCase() === "w") targetRow = tr.previousElementSibling;
      if (event.key === "ArrowDown" || event.key.toLowerCase() === "s") targetRow = tr.nextElementSibling;

      if (targetRow) {
        const targetCb = targetRow.cells[colIndex]?.querySelector("input[type='checkbox']");
        if (targetCb) targetCb.focus();
        event.preventDefault();
        return;
      }

      if (event.key === "ArrowLeft" || event.key.toLowerCase() === "a") {
        const checkCb = tr.cells[0]?.querySelector("input[type='checkbox']");
        if (checkCb) checkCb.focus();
        event.preventDefault();
        return;
      }

      if (event.key === "ArrowRight" || event.key.toLowerCase() === "d") {
        const doneCb = tr.cells[1]?.querySelector("input[type='checkbox']");
        if (doneCb) doneCb.focus();
        event.preventDefault();
        return;
      }

      if (event.key === " ") {
        active.checked = !active.checked;
        active.dispatchEvent(new Event("change"));
        event.preventDefault();
      }

      // 1 = toggle ★ (flag), 2 = toggle ✓ (done)
      if (event.key === "1" || event.key === "2") {
        const tr = active.closest("tr");
        if (!tr) return;

        const targetCol = (event.key === "1") ? 0 : 1; // 0=check, 1=done
        const targetCb = tr.cells[targetCol]?.querySelector("input[type='checkbox']");
        if (!targetCb) return;

        targetCb.checked = !targetCb.checked;
        targetCb.dispatchEvent(new Event("change", { bubbles: true }));
        targetCb.focus();

        event.preventDefault();
        return;
      }
    });

    // ----------------------------
    // One-time wiring (event delegation for actions)
    // ----------------------------
    if (!actionsWired) {
      actionsWired = true;
      const tbody = document.getElementById("loot-body");

      tbody.addEventListener("click", (e) => {
        const btn = e.target.closest(".act");
        if (!btn) return;
        if (btn.tagName.toLowerCase() === "a") return;

        const wrap = btn.closest(".row-actions");
        if (!wrap) return;

        const unc = wrap.getAttribute("data-unc") || "";
        const parent = wrap.getAttribute("data-parent") || "";

        if (btn.classList.contains("act-copy-unc")) {
          copyToClipboard(unc);
          flashCopied(btn);
        }
        if (btn.classList.contains("act-copy-parent")) {
          copyToClipboard(parent);
          flashCopied(btn);
        }
      });
    }

    // ----------------------------
    // Init
    // ----------------------------
    initTheme();
    initReadableMode();
    wireHeader();
    loadProgressFromLocalStorage();
    loadCols();
    applyColsToTable();
    wireColumnsUi();
    buildFilterMenu();
    wirePageJump();
    applyAll();
  });
</script>

'@

# ---------------- CSS ----------------

$css = @"
<style>
  /* Theme hint for native controls */
  :root { 
    color-scheme: dark;
    --report-header-offset: 64px; /* adjust once to match real header height */
  }
  html[data-theme="dark"] { color-scheme: dark; }
  html[data-theme="light"] { color-scheme: light; }

  /* =========================
     Base / Typography
     ========================= */
  body {
    background-color: #121212;
    color: #E0E0E0;
    font-family: Arial, Helvetica, sans-serif;
    font-size: 14px;
    margin: 0;
    padding: 0;
  }

  h1,
  h2 {
    color: #BB86FC;
  }

  /* =========================
     Buttons / Inputs
     ========================= */
  button {
    background-color: rgb(106, 145, 230);
    border: none;
    color: #fff;
    padding: 10px 10px;
    text-align: center;
    display: inline-block;
    font-size: 12px;
    margin: 5px 2px;
    cursor: pointer;
    border-radius: 5px;
    transition: background-color 0.3s, transform 0.2s;
  }

  button:hover {
    background-color: rgb(74, 124, 231);
    transform: scale(1.05);
  }

  button:active {
    background-color: rgb(52, 110, 235);
    transform: scale(0.98);
  }

  input[type="checkbox"] {
    width: 14px;
    height: 14px;
    margin: 4px;
    background-color: #fff;
    border: 2px solid #ccc;
    border-radius: 3px;
    cursor: pointer;
  }

  /* Generic icon helper (used outside of row-actions too) */
  .icon {
    font-size: 20px;
    line-height: 1;
    display: inline-block;
    width: 24px;
    height: 24px;
    text-align: center;
  }

  .icon:hover {
    transform: scale(1.2);
    transition: transform 0.2s ease, color 0.2s ease;
  }

  /* =========================
     Sticky report header
     ========================= */
  #report-header {
    position: sticky;
    top: 0;
    z-index: 3000;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 12px 14px;
    border-bottom: 1px solid #333;
    background: rgba(18, 18, 18, 0.92);
    backdrop-filter: blur(6px);
  }

  .hdr-left {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 280px;
  }

  .hdr-title {
    display: flex;
    align-items: baseline;
    gap: 10px;
    font-size: 18px;
    font-weight: 800;
    color: inherit;
  }

  .hdr-name {
    font-size: 18px;
    font-weight: 900;
  }

  .hdr-sub {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    opacity: 0.9;
  }

  .hdr-meta { white-space: nowrap; }
  .hdr-dot { opacity: 0.5; }

  .hdr-right {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
    justify-content: flex-end;
  }

  .hdr-link {
    font-size: 12px;
    color: inherit;
    opacity: 0.85;
    text-decoration: none;
    padding: 8px 10px;
    border: 1px solid #444;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.03);
  }

  .hdr-link:hover {
    opacity: 1;
    text-decoration: underline;
  }

  /* Severity mini-colors in header */
  .hdr-sub .sev.black { color: #fff; }
  .hdr-sub .sev.red { color: #ff6b6b; }
  .hdr-sub .sev.yellow { color: #f1c40f; }
  .hdr-sub .sev.green { color: #2ecc71; }

  /* When report header is sticky, keep table header below it */
  th {
    top: var(--report-header-offset);
    z-index: 2000; /* keep above rows but below report header */
  }

  /* =========================
     Filter UI
     ========================= */
  #filter-menu {
    margin: 10px 0 14px 0;
    padding: 12px;
    border: 1px solid #333;
    border-radius: 10px;
    background: rgba(255, 255, 255, 0.02);
  }

  .filter-topbar {
    display: flex;
    gap: 10px;
    align-items: center;
    flex-wrap: wrap;
    margin-bottom: 10px;
  }

  .filter-topbar .spacer { flex: 1; }

  .filter-topbar input[type="text"] {
    min-width: 280px;
    padding: 7px 10px;
    border-radius: 8px;
    border: 1px solid #444;
    background: rgba(255, 255, 255, 0.03);
    color: inherit;
    outline: none;
  }

  .filter-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(220px, 1fr));
    gap: 10px;
  }

  @media (max-width: 1100px) {
    .filter-grid {
      grid-template-columns: repeat(2, minmax(220px, 1fr));
    }
  }

  @media (max-width: 780px) {
    .filter-grid { grid-template-columns: 1fr; }

    .filter-topbar input[type="text"] {
      min-width: 200px;
      width: 100%;
    }
  }

  details.filter-card {
    border: 1px solid #333;
    border-radius: 10px;
    padding: 8px 10px;
    background: rgba(255, 255, 255, 0.02);
  }

  details.filter-card > summary {
    cursor: pointer;
    font-weight: 700;
    user-select: none;
    list-style: none;
    display: flex;
    align-items: center;
    gap: 8px;
  }

  details.filter-card > summary::-webkit-details-marker {
    display: none;
  }

  .filter-card .meta {
    font-weight: 400;
    opacity: 0.8;
    margin-left: auto;
    font-size: 12px;
  }

  .filter-list {
    margin-top: 8px;
    display: grid;
    grid-template-columns: repeat(2, minmax(140px, 1fr));
    gap: 6px 10px;
  }

  .filter-list.threecol {
    grid-template-columns: repeat(3, minmax(120px, 1fr));
  }

  .filter-list.onecol {
    grid-template-columns: 1fr;
  }

  .filter-scroll {
    max-height: 180px;
    overflow: auto;
    padding-right: 6px;
  }

  .filter-actions-row {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
    margin-top: 8px;
  }

  .filter-mini {
    font-size: 12px;
    opacity: 0.85;
  }

  .filter-inline {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin-right: 12px;
  }

  .ext-search {
    width: 100%;
    max-width: 100%;
    box-sizing: border-box;
    margin-top: 6px;
    padding: 6px 8px;
    border-radius: 8px;
    border: 1px solid #444;
    background: rgba(255, 255, 255, 0.03);
    color: inherit;
  }

  /* =========================
     Table layout
     ========================= */
  #loot-table {
    width: 100%;
    max-width: 100%;
    margin-top: 5px;
    table-layout: fixed;
    border-collapse: collapse;
    font-size: 14px;
  }

  /* Column widths (needs your <colgroup> classes) */
  #loot-table col.c-check { width: 32px; }
  #loot-table col.c-done { width: 32px; }
  #loot-table col.c-sev { width: 70px; }
  #loot-table col.c-actions { width: 140px; }
  #loot-table col.c-mod { width: 160px; }
  #loot-table col.c-ext { width: 90px; }
  #loot-table col.c-rule { width: 185px; }
  #loot-table col.c-key { width: 160px; }

  /* Let UNC + content take the remaining space */
  #loot-table col.c-unc { width: 360px; }
  /* c-content: no width => gets the rest */

  /* Default: no wrapping + ellipsis for compact columns */
  #loot-table td,
  #loot-table th {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  #loot-table td {
    vertical-align: middle;
  }

  th {
    background: #282a36;
    color: #E0E0E0;
    font-size: 14px;
    font-weight: bold;
    padding: 8px;
    text-align: left;
    border: 1px solid #333;
    border-bottom: 2px solid #838383;
    position: sticky;
    cursor: pointer;
  }

  td {
    padding: 6px;
    border: 1px solid #333;
  }

  /* Center severity + actions columns */
  table td:nth-child(3),
  table td:nth-child(9) {
    text-align: center;
    vertical-align: middle;
  }

  tbody tr:nth-child(even) { background-color: #1A1A1A; }
  tbody tr:nth-child(odd) { background-color: #2A2A2A; }

  tbody tr:hover td:not(:nth-child(3)) {
    background-color: #444 !important;
  }

  /* Compact icon headers */
  #loot-table th[data-col="check"],
  #loot-table th[data-col="done"] {
    text-align: center;
    font-size: 16px;
    font-weight: 700;
    width: 32px;
  }

  /* Center first two checkbox columns */
  #loot-table td:nth-child(1),
  #loot-table td:nth-child(2) {
    text-align: center;
    vertical-align: middle;
    padding: 0;
  }

  #loot-table td:nth-child(1) input[type="checkbox"],
  #loot-table td:nth-child(2) input[type="checkbox"] {
    display: block;
    margin: 0 auto;
  }

  /* Allow wrapping only in UNC + content */
  #loot-table td:nth-child(7),   /* UNC */
  #loot-table td:nth-child(10) { /* content */
    white-space: normal;
    overflow: visible;
    text-overflow: clip;
    overflow-wrap: anywhere;
    word-break: break-word;
  }

  /* Actions column: allow tooltip to escape the cell */
  #loot-table td:nth-child(9),
  #loot-table th:nth-child(9) {
    overflow: visible !important;
  }

  #loot-table td:nth-child(9) {
    position: relative;
    z-index: 5;
  }

  /* =========================
     Column visibility toggles
     ========================= */
  #loot-table.hide-col-check th:nth-child(1),
  #loot-table.hide-col-check td:nth-child(1),
  #loot-table.hide-col-check col.c-check { display: none !important; }

  #loot-table.hide-col-done th:nth-child(2),
  #loot-table.hide-col-done td:nth-child(2),
  #loot-table.hide-col-done col.c-done { display: none !important; }

  #loot-table.hide-col-severity th:nth-child(3),
  #loot-table.hide-col-severity td:nth-child(3),
  #loot-table.hide-col-severity col.c-sev { display: none !important; }

  #loot-table.hide-col-rule th:nth-child(4),
  #loot-table.hide-col-rule td:nth-child(4),
  #loot-table.hide-col-rule col.c-rule { display: none !important; }

  #loot-table.hide-col-keyword th:nth-child(5),
  #loot-table.hide-col-keyword td:nth-child(5),
  #loot-table.hide-col-keyword col.c-key { display: none !important; }

  #loot-table.hide-col-modified th:nth-child(6),
  #loot-table.hide-col-modified td:nth-child(6),
  #loot-table.hide-col-modified col.c-mod { display: none !important; }

  #loot-table.hide-col-unc th:nth-child(7),
  #loot-table.hide-col-unc td:nth-child(7),
  #loot-table.hide-col-unc col.c-unc { display: none !important; }

  #loot-table.hide-col-extension th:nth-child(8),
  #loot-table.hide-col-extension td:nth-child(8),
  #loot-table.hide-col-extension col.c-ext { display: none !important; }

  #loot-table.hide-col-actions th:nth-child(9),
  #loot-table.hide-col-actions td:nth-child(9),
  #loot-table.hide-col-actions col.c-actions { display: none !important; }

  #loot-table.hide-col-content th:nth-child(10),
  #loot-table.hide-col-content td:nth-child(10),
  #loot-table.hide-col-content col.c-content { display: none !important; }


  /* =========================
    Column visibility toggles
    ========================= */
  html.readable-on #loot-table td:nth-child(10) {
    white-space: pre-wrap !important;   /* show \n and \t */
    overflow: visible !important;
    text-overflow: clip !important;
  }


  /* =========================
     Row actions (icons + tooltips)
     ========================= */
  .row-actions {
    position: relative;
    z-index: 6;
    display: flex;
    gap: 6px;
    align-items: center;
    justify-content: center;
  }

  .row-actions .act {
    position: relative; /* tooltip anchor */
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    padding: 0;
    border-radius: 6px;
    border: 1px solid rgba(255, 255, 255, 0.12);
    background: rgba(255, 255, 255, 0.03);
    color: inherit;
    cursor: pointer;
    text-decoration: none; /* for <a> */
  }

  .row-actions .act:hover {
    background: rgba(255, 255, 255, 0.08);
    transform: scale(1.06);
  }

  /* Ensure the icon inside open/save links fits nicely */
  .row-actions .act .icon {
    width: auto;
    height: auto;
    font-size: 18px;
    line-height: 1;
  }

  /* Fade actions slightly until hover (cleaner scanning) */
  #loot-body tr .row-actions { opacity: 0.75; }
  #loot-body tr:hover .row-actions { opacity: 1; }

  /* Copy feedback */
  .row-actions .act.copied {
    border-color: rgba(46, 204, 113, 0.55);
    background: rgba(46, 204, 113, 0.12);
  }

  .row-actions .act .tip {
    position: absolute;
    top: -26px;
    left: 50%;
    transform: translateX(-50%);
    font-size: 11px;
    padding: 3px 6px;
    border-radius: 6px;
    border: 1px solid rgba(255, 255, 255, 0.14);
    background: rgba(0, 0, 0, 0.85);
    color: inherit;
    white-space: nowrap;
    opacity: 0;
    pointer-events: none;
    transition: opacity 120ms ease;
  }

  .row-actions .act.show-tip .tip {
    opacity: 1;
  }

  /* =========================
     Row state styles (workflow)
     ========================= */
  /* Done: greyed out */
  #loot-body tr.done td {
    opacity: 0.55;
  }

  #loot-body tr.done td a,
  #loot-body tr.done td .icon {
    opacity: 0.7;
  }

  /* Flagged: subtle overlay on every cell except severity */
  #loot-body tr.flagged td:not(:nth-child(3)) {
    background-color: inherit;
    position: relative;
  }

  #loot-body tr.flagged td:not(:nth-child(3))::after {
    content: "";
    position: absolute;
    inset: 0;
    background: rgba(245, 197, 66, 0.10);
    pointer-events: none;
    z-index: 0;
  }

  #loot-body tr.flagged td:not(:nth-child(3)) > * {
    position: relative;
    z-index: 1;
  }

  /* =========================
     Modals
     ========================= */
  .modal-overlay {
    position: fixed;
    inset: 0;
    display: none;
    align-items: center;
    justify-content: center;
    padding: 20px;
    background: rgba(0, 0, 0, 0.65);
    z-index: 5000;
  }

  .modal-overlay.open {
    display: flex;
  }

  .modal {
    width: min(900px, 95vw);
    max-height: 85vh;
    overflow: auto;
    border-radius: 12px;
    border: 1px solid #333;
    background: #1E1E1E;
    color: inherit;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.4);
  }

  .modal-header {
    position: sticky;
    top: 0;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 12px 14px;
    border-bottom: 1px solid #333;
    background: rgba(30, 30, 30, 0.95);
  }

  .modal-title {
    font-weight: 700;
    font-size: 16px;
  }

  .modal-close { margin-left: auto; }
  .modal-body { padding: 12px 14px; }

  /* Search highlights */
  mark.hit {
    padding: 0 2px;
    border-radius: 3px;
    background: rgba(255, 235, 59, 0.25);
    color: inherit;
  }

  /* =========================
     Light theme overrides
     ========================= */
  html[data-theme="light"] body {
    background: #ffffff;
    color: #111;
  }

  html[data-theme="light"] h1,
  html[data-theme="light"] h2 {
    color: #000099;
  }

  html[data-theme="light"] table {
    background: #fff;
    color: #111;
  }

  html[data-theme="light"] th {
    background: linear-gradient(#49708f, #293f50);
    color: #fff;
    border: 1px solid #ccc;
    border-bottom: 2px solid #ccc;
  }

  html[data-theme="light"] td {
    border: 1px solid #ddd;
  }

  html[data-theme="light"] tbody tr:nth-child(even) { background: #f0f0f2; }
  html[data-theme="light"] tbody tr:nth-child(odd) { background: #ffffff; }

  html[data-theme="light"] tbody tr:hover td:not(:nth-child(3)) {
    background-color: lightblue !important;
  }

  html[data-theme="light"] #report-header {
    background: rgba(255, 255, 255, 0.92);
    border-bottom: 1px solid #ccc;
  }

  html[data-theme="light"] #filter-menu { border: 1px solid #ccc; }
  html[data-theme="light"] details.filter-card { border: 1px solid #ccc; }

  html[data-theme="light"] .filter-topbar input[type="text"],
  html[data-theme="light"] .ext-search {
    border: 1px solid #ccc;
    background: #fff;
    color: #111;
  }

  html[data-theme="light"] .hdr-link {
    border: 1px solid #ccc;
    background: #fff;
  }

  html[data-theme="light"] .hdr-sub .sev.black {
    color: #111;
  }

  html[data-theme="light"] mark.hit {
    background: rgba(255, 235, 59, 0.55);
  }

  html[data-theme="light"] .modal {
    background: #fff;
    border: 1px solid #ccc;
  }

  html[data-theme="light"] .modal-header {
    background: rgba(255, 255, 255, 0.95);
    border-bottom: 1px solid #ccc;
  }
</style>

"@


# ---------------- HTML skeleton (NO huge table) ----------------
$titleAndTable = @"
<div id="report-header">
  <div class="hdr-left">
    <span id="report-sha256" style="display:none;">$($baseInfo.SHA256)</span>
    <div class="hdr-title">
      <span class="hdr-name">SnafflerParser Loot Report</span>
    </div>
    <div class="hdr-sub">
      <span class="hdr-meta">Input: <strong>$($baseInfo.Snaffler_File)</strong></span>
      <span class="hdr-dot">&#8226;</span>
      <span class="hdr-meta">Files: <strong>$filesum</strong></span>
      <span class="hdr-dot">&#8226;</span>
      <span class="hdr-meta sev black">B: <strong>$blackscount</strong></span>
      <span class="hdr-meta sev red">R: <strong>$redscount</strong></span>
      <span class="hdr-meta sev yellow">Y: <strong>$yellowscount</strong></span>
      <span class="hdr-meta sev green">G: <strong>$greenscount</strong></span>
      <span class="hdr-dot">&#8226;</span>
      <span class="hdr-meta">Parsed: <strong>$(Format-TimePrettyUtc $baseInfo.Report_GeneratedUtc)</strong></span>

    </div>
  </div>

  <div class="hdr-right">
    <a class="hdr-link" href="https://github.com/zh54321/snaffler_parser" target="_blank" rel="noopener">
      Repo &#8599;
    </a>
    <button id="show-input-info" type="button">Job Info</button>
    <button id="save-html" type="button">Save HTML</button>
    <button id="theme-toggle" type="button" title="Toggle theme">Light mode</button>
  </div>
</div>


<div id="filter-menu"></div>

<div id="pager" style="margin:10px 0; display:flex; gap:10px; align-items:center; flex-wrap:wrap;">
  <button id="prevPage">Prev</button>
  <button id="nextPage">Next</button>
  <span id="pageInfo"></span>
  <label style="display:inline-flex; align-items:center; gap:6px;">
    Go to:
    <input id="pageJump" type="number" min="1" step="1"
           style="width:90px; padding:6px 8px; border-radius:8px; border:1px solid #444; background: rgba(255,255,255,0.03); color: inherit;"
           aria-label="Go to page">
  </label>
  <button id="pageJumpGo" type="button" title="Go to page">Go</button>
  <label>Rows/page:
    <select id="pageSize">
      <option>100</option>
      <option>250</option>
      <option selected>500</option>
      <option>1000</option>
      <option>5000</option>
    </select>
  </label>

  <span style="margin-left:auto;"></span>
  <button id="cols-btn" type="button" title="Choose visible columns">Columns</button>
  <button id="toggle-readable" type="button" title="Toggle readable content">Unescape</button>
  <button id="reset-progress" type="button" title="Delete saved check/done state">Reset Progress</button>
  <button id="export-csv" type="button" title="Export current filtered view to CSV">Export Filtered Table</button>
</div>

<div id="cols-modal" class="modal-overlay" aria-hidden="true">
  <div class="modal">
    <div class="modal-header">
      <div class="modal-title">Visible Columns</div>
      <button id="cols-close" class="modal-close" type="button">Close</button>
    </div>
    <div class="modal-body">
      <div id="cols-list" class="filter-list threecol"></div>

      <div class="filter-actions-row" style="margin-top:12px;">
        <button id="cols-all" type="button">All</button>
        <button id="cols-none" type="button">None</button>
        <button id="cols-apply" type="button">Apply</button>
      </div>
    </div>
  </div>
</div>



<table id="loot-table">
  <colgroup>
    <col class="c-check">
    <col class="c-done">
    <col class="c-sev">
    <col class="c-rule">
    <col class="c-key">
    <col class="c-mod">
    <col class="c-unc">
    <col class="c-ext">
    <col class="c-actions">
    <col class="c-content">
  </colgroup>
  <thead>
    <tr>
      <th data-col="check" title="Flag">&#9733;</th>
      <th data-col="done" title="Reviewed">&#10003;</th>
      <th data-col="severity">severity</th>
      <th data-col="rule">rule</th>
      <th data-col="keyword">keyword</th>
      <th data-col="modified">modified</th>
      <th data-col="unc">unc</th>
      <th data-col="extension">extension</th>
      <th data-col="actions">actions</th>
      <th data-col="content">content</th>
    </tr>
  </thead>
  <tbody id="loot-body"></tbody>
</table>
"@


# ---------------- Build JSON blob from the PS objects ----------------
$rowsForJson = $object | ForEach-Object {
    [pscustomobject]@{
        severity  = $_.severity
        rule      = $_.rule
        keyword   = $_.keyword
        modified  = $_.modified
        unc       = $_.unc
        extension = $_.extension
        content   = $_.content
        check     = $false
        done      = $false
    }
}

$json = $rowsForJson | ConvertTo-Json -Depth 6 -Compress
$json = $json -replace '</script', '<\/script'
$dataBlob = "<script id='loot-data' type='application/json'>$json</script>"

# ---------------- Compose & write final HTML ----------------
write-host "[*] Storing: $($outputname)_loot_$($name).html"

# ---- Parse Snaffler Finished + Duration into objects (so we can pretty print consistently) ----
$finishedObj = $null
if ($baseInfo.Snaffler_EndTime) {
  try {
    # "21/01/2025 07:30:59" (assumed local machine time)
    $finishedObj = [DateTime]::ParseExact(
      $baseInfo.Snaffler_EndTime,
      'dd/MM/yyyy HH:mm:ss',
      [System.Globalization.CultureInfo]::InvariantCulture
    )
  } catch {
    $finishedObj = $baseInfo.Snaffler_EndTime # fallback string
  }
}

$durationObj = $null
if ($baseInfo.Snaffler_Duration) {
  try { $durationObj = [TimeSpan]::Parse($baseInfo.Snaffler_Duration) } catch { $durationObj = $null }
}

# ---- Ordered modal content (controls display order) ----
$baseInfoForModal = [pscustomobject]@{
  'Input file'        = $baseInfo.Snaffler_File
  'SHA256'            = $baseInfo.SHA256
  'Computer'          = $baseInfo.Snaffler_ComputerName
  'User'              = $baseInfo.Snaffler_User

  'Started'           = (Format-TimePrettyUtc $baseInfo.Snaffler_StartTime)
  'Finished'          = (Format-TimePrettyUtc $finishedObj)
  'Snaffler duration' = (Format-DurationPretty $durationObj)

  'Report generated'  = (Format-TimePrettyUtc $baseInfo.Report_GeneratedUtc)
  'Parser duration'   = (Format-DurationPretty $baseInfo.Parser_Duration)
}

$inputInfoInner = $baseInfoForModal | ConvertTo-Html -As List -Fragment




$inputInfo = @"
<div id="input-info-modal" class="modal-overlay" aria-hidden="true">
  <div class="modal">
    <div class="modal-header">
      <div class="modal-title">Input Information</div>
      <button id="modal-close" class="modal-close" type="button">Close</button>
    </div>
    <div class="modal-body">
      $inputInfoInner
    </div>
  </div>
</div>
"@


# Put inputInfo + skeleton table + json blob into body
$body = "$inputInfo $titleAndTable $dataBlob"

$htmlOutput = ConvertTo-Html -Head $css,$Header -Body $body

$htmlOutput | Out-File -FilePath "$($outputname)_loot_$($name).html" -Encoding UTF8

}


# Script section-----------------------------------------------------------------------------------

$banner = @"
 ____               __  __ _             ____                          
/ ___| _ __   __ _ / _|/ _| | ___ _ __  |  _ \ __ _ _ __ ___  ___ _ __ 
\___ \|  _ \ / _  | |_| |_| |/ _ \ '__| | |_) / _  | '__/ __|/ _ \ '__|
 ___) | | | | (_| |  _|  _| |  __/ |    |  __/ (_| | |  \__ \  __/ |   
|____/|_| |_|\__,_|_| |_| |_|\___|_|    |_|   \__,_|_|  |___/\___|_|   

"@

Write-Host $banner -ForegroundColor Cyan

$parserStart = [DateTimeOffset]::UtcNow

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
write-host "[*] Checking input file $inpath"
if (!(Test-Path -LiteralPath $inpath -PathType Leaf)) {
	write-host "[-] Input file not found $inpath"
	exit
} else {
	write-host "[+] Input file exists"

	#Check if file size is  at least 300 bytes
	$FileSize = (Get-ChildItem $inpath).Length / 1014
	$FileSizeRound = [math]::Round($FileSize,2)

	if ($FileSizeRound -ge 0.3) {
		write-host "[+] Input file is $FileSizeRound KB"
		write-host "[*] Importing data from file"
		$outputname = (Get-Item $inpath).BaseName

		# Streaming containers
		$files = [System.Collections.Generic.List[object]]::new()
		$sharesSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)


		$baseInfo = [PsCustomObject]@{
			Snaffler_File = Split-Path $inpath -Leaf
			SHA256 = $(Get-FileHash $inpath).Hash
      Snaffler_EndTime    = $null
      Snaffler_Duration   = $null
		}

		$firstLine = Get-Content $inpath -TotalCount 1

		# Define the regular expression pattern to extract Computername, User and timestamp
		$pattern = '\[(?<machine>.*?)\\(?<user>.*?)@.*?\]\s+(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}Z)'


		if ($firstLine -match $pattern) {
			$baseInfo | Add-Member -NotePropertyName Snaffler_ComputerName -NotePropertyValue $matches['machine']
			$baseInfo | Add-Member -NotePropertyName Snaffler_User -NotePropertyValue $matches['user']
			$baseInfo | Add-Member -NotePropertyName Snaffler_StartTime -NotePropertyValue $matches['timestamp']
		}

	} else {
		write-host "[!] Input file is less than 0.3 KB"
		exit
	}

}

write-host "[*] Streaming parse of input file"

# We already read first line for baseInfo, now stream everything.
# Use .NET StreamReader for speed and low memory.
$sr = [System.IO.StreamReader]::new($inpath)

try {
    while (-not $sr.EndOfStream) {
        $raw = $sr.ReadLine()
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        # Split on tab; keep empties (important because the snaffler output file has blank columns)
        $cols = $raw.Split("`t", [System.StringSplitOptions]::None)

        # Need at least 3 columns for Type check: [0]=user, [1]=timestamp, [2]=typ
        if ($cols.Length -lt 3) { continue }

        $typ = $cols[2]

        # ---- Job end/duration info (cheap: only runs for [Info] lines) ----
        if ($typ -eq "[Info]" -and $cols.Length -ge 4) {
            $msg = $cols[3]

            # Example: "Finished at 21/01/2025 07:30:59"
            if ($msg -like "Finished at*") {
                if ($msg -match '^Finished at\s+(?<dt>\d{1,2}/\d{1,2}/\d{4}\s+\d{2}:\d{2}:\d{2})') {
                    $baseInfo.Snaffler_EndTime = $Matches.dt
                } else {
                    # fallback: store full message if format differs
                    $baseInfo.Snaffler_EndTime = $msg
                }
                continue
            }

            # Example: "Snafflin' took 00:05:00.0467798"
            if ($msg -like "Snafflin'*took*") {
                if ($msg -match "took\s+(?<dur>\d{2}:\d{2}:\d{2}(?:\.\d+)?)") {
                    $baseInfo.Snaffler_Duration = $Matches.dur
                } else {
                    $baseInfo.Snaffler_Duration = $msg
                }
                continue
            }

        }


        if ($typ -eq "[Share]") {
            # In current format, UNC is column index 4 (0-based): user, time, typ, color, unc, rights
            if ($cols.Length -gt 4) {
                $shareUnc = $cols[4]
                if (-not [string]::IsNullOrWhiteSpace($shareUnc)) {
                    [void]$sharesSet.Add($shareUnc)
                }
            }
            continue
        }

        if ($typ -eq "[File]") {
            # A [File] line is tab-separated. Columns by index:
            #   cols[0]  user@host
            #   cols[1]  timestamp
            #   cols[2]  [File]
            #   cols[3]  severity (Black/Red/Yellow/Green)
            #   cols[4]  rule name
            #   cols[5]  readable  (R or empty)
            #   cols[6]  writable  (W or empty)
            #   cols[7]  modifiable (M or empty)
            #   cols[8]  matched keyword/string
            #   cols[9]  file size (bytes)
            #   cols[10] last-modified timestamp
            #   cols[11] UNC path
            #
            # Snaffler added a new column after the UNC in release 1.0.244:
            #   OLD (13 cols): cols[12] = content (matched text snippet)
            #   NEW (14 cols): cols[12] = original filename (for SCCM content-lib files; usually empty)
            #                  cols[13] = content
            if ($cols.Length -lt 12) { continue }

            $unc = $cols[11]
            if ([string]::IsNullOrWhiteSpace($unc)) { continue }

            # Support both old (13-col) and new (14-col) Snaffler output formats.
            # The new format added alt_filename at cols[12]; content shifted to cols[13].
            $content = if ($cols.Length -gt 13) { $cols[13] } elseif ($cols.Length -gt 12) { $cols[12] } else { '' }

            # UNC sanitize for GetExtension
            $uncSafe = $unc -replace '[\x00-\x1F]', ''
            if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                $uncSafe = $uncSafe -replace '[<>:"|?*]', ''
            }
            $ext = ''
            try { $ext = [System.IO.Path]::GetExtension($uncSafe) } catch { $ext = '' }


            $files.Add([PsCustomObject]@{
				check     = $false
				done      = $false
                severity  = if ($cols.Length -gt 3)  { $cols[3] }  else { '' }
                rule      = if ($cols.Length -gt 4)  { $cols[4] }  else { '' }
                keyword   = if ($cols.Length -gt 8)  { $cols[8] }  else { '' }
                modified  = if ($cols.Length -gt 10) { $cols[10] } else { '' }
                unc       = $unc
                extension = $ext
                content   = $content
            })
        }
    }
}
finally {
    if ($null -ne $sr) { $sr.Dispose() }
}

write-host "[*] Processing shares"

$shares = $sharesSet |
    ForEach-Object { [PsCustomObject]@{ unc = $_ } } |
    Sort-Object -Property unc



# Check share count and write to file
$sharescount = $shares | Measure-Object -Line -Property unc
if ($sharescount.lines -ge 1) {
	write-host "[+] Shares identified: $($sharescount.lines)"
	write-host "[*] Writing share output file"
	$shares | Format-Table -AutoSize | Out-File -FilePath "$($outputname)_shares.txt"
} else {
	write-host "[!] Shares identified: 0"
	write-host "[?] Was Snaffler executed with parameter -y ?"
}



# Define fixed severity order
$severityRank = @{
    Black  = 0
    Red    = 1
    Yellow = 2
    Green  = 3
}

# Whether to sort descending
$sortDescending = ($sort -eq 'modified')

# Sort once:
# 1) by severity rank so Black/Red/Yellow/Green always stay grouped + ordered
# 2) then by chosen $sort column (descending only for modified)
$fulloutput = $files | Sort-Object `
    @{ Expression = { $severityRank[$_.severity] } ; Ascending = $true } ,
    @{ Expression = { $_.$sort } ; Descending = $sortDescending }

# Group once into a hashtable: keys = "Black"/"Red"/...
$bySeverity = $fulloutput | Group-Object -Property severity -AsHashTable -AsString

# Pull groups out (always define them as arrays, even if empty)
$blacks  = @($bySeverity['Black'])
$reds    = @($bySeverity['Red'])
$yellows = @($bySeverity['Yellow'])
$greens  = @($bySeverity['Green'])

# Counts
$blackscount  = $blacks.Count
$redscount    = $reds.Count
$yellowscount = $yellows.Count
$greenscount  = $greens.Count



$filesum = $blackscount + $redscount + $yellowscount + $greenscount
if ($filesum -ge 1) {
	write-host "[+] Files total: $filesum "
	write-host "[+] Files with severity BLACK: $blackscount"
	write-host "[+] Files with severity RED: $redscount"
	write-host "[+] Files with severity YELLOW: $yellowscount"
	write-host "[+] Files with severity GREEN: $greenscount"


  $reportGeneratedUtc = [DateTimeOffset]::UtcNow
  $parserDuration = $reportGeneratedUtc - $parserStart

  $baseInfo | Add-Member -NotePropertyName Report_GeneratedUtc -NotePropertyValue $reportGeneratedUtc -Force
  $baseInfo | Add-Member -NotePropertyName Parser_Duration -NotePropertyValue $parserDuration -Force

  
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
	write-host "[*] Will export $($sharescount.lines) shares to explorer"
	explorerpp($shares)
}