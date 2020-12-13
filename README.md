# ws

Edgebox Dynamic Web Service via nginx Reverse Proxy for subdirectory access to containers

## How to use

 - Clone this repo to a working folder (eg: ~/edgebox/)
 - Clone any other necessary modules (Eg. edgebox-iot/api) that are compatible with edgebox-compose structure, to the same working folder.
 - Inside of this repository (eg: ~/edgebox/ws) run ./ws --build
 - Once the process is complete, run ./ws --start

## TODO

 - Way more information on the inner workings of this module and why it is organized like this.
 - Support for SSL and other stuff... Good enough for development right now.