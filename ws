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
-s, --start              docker-compose up -d
-l, --logs [SERVICE]     docker-compose logs for [SERVICE]
-r, --restart [SERVICE]  docker-compose restart [SERVICE]
-k, --kill               docker-compose down
-o, --output [FILE] write output to file

EOF
    exit 1
}
publish_mdns_entries() {
    config_name="edgebox-hosts.txt"
    domain=".edgebox.local"
    if command -v avahi-publish -h &> /dev/null
    then
        echo "Publishing mDNS service entries"
        for d in ../*/ ; do
            HOSTS_FILE="$d$config_name"
            SERVICE_NAME="$(basename $d)"
            if test -f "$HOSTS_FILE"; then
                echo "Found configuration for $SERVICE_NAME service"
		while IFS= read -r line
		do
                avahi-publish -a -R $line$domain $(hostname -I | awk '{print $1}') &
		done < "$HOSTS_FILE"
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
        global_composer="docker-compose"

        for d in ../*/ ; do
            # Iterating through each one of the directories in the "components" dir, look for edgebox-compose service definitions...
            EDGEBOX_COMPOSE_FILE="$d$config_name"
            if test -f "$EDGEBOX_COMPOSE_FILE"; then
                echo "Building $EDGEBOX_COMPOSE_FILE module -> docker-compose --env-file=$d/edgebox.env -f $EDGEBOX_COMPOSE_FILE config > module-configs/$(basename $d).yml"
                global_composer="${global_composer} -f ./module-configs/$(basename $d).yml"
                BUILD_ARCH=$(uname -m) docker-compose --env-file=$d/edgebox.env -f $EDGEBOX_COMPOSE_FILE config > module-configs/$(basename $d).yml
            fi
        done

        global_composer="${global_composer} config > docker-compose.yml"

        echo "Building global compose file -> $global_composer"
        eval $global_composer

        echo "Starting Services"
        docker-compose up -d --build

        # TODO: This should really be executed inside its own service definition (port to edgebox-iot/api repo)
        docker exec -w /var/www/html -it edgebox-api-ws composer install
        docker exec -it edgebox-api-ws chmod -R 777 /var/www/html/app/Storage/Cache

        publish_mdns_entries

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
