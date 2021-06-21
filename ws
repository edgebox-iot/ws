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
        sleep 10 # This is base time. To add further delay, execute the sleep inside of the postinstall...
        echo "Executing post-install operations"

        while read -r line
        do
            echo " -> docker-compose exec $line"
            docker-compose exec $line </dev/null || true &
            wait
        done < "$POSTINSTALL_FILE"

        echo "Finished post-install operations"
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
    runnable_file=".run"
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
                    nohup avahi-publish -a -R $line$domain $local_ip >/dev/null 2>&1 &
                    sleep 3
                done < "$HOSTS_FILE"
            fi
        done
    
        echo "Publishing mDNS service entries for edgeapps to ${local_ip}"
        for d in ../apps/*/ ; do
            HOSTS_FILE="$d$config_name"
            SERVICE_NAME="$(basename $d)"
            RUNNABLE_FILE="$d$runnable_file"
            if test -f "$HOSTS_FILE"; then
                echo "Found configuration for $SERVICE_NAME edgeapp"
                if test -f "$RUNNABLE_FILE"; then
                    while IFS= read -r line; do
                        echo "Publishing domain $line$domain"
                        nohup avahi-publish -a -R $line$domain $local_ip >/dev/null 2>&1 &
                        sleep 3
                    done < "$HOSTS_FILE"
                fi
            fi 
        done

    fi
}

kill_mdns_entries() {
    echo "Killing mDNS service entries"
    pkill avahi-publish
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
        myedgeappenv_name="myedgeapp.env"
        postinstall_file="edgebox-postinstall.txt"
        runnable_file=".run"
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
            MYEDGEAPP_ENV_FILE="$d$myedgeappenv_name"
            INTERNET_URL=""
        if test -f "$EDGEBOX_COMPOSE_FILE"; then
        echo " - Building $(basename $d) module"
                global_composer="${global_composer} -f ./module-configs/$(basename $d).yml"
                echo " - Testing existance of $MYEDGEAPP_ENV_FILE"
                if test -f "$MYEDGEAPP_ENV_FILE"; then
                    export $(cat $MYEDGEAPP_ENV_FILE | xargs)
                    echo " - Adding VIRTUAL_HOST entry for $INTERNET_URL"
                    INTERNET_URL_NOCOMMA="$INTERNET_URL"
                    INTERNET_URL=",$INTERNET_URL"
                fi
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
            EDGEBOX_RUNNABLE_FILE="$d$runnable_file"
            MYEDGEAPP_ENV_FILE="$d$myedgeappenv_name"
            INTERNET_URL=""
            
            if test -f "$EDGEBOX_COMPOSE_FILE"; then
                echo " - Found Edgebox Application Config File"
                if test -f "$EDGEBOX_RUNNABLE_FILE"; then
                    echo " - Building EdgeApp -> $(basename $d)"
                    global_composer="${global_composer} -f ./module-configs/$(basename $d).yml"
                    # Check existance of myedge.app config file, apply it as ENV VAR before building config file.
                    echo " - Testing existance of $MYEDGEAPP_ENV_FILE"
                    if test -f "$MYEDGEAPP_ENV_FILE"; then
                        export $(cat $MYEDGEAPP_ENV_FILE | xargs)
                        echo " - Adding VIRTUAL_HOST entry for $INTERNET_URL"
                        INTERNET_URL_NOCOMMA="$INTERNET_URL"
                        INTERNET_URL=",$INTERNET_URL"
                    fi
                    BUILD_ARCH=$(uname -m) docker-compose --env-file=$EDGEBOX_ENV_FILE -f $EDGEBOX_COMPOSE_FILE config > module-configs/$(basename $d).yml
                fi
            fi
            if test -f "$EDGEBOX_POSTINSTALL_FILE"; then
                echo " - Building $(basename $d) post-install"
                INTERNET_URL="$INTERNET_URL_NOCOMMA"
                eval "echo \"$(cat $EDGEBOX_POSTINSTALL_FILE)\"" >> ./module-configs/postinstall.txt
            fi

        done

        global_composer="${global_composer} config > docker-compose.yml"

        echo "Building global compose file -> $global_composer"
        eval $global_composer

        echo "Starting Services"
        docker-compose up -d --build

        if ! [ "$2" = "--fast" ]; then
            run_postinstall
        fi

        publish_mdns_entries

        touch .ready

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
