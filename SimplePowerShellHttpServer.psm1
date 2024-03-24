
function Write-Log([string]$LogMessage)
{
    $MessageTime = [System.DateTime]::UTCNow 
    Write-Output "$MessageTime`t$LogMessage"
    if($Logging){
        "$MessageTime`t$LogMessage" | Out-File -Path $LogOutput -Append
    }
}
function Start-HttpServer{
<#
    .SYNOPSIS
Simple PowerShell HTTP Server.

.DESCRIPTION
Simple PowerShell HTTP Server creates an HTTP server on any specified address and port. It will load an index.html file and allow file transfers between the server and client. 

.PARAMETER URL
The url to bind to. Defaults to * if left blank.

.PARAMETER Port
The port to bind to. Defaults to 80 if left blank.

.PARAMETER Logging
Enable output logging. Times are UTC.

.PARAMETER LogOutput
File to store the logs. Defaults to documents.

.PARAMETER Index
Specify an index.html file.


.Example 
    # Start a server on localhost:80.
    Start-HttpServer

.Example
    # Start a server on a specified address and port.
    Start-HttpServer -Url 192.168.10.1 -port 1234

.Example 
    # Enable logging to log.txt
    Start-HttpServer -Logging -LogOutput log.txt
    
#>
    param(
        # URL
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,HelpMessage="The url to bind to. Defaults to * if left blank.")]
        [string]
        $URL='*',
        # Port
        [Parameter(Mandatory=$false,ValueFromPipeline=$True,HelpMessage="The port to bind to. Defaults to 80 if left blank.")]
        [string]
        $port='80',
        # Logging
        [Parameter(Mandatory=$false,HelpMessage="Enable output logging. Times are UTC.")]
        [switch]
        $Logging,
        # Log File
        [Parameter(Mandatory=$false,HelpMessage="File to store the logs. Defaults to documents.")]
        [string]
        $LogOutput=[Environment]::GetFolderPath("MyDocuments")+"SPHSLog.txt",
        # Index specification
        [Parameter(Mandatory=$false,HelpMessage="Specify an index.html file.")]
        [string]
        $Index
    )
    # Initialize server
    Write-Log "Starting server..."
    # Create prefix from arguments
    $prefix = "http://"+$URL+":"+$port+"/"
    # Attempt to start the listener
    try {
        $Listener = New-Object System.Net.HttpListener
        $Listener.Prefixes.Add($prefix)
        $Listener.Start()
    }
    # Write error logs as needed
    catch [System.Net.HttpListenerException] {
        Write-Log "Caught HttpListenerException exception"
        Write-Log "Server aborted. Check errors."
        Write-Log ($_.ScriptStackTrace).ToString()
        Write-Log ($_.Exception).ToString()
        Write-Log ($_.FullyQualifiedErrorId).ToString()
        exit
    }
    catch
    {
        Write-Log "Caught unexpected exception"
        Write-Log "Server aborted. Check errors."
        Write-Log ($_.ScriptStackTrace).ToString()
        Write-Log ($_.Exception).ToString()
        Write-Log ($_.FullyQualifiedErrorId).ToString()
        exit
    }

    # Test if server is listening on the right port & URL
    # If default URL, this will find all connections on $port
    if(Get-NetTCPConnection -LocalPort $port -LocalAddress $URL -State Listen){
        Write-Log "Server is running at $Prefix"
    }else{
        Write-Log "Server failed to initialize. Check errors."
        Write-Log $error[0].ToString()
        Write-Log "Stopping server..."
        # Close server
        $Listener.Stop()
        exit
    }

    # Prepare to receive requests
    while($true){
        $Context = $Listener.GetContext()
        $Request = $Context.Request
        Write-Log "Request recieved from: $($Request.RemoteEndPoint)"
        $RequestDetails = @(
            # Expand details like headers at some point
            # write-host $request.Headers["Content-Type"]
            # foreach($x in ($request.headers.AllKeys)){
            #     write-host $x -ForegroundColor red
            #     write-host $request.headers.GetValues($x)
            # }
            "`t`t`t`tLocalEndPoint: $($Request.LocalEndPoint)`n"
            "`t`t`t`tURL: $($Request.Url)`n"
            "`t`t`t`tUserAgent: $($Request.UserAgent)`n"
            "`t`t`t`tHTTPMethod: $($Request.HttpMethod)`n"
            "`t`t`t`tHeaders: $($Request.Headers)`n"
            "`t`t`t`tCookies: $($Request.Cookies)`n"
            "`t`t`t`tInputStream: $($Request.InputStream)"
        )
        Write-Log "Request details:`n$($RequestDetails)"
        # Switch to case for added actions
        if(($Request.Headers["Action"]) -And $Request.Headers["Action"] -eq "Shutdown"){
            Write-Log "Shutdown requested"
            break
        }else {
            # Get response object
            $Response = $context.Response
            # Respond to request
            switch ($Request.HttpMethod) {
                # Serve an index page or transfer local files. 
                # There is no security bundled with the file transfer, do not use this for secure environments.
                "GET" { 
                    # Build the request path by stripping the url prefix 
                    $RequestPath=(Get-Location).Path + "\" + ((($Request.Url).ToString()) -replace ".*/")
                    Write-Log "Client requested file:$RequestPath"
                    # Create a fileinfo object
                    $RequestFileInfo = New-Object System.IO.FileInfo($RequestPath)
                    # Test if the file exists
                    if($RequestFileInfo.Exists){
                        Write-Log "File exists"
                        # Test if file should be served as webpage
                        if($RequestFileInfo.Extension -in (".html",".php",".js",".css")){
                            Write-Log "Serving file as webpage"
                            # Get file contents
                            [string] $responseString = Get-Content $RequestPath
                            # Create buffer for response
                            [byte[]] $Buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
                            # Set content length to the buffer size
                            $Response.ContentLength64 = $Buffer.Length
                            # Create an output stream to send the response
                            [System.IO.Stream] $Output = $Response.OutputStream
                            # Send response
                            $Output.Write($Buffer,0,$Buffer.Length)
                            # Close output stream
                            $Output.Close()
                        }else{
                            # Attempt to send the file.
                            try {
                                Write-Log "Sending file as download"
                                # Create a filestream object for reading the desired file
                                [System.IO.FileStream] $FileStream = New-Object System.IO.FileStream($RequestPath, "Open")
                                $filename = ($RequestPath | Get-Item).Name
                                $Response.ContentLength64 = $FileStream.Length
                                $Response.SendChunked = $false
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
                            catch {
                                Write-Log "Something went wrong. Check errors."
                                Write-Log ($_.ScriptStackTrace).ToString()
                                Write-Log ($_.Exception).ToString()
                                Write-Log ($_.FullyQualifiedErrorId).ToString()
                                # Catch on error and terminate active stream objects
                                $BinaryWriter.Close()
                                $FileStream.Close()
                                # Send a BadRequest status if the send fails for any reason.
                                $Response.StatusCode = [System.Net.HttpStatusCode]::BadRequest
                                $Response.StatusDescription = "BadRequest"
                                $Response.OutputStream.Close()
                            }
                        }
                    # If no file is requested, serve the default page.
                    }elseif(((($Request.Url).ToString()) -replace ".*/") -le 1){
                        Write-Log "Serving index file."
                        $DefaultIndex =@'
<HTML>
    <head>
        <title>How to Upload Files with JavaScript</title>
        <meta charset="UTF-8">
        <link rel="stylesheet" type="text/css" href="styles.css">
        <link rel="icon" href="../images/favicon-32x32.png" type="image/png">
      </head>
<BODY>
<h1>Simple PowerShell HTTP Server</h1>
<p><a href="https://github.com/lpowell/SimplePowerShellHTTPServer" target="_blank">Learn more!</a></p>
<input id="Shutdown" type="button" value="Shutdown" onclick="Shutdown();" />
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
                "Action": "Shutdown"
            }
        });
        alert("Server shutdown requested.");
        location.reload();
    }
</script>
</BODY>
</HTML>
'@
                        if($Index){
                            if(-Not [System.IO.File]::Exists($Index)){
                                # try and see if it's in the local directory
                                $loc = (Get-Location).Path + "\" + $Index
                                if([System.IO.File]::Exists($loc)){
                                    [string] $responseString = Get-Content $loc
                                }else{
                                    [string] $responseString = $DefaultIndex
                                }                                

                            }else{
                                [string] $responseString = Get-Content $Index
                            }
                        }elseif([System.IO.File]::Exists((Get-Location).Path+"\"+"index.html")){
                            [string] $responseString = Get-Content "index.html"
                        }else{
                            Write-Log "Could not find the specified index. Serving the default page."
                            [string] $responseString = $DefaultIndex
                        }
                        # Create buffer for response
                        [byte[]] $Buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
                        # Set content length to the buffer size
                        $Response.ContentLength64 = $Buffer.Length
                        # Create an output stream to send the response
                        [System.IO.Stream] $Output = $Response.OutputStream
                        # Send response
                        $Output.Write($Buffer,0,$Buffer.Length)
                        # Close output stream
                        $Output.Close()
                    # If a file is requested, but not found, send an error. 
                    }else{
                        Write-Log "File does not exist. Closing connection."
                        [string] $responseString = "<HTML><p>File not found.</p></HTML>"
                        # Create buffer for response
                        [byte[]] $Buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
                        # Set content length to the buffer size
                        $Response.ContentLength64 = $Buffer.Length
                        # Create an output stream to send the response
                        $Response.StatusCode = [System.Net.HttpStatusCode]::NotFound
                        $Response.StatusDescription = "NotFound"
                        [System.IO.Stream] $Output = $Response.OutputStream
                        # Send response
                        $Output.Write($Buffer,0,$Buffer.Length)
                        # Close output stream
                        $Output.Close()
                    }
                }
                "POST" { 
                    # Create a MemoryStream object to store the InputStream
                    $memStream = New-Object System.IO.MemoryStream
                    # Copy the input stream to the memory stream
                    $Request.InputStream.CopyTo($memStream)
                    # Create a byte array from the memory stream
                    [byte[]] $data = $memStream.ToArray() 
                    # Close the memory stream
                    $memStream.Close()
                    # Write the byte array to a temp file
                    [System.IO.File]::WriteAllBytes((Get-Location).Path+"\"+"temp.dat",$data) | Out-null
                    # Read the filename from the temp file
                    $datafilename = (Get-Content "temp.dat" | Select-String "filename" | Out-String) -replace ".*filename=" -replace "`"",""
                    write-log "Client sent file: $($datafilename.Trim())"
                    # Find the starting offset of the data by enumerating expected carriage returns
                    # This is designed with the sample index in mind.
                    $newline = 0
                    $offset = 1
                    foreach($x in $data){
                        # find four newlines and get offset
                        if($x -eq 13){
                            $newline ++
                        }
                        if($newline -eq 4){
                            break;
                        }
                        $offset ++
                    }
                    # New memory stream for trimmed data
                    $memStream = New-Object System.IO.MemoryStream
                    # Write the trimmed data to the memory stream
                    $memStream.write($data, $offset, $data.Length - $offset)
                    # replace data array with trimmed data
                    $data = $memStream.ToArray()
                    # close the memory stream
                    $memStream.Close()
                    # reverse data array
                    [System.array]::reverse($data)
                    # Find the offset of the last 2 cr 
                    $newline = 0
                    $offset = 1
                    foreach($x in $data){
                        if($x -eq 13){
                            $newline++
                        }
                        if($newline -eq 2){
                            break;
                        }
                        $offset++
                    }
                    # New memory stream for trimmed data
                    $memStream = New-Object System.IO.MemoryStream
                    # Write data to stream
                    $memStream.write($data, $offset, $data.Length - $offset)
                    # replace data array
                    $data = $memStream.ToArray()
                    $memStream.Close()
                    # reverse data array
                    [System.Array]::reverse($data)
                    # write raw bytes to the correct file
                    [System.IO.File]::WriteAllBytes((Get-Location).Path+"\"+$datafilename.trim(),$data[1..$data.length]) | Out-null
                    Write-Log "File written to: $((Get-Location).Path+"\"+$datafilename.trim())"
                    # If the post request came from the sample index, don't send a response
                    if(!$Request.Headers['sec-ch-ua']){
                        $Response.StatusCode = [System.Net.HttpStatusCode]::OK
                        $Response.StatusDescription = "OK"
                        $Response.OutputStream.Close()
                    }else{
                        write-log "Redircted client to base url: $($Request.URL)"
                        $response.Redirect($request.Url)
                        $Response.OutputStream.Close()
                    }
                }
                "PUT" { 
                    # Create name based on passed header
                    Write-Log "Client is sending a file for upload"
                    if($Request.Headers["Name"]){
                        $writeName = $Request.Headers["Name"]
                        Write-Log "Received file name: $writeName"
                    }else{
                        $writeName = "SavedFile"
                    }
                    $writePath = (Get-Location).Path + "\" + $writeName
                    try {
                        # Create a filestream object for writing 
                        $fsWrite = New-Object System.IO.FileStream($writePath, "Create")
                        Write-Log "File created at: $writePath"
                        # Create a MemoryStream object to store the InputStream
                        $memStream = New-Object System.IO.MemoryStream
                        $Request.InputStream.CopyTo($memStream)
                        [byte[]] $data = $memStream.ToArray()
                        # Write the data to file
                        $fsWrite.Write($data, 0, $data.Length)
                        $fsWrite.Close()
                        $memStream.Close()
                        Write-Log "File saved at: $writePath"
                        $Response.StatusCode = [System.Net.HttpStatusCode]::OK
                        $Response.StatusDescription = "OK"
                        $Response.OutputStream.Close()
                    }
                    catch {
                        # Catch on error and terminate stream objects
                        Write-Log "Something went wrong. Check errors."
                        Write-Log ($_.ScriptStackTrace).ToString()
                        Write-Log ($_.Exception).ToString()
                        Write-Log ($_.FullyQualifiedErrorId).ToString()
                        $fsWrite.Close()
                        $memStream.Close()
                    }
                }
                "HEAD" {
                    $Response.StatusCode = [System.Net.HttpStatusCode]::OK
                    $Response.StatusDescription = "OK"
                    $Response.OutputStream.Close()
                }
                Default {
                    # Default not found if no specific handler created
                    $Response.StatusCode = [System.Net.HttpStatusCode]::NotFound
                    $Response.StatusDescription = "NotFound"
                    $Response.OutputStream.Close()
                }
            }
        }
    }
    Write-Log "Stopping server..."
    # Close server
    $Listener.Stop()
    Write-Log "Server stopped."
}

Export-ModuleMember -Function Start-HttpServer 