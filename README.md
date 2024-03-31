# Simple PowerShell HTTP Server
A module for creating an HTTP server. SPHS is written entirely in PowerShell and uses the System.Net.HttpListener .Net class to operate. SPHS can be served on any port. It functions as a file upload/download option and a basic HTTP server for serving web content. Future work will see these options expand and improve. SPHS started as a PowerShell native solution for another [project](https://github.com/lpowell/PowerShellMalwareExamples/tree/main/ExampleSamples) but has evolved into its own work. SPHS requires PowerShell 6+, preferably PowerShell 7+. 


## File Upload
Files can be uploaded via post requests. An example is included in the provided index.html page. File upload can be sent through the command line as well, using either POST or PUT requests. Command line requests must include a name header.
    
PUT Request
    
    Invoke-WebRequest 192.168.10.1:1234 -method PUT -InFile red.txt -Headers @{"Name"="red.txt"} 

POST Request
    
    Invoke-WebRequest 192.168.10.1:1234 -method POST -Infile red.txt -Headers @{"Name"="red.txt"}

## File Download
Files can be downloaded from the command line or through the browser. For example, browsing to http://localhost/red.txt will result in the server sending red.txt for download. SPHS serves files in the directory it's running in. Files may also be downloaded from the command line.

GET Request
   
    curl 192.168.10.1:1234/blue.txt --output blue.txt

## Command Execution
Commands can be executed in the current scope by submitting any request with the Action and Command headers. This must be enabled by starting the server with the CommandExecute switch. Commands cannot be executed by default. Commands can be executed from the command line or the included index page.

Example request

    curl 192.168.10.1:1234 -H "Action: CommandExecute" -H "Command: Get-Process"

The server directory can also be queried via command line or index. This operation is separate from command execution and cannot currently be turned off. 

Example request

    Invoke-WebRequest 192.168.10.1:1234 -Headers @{"Action"="DirectoryList"}

All command execution results are returned as strings.  

## Server Operation
The server can be shut down by sending any request with the Action header. Additionally, the sample index page includes a shutdown button.

Server shutdown

    Invoke-WebRequest 192.168.10.1:1234 -Method POST -Headers @{"Action"="Shutdown"}

SPHS logs to the console by default. Currently, this cannot be turned off. Optionally, SPHS can log to a file. Use the -Logging switch to enable file output, and the -LogOutput argument to specify a log file. By default, SPHS will log to SPHSLog in the current directory. Logs are in UTC and are quite verbose. Error logs are stored in the same file at the moment. 

HTML, CSS, PHP, and Javascript files are served to the browser when a GET request is sent. This allows for normal browsing of web pages. Visiting http://localhost/<example\>.html will display the web page over downloading the file. Notable exclusions are images and media files. Browsing or requesting these resources will download them instead of displaying them in the browser. This limitation may be worked on in the future.

## Roadmapping
This is the current roadmap/feature list I'm looking at adding. Not all of these will get done, others may also be added. At the time of writing, Dragon's Dogma 2 has just been released. My work efficiency is about to drop to 0. 
* Create randomized API key to authenticate communications
  * Use for commands, direwctory listing, and upload/download. Various levels of strictness.
* JSON configuration support
  * Deploy from config 
* Add firewall rule creation switch
  * Currently, manual firewall rules need to be created to allow for external access
* Add further Action headers
  * ~~Directory list function~~
  * ~~Remote code execution option~~
    * Available as a switch, turned off by default
* Built-out media viewer
* SSL/TLS
  * This is more of a way out there, I feel insane, sort of thing
* Executable release 


## Full usage 
The code is documented to provide as much clarity as possible. At some point, full documentation might be made. However, for now, the module help information is pretty informative on usage. Use `Get-Help Start-HttpServer -Full` to list the built-in help. Or, just look at it in the top of the function declaration. 

### Parameters:
* URL
  * The URL to bind to. Defaults to * if left blank.
* Port
  * The port to bind to. Defaults to 80 if left blank.
* Logging
  * Enable output logging. Times are UTC.
* LogOutput
  * File to store the logs. Defaults to documents.
* Index
  * Specify an index.html file.
* CommandExecute
  * Allow users to execute commands against the server. 
