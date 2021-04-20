#!/bin/sh
set -e
PROGNAME=$(basename $0)
die() {
    echo "$PROGNAME: $*" >&2
    exit 1
}

usage() {
    if [ "$*" != "" ] ; then
        echo "Error: $*"
    fi
    cat << EOF

Usage: $PROGNAME [OPTION ...] [foo] [bar]

-------------------------------------------------------------
|  CLI tool for building and managing the ws functionality  |
-------------------------------------------------------------

Options:
-h, --help               display this usage message and exit
-b, --build              build global docker-commpose file
-c, --clean              clean appdata directory
-s, --start              docker-compose up -d
-l, --logs [SERVICE]     docker-compose logs for [SERVICE]
-r, --restart [SERVICE]  docker-compose restart [SERVICE]
-k, --kill               docker-compose down
-o, --output [FILE]      write output to file

EOF
    exit 1
}

run_postinstall() {
    POSTINSTALL_FILE="./module-configs/postinstall.txt"
    if test -f "$POSTINSTALL_FILE"; then
    echo "Waiting for Container Warmups before running post-install operations..."
    sleep 60
    echo "Executing post-install operations"
    while IFS= read -r line
    do
        echo " -> docker-compose exec $line"
           docker-compose exec $line &
        wait
    done < "$POSTINSTALL_FILE"
    fi
}

get_lan_ip () {
    for adaptor in eth0 wlan0; do
        if ip -o -4 addr list $adaptor  > /dev/null 2>&1 ; then
            ip=$(ip -o -4 addr list $adaptor | awk '{print $4}' | cut -d/ -f1)
        fi
    done

    echo $ip
}

clean () {
    echo "Cleaning all data from appdata"
    sudo rm -rf appdata/*
}

publish_mdns_entries() {
    config_name="edgebox-hosts.txt"
    domain=".edgebox.local"
    local_ip=$(get_lan_ip)
    if command -v avahi-publish -h &> /dev/null; then
        echo "Publishing mDNS service entries for modules to ${local_ip}"
        for d in ../*/ ; do
            HOSTS_FILE="$d$config_name"
            SERVICE_NAME="$(basename $d)"
            if test -f "$HOSTS_FILE"; then
                echo "Found configuration for $SERVICE_NAME service"
                while IFS= read -r line; do
                    avahi-publish -a -R $line$domain $local_ip &
                    sleep 3
                done < "$HOSTS_FILE"
            fi
        done
    
        echo "Publishing mDNS service entries for edgeapps to ${local_ip}"
        for d in ../apps/*/ ; do
            HOSTS_FILE="$d$config_name"
            SERVICE_NAME="$(basename $d)"
            if test -f "$HOSTS_FILE"; then
                echo "Found configuration for $SERVICE_NAME edgeapp"
                while IFS= read -r line; do
                    avahi-publish -a -R $line$domain $local_ip &
                    sleep 3
                done < "$HOSTS_FILE"
            fi 
        done

    fi
}

kill_mdns_entries() {
    echo "Killing mDNS service entries"
    pkill avahi-publish
}

setup_myedgebox_tunnel() {
    
    echo "Setting up myedgeapp service"

    MYEDGEAPP_TOKEN = `cat /home/system/.myedgeapp_token`

    if [ "$MYEDGEAPP_TOKEN" = "<REPLACE_THIS_WITH_TUNNEL_ACCESS_TOKEN>" ]; then
        read -p "No myedge.app access token found in installation. Please provide one: " MYEDGEAPP_TOKEN
    else
        echo "Token found - Setting up."        
    fi

    # TODO: Send Request to boot-node to obtain available prefix, and so it can automatically setup etcd and traefik to correctly route the domains.


    sudo tinc-boot gen --token $MYEDGEAPP_TOKEN 157.230.110.104:8655 # Help Wanted: Enable connection to boot-node via domain (myedge.app) or have secure way of setting up origin ip directly
    sudo systemctl start tinc@dnet
    sudo systemctl enable tinc@dnet
}

foo=""
bar=""
setup=0
output="-"
while [ $# -gt 0 ] ; do
    case "$1" in
    -h|--help)
        usage
        ;;
    -b|--build)
        build=1
        config_name="edgebox-compose.yml"
        env_name="edgebox.env"
        postinstall_file="edgebox-postinstall.txt"
        global_composer="docker-compose"
    
        if test -f ./module-configs/postinstall.txt; then
            rm module-configs/postinstall.txt
        fi
    
        touch module-configs/postinstall.txt

        for d in ../*/ ; do
            # Iterating through each one of the directories in the "components" dir, look for edgebox-compose service definitions...
            EDGEBOX_COMPOSE_FILE="$d$config_name"
            EDGEBOX_ENV_FILE="$d$env_name"
            EDGEBOX_POSTINSTALL_FILE="$d$postinstall_file"
        if test -f "$EDGEBOX_COMPOSE_FILE"; then
        echo " - Building $(basename $d) module"
                global_composer="${global_composer} -f ./module-configs/$(basename $d).yml"
                BUILD_ARCH=$(uname -m) docker-compose --env-file=$EDGEBOX_ENV_FILE -f $EDGEBOX_COMPOSE_FILE config > module-configs/$(basename $d).yml
        fi
        if test -f "$EDGEBOX_POSTINSTALL_FILE"; then
            echo " - Building $(basename $d) post-install"
            cat $EDGEBOX_POSTINSTALL_FILE >> ./module-configs/postinstall.txt
        fi

        done

        for d in ../apps/*/ ; do
            # Now looking specifically for edgeapps... If they follow the correct package structure, it will fit seamleslly.
            EDGEBOX_COMPOSE_FILE="$d$config_name"
            EDGEBOX_ENV_FILE="$d$env_name"
            EDGEBOX_POSTINSTALL_FILE="$d$postinstall_file"
            if test -f "$EDGEBOX_COMPOSE_FILE"; then
                echo " - Building EdgeApp -> $(basename $d)"
                global_composer="${global_composer} -f ./module-configs/$(basename $d).yml"
                BUILD_ARCH=$(uname -m) docker-compose --env-file=$EDGEBOX_ENV_FILE -f $EDGEBOX_COMPOSE_FILE config > module-configs/$(basename $d).yml
            fi
            if test -f "$EDGEBOX_POSTINSTALL_FILE"; then
                echo " - Building $(basename $d) post-install"
                cat $EDGEBOX_POSTINSTALL_FILE >> ./module-configs/postinstall.txt
            fi

        done

        global_composer="${global_composer} config > docker-compose.yml"

        echo "Building global compose file -> $global_composer"
        eval $global_composer

        echo "Starting Services"
        docker-compose up -d --build

        run_postinstall

        publish_mdns_entries

        # Systemctl service. Only needs to be run once and auto-starts
        setup_myedgebox_tunnel

        ;;
    -s|--start)
        start=1
        docker-compose up -d
        publish_mdns_entries
        ;;
    -l|--logs)
        logs=1
        docker-compose logs $2
        ;;
    -r|--restart)
        restart=1
        docker-compose restart $2
        kill_mdns_entries
        publish_mdns_entries
        ;;
    -k|--kill)
        kill=1
        docker-compose down
        kill_mdns_entries
        ;;
    -t|--terminal)
        terminal=1
        docker-compose exec $2 bash
        ;;
    -c|--clean)
        clean
        ;;
    -o|--output)
        output="$2"
        shift
        ;;
    -*)
        usage "Unknown option '$1'"
        ;;
    *)
        if [ -z "$foo" ] ; then
            foo="$1"
        elif [ -z "$bar" ] ; then
            bar="$1"
        else
            usage "Too many arguments"
        fi
        ;;
    esac
    shift
done
# if [ -z "$bar" ] ; then
#     usage "Not enough arguments"
# fi
# foo=$foo
# bar=$bar
# delete=$delete
# output=$output
cat <<EOF

-----------------------
| Operation Completed. | 
-----------------------

EOF
