
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
        $LogOutput=[Environment]::GetFolderPath("MyDocuments")+"PoShttpLog.txt"
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
                    # Test if the file exists
                    if([System.IO.File]::Exists($RequestPath)){
                        Write-Log "File exists"
                        # Attempt to send the file.
                        try {
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
                    # If no file is requested, serve the default page.
                    }elseif(((($Request.Url).ToString()) -replace ".*/") -le 1){
                        Write-Log "Serving index file."
                        if([System.IO.File]::Exists((Get-Location).Path+"\"+"index.html")){
                            [string] $responseString = Get-Content "index.html"
                        }else{
                            [string] $responseString = "<HTML><p>Testing!</p></HTML>"
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
                    # Something might happen here at some point. 
                    # I don't use post for anything other than shutdown commands atm. 
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
                Default {}
            }
        }
    }
    Write-Log "Stopping server..."
    # Close server
    $Listener.Stop()
    Write-Log "Server stopped."
}

Export-ModuleMember -Function Start-HttpServer 