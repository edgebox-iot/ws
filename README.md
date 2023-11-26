![Edgebox Logo Image](https://adm-listmonk.edgebox.io/uploads/logo_transparent_horizontal_300x100.png)
# ws

Web Service Container Orchestration and proxy pass system for Edgebox.
Curious about what the Edgebox is? Check out our [website](https://edgebox.io)!

## Installation

This repository should automatically be installed on the Edgebox system setup repository for the target Edgebox platform (`multipass-cofig`, `ua-netinst-config`, `image-builder`)
In this case, it will be located in `/home/system/components/ws`.

If you have a custom Edgebox setup, or for detached usage, you can install this repository manually by running the following commands:
```bash
cd /home/system/components/ws
git clone https://github.com/edgebox-iot/ws.git
```

## Usage

Make sure you run the following commands from the root of this repository.


### Build

```bash
$ ./ws -b
```

This will go through each folder in the `/home/system/components/apps/` folder ([Check the `apps` repo for more information on the structure of an app](https://github.com/edgebox-iot/apps)), and configure the containers for each valid app entry. 
After running this command, You should have a `docker-compose.yml` file in the the root of this repository (it is git igored) with the final generated configuration which will then be used to spawn the containers via the `docker-compose up -d` command.
The containers will also automatically start, and be available on the configured `VIRTUAL_HOST` of each app.

Aditionally, this module also configures any folder on `/home/system/compoennts/` folder that contains an `edgebox-compose.yml` file, and starts the containers too.
These folders are not considered apps, and instead are internal components of the Edgebox system that need to run as containers, [such as `api`](https://github.com/edgebox-iot/api), or the proxy pass system that is also present in this repo (check the `edgebox-compose.yml` file in this repo for more information on how its configured).

### Clean

```bash
$ ./ws -c
```

This cleans the `module-configs` folder, removing any generated `docker-compose.yml` files and accompanying service definition files `<appname>.yml``. Ideal when developing to clearn any caches and make sure all generated config files are fresh. 
