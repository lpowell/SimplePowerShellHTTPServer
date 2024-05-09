# Write log data to console and optionally, a log file
function Write-Log([string]$LogMessage, $Level)
{
    $MessageTime = [System.DateTime]::UTCNow 
    switch($LogLevel){
        3 {
            "$MessageTime`t$LogMessage" | Out-File -Path $LogFile -Append
            Write-Verbose "$MessageTime`t$LogMessage"
        }

        2 {
            if($Level -le 2){
                "$MessageTime`t$LogMessage" | Out-File -Path $LogFile -Append
                Write-Verbose "$MessageTime`t$LogMessage"
            }
        }

        default {
            if($Level -eq 1){
                "$MessageTime`t$LogMessage" | Out-File -Path $LogFile -Append
                Write-Verbose "$MessageTime`t$LogMessage"
            }
        }
    }
}
# Test if the user is running the server as admin
# This server must be run as an Admin
Function Test-Admin{
    # Check if the session has the correct permissions
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    # Returns true or false
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
# Start the HTTP server and return a server object
Function Start-Server{
    switch($LogLevel){
        1 {$ll="OPERATIONAL";break;}
        2 {$ll="SECURITY";break;}
        3 {$ll="ALL";break;}
    }
    Write-Log "Logging level set to $ll"
    Write-Host "API Key: $APIKey"
    # Create server listener 
    try{
        $prefix = "http://"+$URL+":"+$Port+"/"
        $prefxhttps = "https://"+$URL+":"+$SSLPort+"/"
        Write-Log "Initiating server on $Prefix" 1
        $Server = New-Object System.Net.HttpListener
        foreach($x in [string[]] @($prefix,$prefxhttps)){
            $Server.Prefixes.Add($x)
        }
        $Server.Start()
    }    
    catch [System.Net.HttpListenerException] {
        Write-Log "Caught HttpListenerException exception" 1
        Write-Log "Server aborted. Check errors." 1
        Write-Log ($_.ScriptStackTrace).ToString() 1
        Write-Log ($_.Exception).ToString() 1
        Write-Log ($_.FullyQualifiedErrorId).ToString() 1
        exit
    }
    catch
    {
        Write-Log "Caught unexpected exception" 1
        Write-Log "Server aborted. Check errors." 1
        Write-Log ($_.ScriptStackTrace).ToString() 1
        Write-Log ($_.Exception).ToString() 1
        Write-Log ($_.FullyQualifiedErrorId).ToString() 1
        exit
    }
    # Check for succesful execution
    if(Get-NetTCPConnection -LocalPort $port -State Listen){
        Write-Log "Server started succesfully" 1
    }else{
        Write-Error "Server could not be found on the designated port. Try examining surrounding logs."
        Write-Log "ERROR: Server could not be found on the designated port. Try examining surrounding logs." 1
        Write-Log "Stopping server..."
        # Close server
        $Server.Stop()
    }
    # Return server object
    return $Server
}
# Load server settings from a passed JSON file
# Automates config and initiates server with Start-Server
Function Load-Server{
    # Load Profile
    $FileInfo = New-Object System.IO.FileInfo($Load)
    if($FileInfo.Exists){
        Write-Log "Loading configuration item $Load" 1
        try{
            $Load = Get-Content $Load | ConvertFrom-JSON
        }
        catch{
            Write-Error "Could not load JSON file."
            Write-Log "ERROR: Could not load JSON file." 1
            Write-Log ($_.Exception).ToString() 1
            Write-Log ($_.FullyQualifiedErrorId).ToString() 1
        }
        if($Load.Port -ne ""){$Port = $Load.Port}
        if($Load.URL -ne ""){$URL = $Load.URL}
        if($Load.Port -ne ""){$APIKey = $Load.APIKey}
        if($Load.Index -ne ""){$Index = $Load.Index}
        if($Load.Path -ne ""){$Path = $Load.Path}
        if($Load.LogFile -ne ""){$LogFile = $Load.LogFile}
        if($Load.LogLevel -ne ""){$LogLevel = $Load.LogLevel}
    }else{
        Write-Error "Configuration file not found at $Load"
        Write-Log "ERROR: Configuration file not found at $Load" 1
    }
    Start-Server
}
# Handle the request object sent by the client
Function Handle-Request($Request){
    # Process request
    Write-Log "Request received from: $($Request.RemoteEndPoint)" 1
    $RequestDetails = @(
            "`t`t`t`tLocalEndPoint: $($Request.LocalEndPoint)`n"
            "`t`t`t`tURL: $($Request.Url)`n"
            "`t`t`t`tUserAgent: $($Request.UserAgent)`n"
            "`t`t`t`tHTTPMethod: $($Request.HttpMethod)`n"
            "`t`t`t`tHeaders: `n"
            Foreach($header in $request.headers.AllKeys){
                "`t`t`t`t`t$header | $($request.headers.GetValues($header))`n"
            }
            "`t`t`t`tCookies: $($Request.Cookies)`n"
            "`t`t`t`tInputStream: $($Request.InputStream)"
    )
    Write-Log "Request details:`n$($RequestDetails)" 2
    # Test for api key
    if($Request.Headers["x-api-key"] -eq $APIKey){
        Write-Log "Successful API authentication from $($Request.RemoteEndPoint)" 2
        switch($Request.Headers["Action"]){
            "Shutdown" {
                Write-Log "Shutdown requested" 1
                return @("Shutdown")
            }

            "DirectoryList" {
                Write-Log "DirectoryList requested" 1
                return @("DirectoryList")
            }

            "CommandExecute" {
                Write-Log "CommandExecute requested" 1
                return @("CommandExecute",$Request.Headers["Command"])
            }
            Default {
                Write-Log "No valid action requested"
                return @("NotFound")
            }
        }
        return
    }elseif(($Request.Headers["x-api-key"]) -And $Request.Headers["x-api-key"] -ne $APIKey){
        write-log "Failed API authentication from $($Request.RemoteEndPoint)" 2
        return @("API","FAILED")
    }
    # Test for method
    switch($request.HttpMethod){
        "GET" {
            # Create serving path
            $RequestPath=$Path+"\"+ ((($request.Url).ToString() -replace "/","\") -split '\\',4)[3]
            Write-Log "Client requested file: $RequestPath" 1
            $RequestFile = New-Object System.IO.FileInfo($RequestPath)
            if($RequestFile.Exists){
                Write-Log "File exists" 3
                return @("Request",$RequestPath)
            }elseif(((($Request.Url).ToString()) -replace ".*/") -le 1){
                return @("Request","Index")
            }else{
                Write-Log "Requested file could not be found" 1
                return @("NotFound")
            }
        }

        "POST" {
            $MemoryStream = New-Object System.IO.MemoryStream
            $Request.InputStream.CopyTo($MemoryStream)
            [byte[]] $data = $MemoryStream.ToArray()
            $MemoryStream.Close()
            $SaveFile = Save-File $data
            return @("SavedFile",$SaveFile)
        }

        "PUT" {
            # Create name based on passed header
            Write-Log "Client is sending a file for upload" 1
            if($Request.Headers["Name"]){
                $writeName = $Request.Headers["Name"]
                Write-Log "Received file name: $writeName" 3
            }else{
                $writeName = "SavedFile"
            }
            $writePath = (Get-Location).Path + "\" + $writeName
            try {
                # Create a filestream object for writing 
                $fsWrite = New-Object System.IO.FileStream($writePath, "Create")
                Write-Log "File created at: $writePath" 3
                # Create a MemoryStream object to store the InputStream
                $memStream = New-Object System.IO.MemoryStream
                $Request.InputStream.CopyTo($memStream)
                [byte[]] $data = $memStream.ToArray()
                # Write the data to file
                $fsWrite.Write($data, 0, $data.Length)
                $fsWrite.Close()
                $memStream.Close()
                Write-Log "File saved at: $writePath" 1
                return @("SavedFile",$True)
            }
            catch {
                # Catch on error and terminate stream objects
                Write-Log "Something went wrong. Check errors." 1
                Write-Log ($_.ScriptStackTrace).ToString() 1
                Write-Log ($_.Exception).ToString() 1
                Write-Log ($_.FullyQualifiedErrorId).ToString() 1
                $fsWrite.Close()
                $memStream.Close()
                return @("SavedFile",$false)
            }
        }

        "HEAD" {
            return @("HEAD")
        }
        Default {
            return @("NotFound")
        }
    }
}
# Handle the response object to send
Function Send-Response($Response,$ResponseAction){
    # Build response
    switch($ResponseAction[0]){
        "DirectoryList" {
            # Get file contents
            [string] $responseString = $(Get-ChildItem -path $Path | Out-String)
            break
        }

        "CommandExecute" {
            Write-Log "Client sent the following command: $($ResponseAction[1])" 2
            # Get file contents
            [string] $responseString = $(Invoke-Expression -Command $ResponseAction[1] | Out-String)
            break
        }

        "Request" {
            if($ResponseAction[1] -eq "Index"){
                if(!$Index){
                    [string] $responseString = Serve-Index
                }else{
                    [string] $responseString = Serve-WebContent "Index"
                }
            }else{
                # Build in media viewers at some point.
                $FileInfo = New-Object System.IO.FileInfo($ResponseAction[1])
                if($FileInfo.Extension -in (".html",".php",".js",".css")){
                    [string] $responseString = Serve-WebContent $ResponseAction[1]
                }else{
                    $File = Serve-File $ResponseAction[1] $response
                    return
                }
            }
            break
        }

        "SavedFile" {
            if($ResponseAction[1] -eq $true){
                [string] $ResponseString = "Success"
                $Response.StatusCode = [System.Net.HttpStatusCode]::OK
                $Response.StatusDescription = "Successful"
            }else{
                [string] $ResponseString = "Failed"
                $Response.StatusCode = [System.Net.HttpStatusCode]::Conflict
                $Response.StatusDescription = "Failed to save file"
            } 
            break
        }
        "API" {
            [string] $ResponseString = ""
            $Response.StatusCode = [System.Net.HttpStatusCode]::Unauthorized
            $Response.StatusDescription = "Unauthorized"
            break
        }

        "NotFound" {
            [string] $ResponseString = "File or Action not found"
            $Response.StatusCode = [System.Net.HttpStatusCode]::NotFound
            $Response.StatusDescription = "NotFound"
            break
        }

        Default {
            [string] $ResponseString = "File or Action not found"
            $Response.StatusCode = [System.Net.HttpStatusCode]::NotFound
            $Response.StatusDescription = "NotFound"
            break
        }
    }
    # Send response
    [byte[]] $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseString)
    $Response.ContentLength64 = $Buffer.Length
    [System.IO.Stream] $Output = $Response.OutputStream
    $Output.Write($Buffer,0,$Buffer.Length)
    $Output.Close()
    return
    # Return on success or failure

}
# Serve a multimedia file to a client request
Function Serve-MultiMedia($Content){
    # Stream must be kept open until all bytes have been read (i.e., video has been streamed)
    # Will require a custom handler to respond 
    # Images will not have this problem. 
    Write-Log "Serving multimedia file: $Content" 1
    $HTML = @"
<HTML>
<BODY>
<video width="300" height="200" controls>
    <source src="{0}" type="video/mp4">
    Your browser does not support displaying this content.
</video>
</body>
</html>
"@ -f ($($Content.split($Path))[1].split("\")[1..$($($Content.split($Path))[1].split("\") | Measure).count] -join "\")
    return $HTML
}
# Serve a file to a client request
Function Serve-File($Content, $Response){
    Write-Log "Sending file as download" 3
    # Create a filestream object for reading the desired file
    [System.IO.FileStream] $FileStream = New-Object System.IO.FileStream($Content, "Open")
    $filename = ($Content | Get-Item).Name
    $Response.SendChunked = $false
    $Response.ContentLength64 = $FileStream.Length
    # Send information on the requested file. Content-Type is not included in this configuration.
    $Response.AddHeader("Content-disposition","attachment; filename=" +$filename)
    # Create a buffer to hold the data
    [byte[]] $Buffer = [System.Byte[]]::CreateInstance([System.Byte], 64 * 1024)
    # Create a binary writer object
    [System.IO.BinaryWriter] $BinaryWriter = $Response.OutputStream
    # Write the data to the output stream
    for($read > 0;$read = $FileStream.Read($Buffer,0,$Buffer.Length); $read = $FileStream.Read($Buffer,0,$Buffer.Length)){
        $BinaryWriter.Write($Buffer, 0, $read)
        $BinaryWriter.Flush()
    }
    # Close streams
    $BinaryWriter.Close()
    $FileStream.Close()
    Write-Log "File sent: $RequestPath"
    $Response.StatusCode = [System.Net.HttpStatusCode]::OK
    $Response.StatusDescription = "OK"
    $Response.OutputStream.Close()

}
# Save a file sent to the server
Function Save-File($RawData){
    try{
        # Create temp file
        [System.IO.File]::WriteAllBytes($Path+"\"+"temp.dat", $RawData) | Out-null
        $Filename = (Get-Content "temp.dat" | Select-String "filename" | Out-String) -replace ".*filename=" -replace "`"",""
        if($filename -eq $null -Or $filename -eq ""){
            $Filename = "UnnamedFile"
        }
        Write-Log "Client sent file: $($Filename.Trim())" 1
        # Check for filename
        $i = 0
        while(Get-ChildItem "$Path"+"$Filename" -ErrorAction SilentlyContinue){
            $i++
            $Filename = "$i" + $Filename
        }
        # Write data to file
        $newline = 0
        $offset = 1
        foreach($x in $RawData){
            if($x -eq 13){
                $newline++
            }
            if($newline -eq 4){
                break;
            }
            $offset++
        }
        $MemoryStream = New-Object System.IO.MemoryStream
        $MemoryStream.Write($RawData, $offset, $RawData.length - $offset)
        $RawData = $MemoryStream.ToArray()
        $MemoryStream.Close()
        [System.Array]::reverse($RawData)
        $newline = 0
        $offset = 1
        foreach($x in $RawData){
            if($x -eq 13){
                $newline++
            }
            if($newline -eq 2){
                break
            }
            $offset++
        }
        $MemoryStream = New-Object System.IO.MemoryStream
        $MemoryStream.write($RawData, $offset, $RawData.Length - $offset)
        $RawData = $MemoryStream.ToArray()
        $MemoryStream.Close()
        [System.Array]::reverse($RawData)
        [System.IO.File]::WriteAllBytes($Path+"\"+$filename.trim(),$RawData[1..$RawData.Length]) | Out-null
        Write-Log "File written to: $($Path+"\"+$Filename.Trim())" 1
        return $true
    }
    catch{
        Write-Error "Could not save file! Check surrounding logs for information."
        Write-Log "ERROR: Could not save file! Check surrounding logs for information."
        return $false
    }
    # Return on success or failure
}
# Serve web content to the client [HTML,CSS,JS,PHP]
Function Serve-WebContent($Content){
    # Check if index should be served
    if($Content -eq "Index"){
        $fileinfo = New-Object System.IO.FileInfo($Index)
        if($FileInfo.Exists){
            Write-Log "Serving user selected index file" 1
            return Get-Content $Index
        }else{
            Write-Error "User selected index file could not be retieved."
            Write-Log "ERROR: User selected index file could not be retrieved." 1
            Write-Log "Serving default index." 1
            return Serve-Index
        }
    }
    Write-Log "Serving webcontent file: $Content" 1
    return Get-Content $Content
}
# Serve the generic index to the client
# Abstracting to a function to de-clutter the Core function
Function Serve-Index{
    # Serve Index 
    $Index = @"
    <HTML>
    <head>
    <style>
        html {
        padding: 50px 0;
        }

        html,
        body {
        height: 100%;
        overflow: hidden;
        }
        h1 {
        font-family: Arial, Helvetica, sans-serif;
        color: #ddd;
        }
        p {
        font-family: 'Courier New', Courier, monospace;
        color: #999;
        }
        pre {

        }
        a {
        color: #999;
        }
        body {
        font-family: Helvetica Neue, Helvetica, Arial, sans-serif;
        background: rgb(51, 51, 51);
        }

        #UploadBox.highlight {
        border-color: #007aff;
        }

        #UploadArea {
        background-color: #272727;
        padding: 20px;
        border-radius: 25px;
        width: 620px;
        margin: 0 auto;
        text-align: center;
        border-color: #000;
        display: none;
        }
        #DirectoryArea {
        background-color: #272727;
        padding: 20px;
        border-radius: 25px;
        width: auto;
        margin: 0 auto;
        border-color: #000;
        display: none;
        overflow: auto;
        }
        #CommandArea {
        background-color: #272727;
        padding: 20px;
        border-radius: 25px;
        width: auto;
        margin: 0 auto;
        border-color: #000;
        display: none;
        max-height: 60%;
        overflow-y: scroll;
        }
        #UploadBox {
        margin: 0 auto;

        border: 2px dashed transparent;
        background: #fff;
        border-radius: 15px;
        width: 500px;
        padding: 20px 20px 30px;

        background-color: #ddd;
        }
        input[type="file"]::file-selector-button {
        margin: 0 20px 10px 0;
        }

        #send {
        position: relative;
        right: 45%;
        }

        input[type="file"] {
        color: #999;
        width: 250px;
        }

        button,
        input[type="file"] {
        display: block;
        margin: 20px auto;
        font-size: 16px;
        }

        button,
        input[type="file"]::file-selector-button {
        padding: 8px 16px;
        background: #000;
        cursor: pointer;
        border-radius: 5px;
        border: 1px solid #000;
        color: #fff;
        }

        button:hover,
        input[type="file"]::file-selector-button:hover {
        background: #313131;
        transition: all 0.2s ease;
        }

        button,
        input[type="button"] {
        margin: 20px auto;
        font-size: 16px;
        }

        button,
        input[type="button"]{
        padding: 8px 16px;
        background: #000;
        cursor: pointer;
        border-radius: 5px;
        border: 1px solid #000;
        color: #fff;
        }

        button:hover,
        input[type="button"]:hover {
        background: #313131;
        transition: all 0.2s ease;
        }
    </style>
       <title>Simple PowerShell HTTP Server</title>
        <meta charset="UTF-8">
      </head>
<BODY>
<h1>Simple PowerShell HTTP Server</h1>
<p><a href="https://github.com/lpowell/SimplePowerShellHTTPServer" target="_blank">Learn more!</a></p>
<div id="HorizontalMenu">
<input id="Shutdown" type="button" value="Shutdown" onclick="Shutdown();" />
<input type="button" id="DirectoryList" value="Get Directory list" onclick="DirectoryRequest();">
<input type="button" id="FileManager" value="Transfer Files" onclick="FileAction();">
<input type="button" id="DirectoryList" value="ExecuteCommands" onclick="CommandExecution();">
</div>
<br />
<br />
<!-- <div id="LogOut">
    <input type="file" name="inputfile" id="inputfile" value="Choose log file">
    <br>
 
    <pre id="output"></pre>
</div> -->
<div id="UploadArea">
    <h1>Upload File</h1>
    <div id="UploadBox">
      <form method="post" enctype="multipart/form-data">
        <input id="file" name="file" type="file" />
        <button>Upload</button>
      </form>
    </div>
</div>
<div id="DirectoryArea">
    <pre><p id="DirectoryOut"></p></pre>
</div>
<div id="CommandArea">
    <div id="execute">
        <p>Execute a Command</p>
        <input id="Command" type="text" />
        <button onclick="SendCommand();" id="send">Execute</button>
    </div>
        <pre><p id="CommandOut"></p></pre>
</div>
<script>
    const LogOut = document.getElementById('inputfile');
    if(LogOut){
        LogOut.addEventListener('change', function () {
            var fr = new FileReader();
            fr.onload = function () {
                document.getElementById('output')
                    .textContent = fr.result;
            };
            fr.readAsText(LogOut.files[0]);
        });
    }
    function Shutdown(){
        const currentUrl = window.location.href;
        fetch(currentUrl, {
            method: "POST",
            body: JSON.stringify({
                userId: 1,
                title: "Shutdown",
                completed: false
            }),
            headers: {
                "Action": "Shutdown",
"@+(@"

                "x-api-key": "{0}"
"@ -f $APIKey)+@"
            }
        });
        alert("Server shutdown requested.");
        location.reload();
    }
    function DirectoryRequest(){
        document.getElementById("DirectoryArea").style.display = "block";
        document.getElementById("CommandArea").style.display = "none";
        document.getElementById("UploadArea").style.display = "none";
        const currentUrl = window.location.href;
        const textReplace = document.getElementById("DirectoryOut");
        fetch(currentUrl, {
            headers: {
                "Action": "DirectoryList",
"@+(@"

                "x-api-key": "{0}"
"@ -f $APIKey)+(@"
            }
        }).then(response => response.text()).then((response)=>{
            textReplace.textContent = response;
        });
    }
    function SendCommand(){
        const currentUrl = window.location.href;
        const textReplace = document.getElementById("CommandOut");
        fetch(currentUrl, {
            headers: {
                "Action": "CommandExecute",
                "Command": document.getElementById("Command").value,
"@)+(@"

                "x-api-key": "{0}"
"@ -f $APIKey)+@'
            }
        }).then(response => response.text()).then((response)=>{
            textReplace.textContent = response;
        });
    }
    function FileAction(){
        document.getElementById("DirectoryArea").style.display = "none";
        document.getElementById("CommandArea").style.display = "none";
        document.getElementById("UploadArea").style.display = "block";
    }
    function CommandExecution(){
        document.getElementById("DirectoryArea").style.display = "none";
        document.getElementById("CommandArea").style.display = "block";
        document.getElementById("UploadArea").style.display = "none";
    }
</script>
</BODY>
</HTML>
'@
    # Return to Serve-WebContent with index object
    return $Index
}
Function DisplayHelp{
@"

 .----------------.  .----------------.  .----------------.  .----------------. 
| .--------------. || .--------------. || .--------------. || .--------------. |
| |    _______   | || |   ______     | || |  ____  ____  | || |    _______   | |
| |   /  ___  |  | || |  |_   __ \   | || | |_   ||   _| | || |   /  ___  |  | |
| |  |  (__ \_|  | || |    | |__) |  | || |   | |__| |   | || |  |  (__ \_|  | |
| |   '.___``-.   | || |    |  ___/   | || |   |  __  |   | || |   '.___``-.   | |
| |  |``\____) |  | || |   _| |_      | || |  _| |  | |_  | || |  |``\____) |  | |
| |  |_______.'  | || |  |_____|     | || | |____||____| | || |  |_______.'  | |
| |              | || |              | || |              | || |              | |
| '--------------' || '--------------' || '--------------' || '--------------' |
 '----------------'  '----------------'  '----------------'  '----------------' 

A PowerShell implementation of the System.Net HttpListener class. Includes file transfer, remote administration, and basic web content functionality. 
See more at https://github.com/lpowell/SimplePowerShellHTTPServer.

USAGE GUIDE
SimplePowerShellHttpServer [SPHS] is primarily inteded to be used in local or testing environments. Do not use SPHS to serve content externally. There are few security considerations beyond basic operational authentications. 
SPHS does not support encrypted traffic or certificates. SPHS should not be used for secure file transfer.

To use SPHS, simply run the command 'Start-HttpServer'. This will bring the server up on *:80. To access the server, you may need to create firewall rules for external inbound access on the selected port. 
Optionally, various arguments and configuration profiles can be used to change default execution values. Find these listed below. Using 'Get-Help Start-HttpServer -Full' may provide addtional details not covered in this help section.

COMMAND ARGUMENTS
-URL
    The URL to bind the server to. Defaults to all interfaces. 
-PORT
    The port to bind the server to. Defaults to 80.
-APIKey
    The API key generated for authentication on administrative tasks. This is needed for shutdown requests, command execution, and directory retrieval. 
    Generates a random key by default.
-Index
    The index page to serve. Defaults to an example page.
-Path
    The operational path of the server. Defaults to the operational directory at execution. 
-LOGFILE
    Enable logging to a specified file. Default log file is SPHS.log.
-LOGLEVEL
    LOG LEVELS
    1....OPERATIONAL
    2....SECURITY
    3....ALL

    OPERATIONAL LOGS [DEFAULT]
    Logs dealing with basic server operations.
    Errors are written to both the error log and the OPERATIONAL log. 

    SECURITY LOGS
    Logs dealing with connection requests and responses.
    Expands headers, Addresses, and other identifying information.
    Includes OPERATIONAL logs. 

    ALL
    All logs, including extraneous operational logs
-VERBOSE
    Display logs on console. Follows log level. 
"@
    return
}
# Core/Main
Function Server-Core{
    # Check for compatability
    if([int](Get-Host).Version.Major -le 6){
        Write-Log "The active session version is less than 6. SPHS recommends PowerShell 7 or higher for full compatability." 1
    }
    # Check for loaded profile
    if($Load){
       $Server = Load-Server
    }else{
       $Server = Start-Server
    }
    :Server While($Server){
        # Listen for requests
        $Context = $Server.GetContext()

        # Process request result
        $Request = Handle-Request $Context.Request

        # Exit when server is terminated
        if(@($Request) -in "Shutdown"){
            $Server.Stop()
            break Server
        }        

        # Handle response object
        Send-Response $Context.Response @($Request)
    }
    Write-Log "Server shutting down..." 1
}
# Exported module function
Function Start-HttpServer{
    [cmdletbinding()]
    param(
        # URL
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,HelpMessage="The url to bind to. Defaults to * if left blank.")]
        [string]
        $URL='*',
        # Port
        [Parameter(Mandatory=$false,ValueFromPipeline=$True,HelpMessage="The port to bind to. Defaults to 80 if left blank.")]
        [string]
        $port='80',
        [Parameter(Mandatory=$false,ValueFromPipeline=$True,HelpMessage="The port to bind to for https. Defaults to 443 if left blank.")]
        [string]
        $sslport='443',
        # Log File
        [Parameter(Mandatory=$false,HelpMessage="File to store the logs. Defaults to documents.")]
        [string]
        $LogFile="SPHS.log",
        [Parameter(Mandatory=$False,HelpMessage="Logging level 1-3. Defaults to 1.")]
        [int]
        $LogLevel,
        # Index specification
        [Parameter(Mandatory=$false,HelpMessage="Specify an html to serve as the index file. Must be an absolute path.")]
        [string]
        $Index,
        [Parameter(Mandatory=$False,HelpMessage="Specify a custom API key for authentication. Used when executing commands. A generated key will be shown by default.")]
        [string]
        $APIKey= -join ((65..90)+(97..122)|Get-Random -count 10| %{[Char]$_}),
        [Parameter(Mandatory=$false,HelpMessage="The path the server should operate out of. Must be an absolute path. Defaults to the operating directory.")]
        [string]
        $Path=(Get-Location).Path,
        [Parameter(Mandatory=$False,HelpMessage="A JSON configuration file containing server settings to be loaded. See the github page for more information.")]
        $Load,
        [Parameter(Mandatory=$False,HelpMessage="Display the help and information page.")]
        [switch]
        $Help
    )
    if($Help){
        DisplayHelp
        return
    }
    # Check Admin
    if(Test-Admin){
        Server-Core
    }else{
        Write-Log "ERROR: SPHS must be run in an admin session." 1
        Write-Error "SPHS must be run in an admin session."
        exit
    }
}

Export-ModuleMember -Function Start-HttpServer