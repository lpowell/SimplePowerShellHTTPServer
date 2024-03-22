# Simple PowerShell HTTP Server
A module for creating an HTTP server. SPHS will serve the index.html file in the directory it's run in by default. This can be overridden to any specified file. SPHS will also allow file upload and download. Any GET request for a file within the directory that SPHS is run will transfer the file. 

The following will attempt to download a file called blue.txt from the server.
    
    curl 192.168.10.1:1234/blue.txt --output blue.txt
    
Uploading files was a function designed for a specific purpose within a personal project. Because of this, uploads must be formatted as the following.
   
    Invoke-WebRequest 192.168.10.1:1234 -method PUT -InFile red.txt -Headers @{"Name"="red.txt"}
    
If no name header is specified, SPHS will save the file with a default name with no extension. 

SPHS logs to the console by default. Optionally, a log file can also be specified. The default log file location is MyDocuments\SPHSLog.txt. Log times are in UTC. Logs are somewhat verbose, and will be worked on in the future. 


To shutdown the server, send a post request with header Action and value Shutdown.
    Invoke-WebRequest 192.168.10.1:1234 -Method POST -Headers @{"Action"="Shutdown"}

## Full usage
Parameters:
* URL
  * The url to bind to. Defaults to * if left blank.
* Port
  * The port to bind to. Defaults to 80 if left blank.
* Logging
  * Enable output logging. Times are UTC.
* LogOutput
  * File to store the logs. Defaults to documents.
* Index
  * Specify an index.html file.
