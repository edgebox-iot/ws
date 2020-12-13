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
            # echo "$d"
            FILE="$d$config_name"
            if test -f "$FILE"; then
                echo "Building $FILE module -> docker-compose --env-file=$d/edgebox.env -f $FILE config > module-configs/$(basename $d).yml"
                global_composer="${global_composer} -f ./module-configs/$(basename $d).yml"
                docker-compose --env-file=$d/edgebox.env -f $FILE config > module-configs/$(basename $d).yml
            fi
        done

        global_composer="${global_composer} config > docker-compose.yml"
        echo "Building global compose file -> $global_composer"
        eval $global_composer
        ;;
    -s|--start)
        start=1
        docker-compose up -d
        ;;
    -l|--logs)
        logs=1
        docker-compose logs $2
        ;;
    -r|--restart)
        restart=1
        docker-compose restart $2
        ;;
    -k|--kill)
        kill=1
        docker-compose down
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