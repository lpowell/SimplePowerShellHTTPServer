# Simple PowerShell Http Server
SPHS is a PowerShell implementation of the .Net HttpListener class. SPHS includes a simple file upload/download system, HTTP and web content server, and remote command execution abilities. The primary function of SPHS is to provide a simple method for local testing of systems and functions that require HTTP. SPHS is not intended to be used in secure or production environments. 

## Overview
The primary method of use is through the `Start-HttpServer` startup command. This will attempt to create an http server with the following default bindings:

```
{
    URL: *,
    Port: 80,
    APIKey: Default,
    Index: Default,
    Path: Default,
    LogFile: Default,
    LogLevel: Default
}
```
To exapnd on this, the basic server startup creates an HttpListener session that binds to all available addresses on port 80. The operational path is set to the working directory, the index default will be served, and logging is set to operational logging only. 

These parameters can be set on execution or loaded via a JSON configuration file in the above format.

Currently SSL is not *officially* supported. However, there is SSL support baked into the code itself. *Theoretically*, with a proper certificate set up, SSL *should* work. This has not been tested. 

## HTML and Web Content 
SPHS serves as a limited, but functional, HTML and web content server. By default, SPHS will attempt to serve .html, .js, ,.css, and .php, files as web content. This allows SPHS to serve simple websites. 

Media files are not yet supported. Most images, gifs, and short form media *should* work fine. However, large media and videos will not load correctly. These files can still be downloaded from the server using the download functionality. 

File paths are handled automatically, and SPHS uses the preconfigured Path parameter to determine where files are located. Examples of file handling and web content serving can be found in the default index in the script. 

## File Upload and Download
Files can be uploaded and downloaded from the server. There are several methods for uploading and downloading thatare supported. Both CLI and browser functionalities exist. In the case of extremely large files, there may be some issues not encountered during testing.

### Upload
Files can be uploaded through the upload example in the default index. They can also be uploaded through the CLI using a PUT request or a file. Files uploaded through the CLI must include a 'Name' header or they will be saved as a data file.

`Invoke-WebRequest -Method PUT -Uri 127.0.0.1:80 -InFile foo.txt -Headers @{"Name"="foo.txt"}`

Uploads using the sample index use POST requests via the HTML `<form>` tag to send data to the server.

### Downloads
Files can be downloaded by simply browsing to the location in any web browser. They can also be pulled from the server through the CLI using any standard GET request.

`curl 127.0.0.1:80/bar.txt --output bar.txt`

## Remote Command Execution
SPHS supports remote command execution on the local machine through the use of the generated API key value. The sample index contains an example field for executing and retrieving commands from the server. Commands return a string containing the result.

`curl 127.0.0.1:80 -H "Action: CommandExecute" -H "Command: Get-Process" -H "x-api-key: <key>"`

The available commands are:
* CommandExecute
* DirectoryList
* Shutdown


## CLI Usage
The cmdlet is called `Start-HttpServer` and includes a full `Get-Help` page with examples. 

The available CLI parameters are:
* URL
    * The address to bind to during execution. Defaults to all addresses.
* Port
    * The port to bind to during execution. Defaults to 80.
* SSLPort
    * *This is not currently supported.* Defaults to port 443.
* LogFile
    * The file logs are written to. Defaults to SPHS.log.
* LogLevel
    * The level of logging to use during execution.
    * LOG LEVELS
        * OPERATIONAL
        * SECURITY
        * ALL
* Index
    * The HTML index page to serve. Defaults to the included html page.
* APIKey
    * The API key used to execute commands on the server. Defaults to a random key that is printed to the console on startup.
* Path
    * The path the server should operate out of. Defaults to the working directory.
* Load
    * Used to load JSON configuration files.
* Help
    * Displays a help page.




## Logging
SPHS supports three levels of logging. These increase in verbosity. To display logs in the console, use the `-Verbose` switch during invocation.


OPERATIONAL LOGS [DEFAULT]

Logs dealing with basic server operations.
Errors are written to both the error log and the OPERATIONAL log. 

SECURITY LOGS

Logs dealing with connection requests and responses.
Expands headers, Addresses, and other identifying information.
Includes OPERATIONAL logs. 

ALL

All logs, including extraneous operational logs