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
        echo "Executing post-install operations"

        # Check the content of POSTINSTALL_FILE
        # If it is empty, then there is nothing to do
        if [ ! -s "$POSTINSTALL_FILE" ]; then
            echo "No post-install operations to execute"
            return
        else
            echo "Waiting for Container Warmups before running post-install operations..."
            sleep 10
        fi

        while read -r line
        do
            echo " -> docker-compose exec $line"
            docker-compose exec $line </dev/null || true &
            wait
        done < "$POSTINSTALL_FILE"

        # Recreate the postinstall file in each of the directories of ../apps/ to indicate that it has been executed
        for d in ../apps/*/ ; do
            POSTINSTALL_FILE="$d$postinstall_file"
            POSTINSTALL_DONE_FILE="$d$(echo $postinstall_file | sed 's/.txt/.done/')"
            if test -f "$POSTINSTALL_FILE"; then
                cp $POSTINSTALL_FILE $POSTINSTALL_DONE_FILE
            fi
        done

        # And do the same for ../
        for d in ../*/ ; do
            POSTINSTALL_FILE="$d$postinstall_file"
            POSTINSTALL_DONE_FILE="$d$(echo $postinstall_file | sed 's/.txt/.done/')"
            if test -f "$POSTINSTALL_FILE"; then
                cp $POSTINSTALL_FILE $POSTINSTALL_DONE_FILE
            fi
        done


        echo "Finished post-install operations"
    fi
}

get_lan_ip () {
    for adaptor in eth0 wlan0 enp0s1; do
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
    host_name=$(hostname)
    domain=".$host_name.local"
    local_ip=$(get_lan_ip)
    if command -v avahi-publish -h &> /dev/null; then
    
        echo "Publishing mDNS service entries for modules to ${local_ip}"
        for d in ../*/ ; do
            HOSTS_FILE="$d$config_name"
            SERVICE_NAME="$(basename $d)"
            if test -f "$HOSTS_FILE"; then
                # echo "Found configuration for $SERVICE_NAME service"
                while IFS= read -r line; do
                    echo "Publishing domain $line$domain"
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
                # echo "Found configuration for $SERVICE_NAME edgeapp"
                if test -f "$RUNNABLE_FILE"; then
                    while IFS= read -r line; do
                        echo "Publishing domain $line$domain"
                        nohup avahi-publish -a -R $line$domain $local_ip >/dev/null 2>&1 &
                        sleep 1
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
        appenv_name="edgeapp.env"
        authenv_name="auth.env"
        myedgeappenv_name="myedgeapp.env"
        postinstall_file="edgebox-postinstall.txt"
        runnable_file=".run"
        global_composer="docker-compose"
        host_name=$(hostname)
        export HOSTNAME="$host_name"
    
        if test -f ./module-configs/postinstall.txt; then
            rm module-configs/postinstall.txt
        fi
    
        touch module-configs/postinstall.txt
        mkdir -p module-configs/sec_tmp

        for d in ../*/ ; do
            DIR_NAME="$(basename $d)"
            # Iterating through each one of the directories in the "components" dir, look for edgebox-compose service definitions...
            EDGEBOX_COMPOSE_FILE="$d$config_name"
            EDGEBOX_ENV_FILE="$d$env_name"
            APP_ENV_FILE="$d$appenv_name"
            AUTH_ENV_FILE="$d$authenv_name"
            EDGEBOX_POSTINSTALL_FILE="$d$postinstall_file"
            # A POSTINSTALL_DONE file is created in the module's directory to indicate that the postinstall has been executed. It should replace the .txt extension with .done
            POSTINSTALL_DONE_FILE="$d$(echo $postinstall_file | sed 's/.txt/.done/')"
            MYEDGEAPP_ENV_FILE="$d$myedgeappenv_name"
            INTERNET_URL=""
            LOCAL_URL=""
            MAIN_URL=""
            if test -f "$EDGEBOX_COMPOSE_FILE"; then
                echo " - Building $(basename $d) module"
                global_composer="${global_composer} -f ./module-configs/$(basename $d).yml"
                LOCAL_URL="$DIR_NAME.$host_name.local"
                MAIN_URL=$LOCAL_URL
                export LOCAL_URL="$LOCAL_URL"
                echo " ----> LOCAL_VIRTUAL_HOST entry: $LOCAL_URL"
                # echo " - Testing existance of $MYEDGEAPP_ENV_FILE"
                if test -f "$MYEDGEAPP_ENV_FILE"; then
                    if grep -q 'INTERNET_URL' "$MYEDGEAPP_ENV_FILE"; then
                        export $(cat $MYEDGEAPP_ENV_FILE | xargs)
                        echo " ----> INTERNET_VIRTUAL_HOST entry: $INTERNET_URL"
                        INTERNET_URL_NOCOMMA="$INTERNET_URL"
                        MAIN_URL=$INTERNET_URL_NOCOMMA
                        INTERNET_URL=",$INTERNET_URL"
                    fi
                fi
                if test -f "$APP_ENV_FILE"; then
                    echo " ----> APP_ENV_FILE entry: $APP_ENV_FILE"
                    # APP_ENV_FILE_FLAG="--env-file=$APP_ENV_FILE"
                    APP_ENV_FILE_FLAG=""
                    export $(cat $APP_ENV_FILE | xargs)
                    INTERNET_URL=",$INTERNET_URL"
                else
                    APP_ENV_FILE_FLAG=""
                fi
                if test -f "$AUTH_ENV_FILE"; then
                    echo " ----> AUTH_ENV_FILE entry: $AUTH_ENV_FILE"
                    # AUTH_ENV_FILE_FLAG="--env-file=$AUTH_ENV_FILE"
                    AUTH_ENV_FILE_FLAG=""
                    export $(cat $AUTH_ENV_FILE | xargs)
                    echo " ----> Building $(basename $d) basic auth token"
                    echo "Username: $USERNAME"
                    echo "Password: $PASSWORD"
                    # Thw following line writes the command not the output to the file
                    # htpasswd -nb $USERNAME $PASSWORD > ./module-configs/sec/$MAIN_URL
                    # The following line writes the output to the file
                    htpasswd -nb $USERNAME $PASSWORD | tee ./module-configs/sec_tmp/$MAIN_URL
                else
                    AUTH_ENV_FILE_FLAG=""
                fi
                export MAIN_URL="$MAIN_URL"
                BUILD_ARCH=$(uname -m) docker-compose --env-file=$EDGEBOX_ENV_FILE -f $EDGEBOX_COMPOSE_FILE config > module-configs/$(basename $d).yml
            fi
            if test -f "$EDGEBOX_POSTINSTALL_FILE"; then
                # If POSTINSTALL_DONE_FILE exists and the content is the same as the EDGEBOX_POSTINSTALL_FILE, it means that the postinstall has already been executed. We don't want to execute it again.
                if test -f "$POSTINSTALL_DONE_FILE"; then
                    if cmp -s "$EDGEBOX_POSTINSTALL_FILE" "$POSTINSTALL_DONE_FILE"; then
                        echo " ----> Postinstall already executed for $(basename $d)"
                    else
                        echo " ----> Building $(basename $d) post-install"
                        cat $EDGEBOX_POSTINSTALL_FILE >> ./module-configs/postinstall.txt
                    fi
                else
                    echo " ----> Building $(basename $d) post-install"
                    cat $EDGEBOX_POSTINSTALL_FILE >> ./module-configs/postinstall.txt
                fi
            fi

        done

        for d in ../apps/*/ ; do
            # Now looking specifically for edgeapps... If they follow the correct package structure, it will fit seamleslly.
            DIR_NAME="$(basename $d)"
            EDGEBOX_COMPOSE_FILE="$d$config_name"
            EDGEBOX_ENV_FILE="$d$env_name"
            APP_ENV_FILE="$d$appenv_name"
            AUTH_ENV_FILE="$d$authenv_name"
            EDGEBOX_POSTINSTALL_FILE="$d$postinstall_file"
            POSTINSTALL_DONE_FILE="$d$(echo $postinstall_file | sed 's/.txt/.done/')"
            EDGEBOX_RUNNABLE_FILE="$d$runnable_file"
            MYEDGEAPP_ENV_FILE="$d$myedgeappenv_name"
            INTERNET_URL=""
            LOCAL_URL=""
            MAIN_URL=""

            if test -f "$EDGEBOX_COMPOSE_FILE"; then
                echo " - Found Edgebox Application Config File"
                if test -f "$EDGEBOX_RUNNABLE_FILE"; then
                    echo " ----> Building EdgeApp -> $(basename $d)"
                    global_composer="${global_composer} -f ./module-configs/$(basename $d).yml"
                    LOCAL_URL="$DIR_NAME.$host_name.local"
                    MAIN_URL=$LOCAL_URL
                    export LOCAL_URL="$LOCAL_URL"
                    echo " ----> LOCAL_VIRTUAL_HOST entry: $LOCAL_URL"
                    # Check existance of myedge.app config file, apply it as ENV VAR before building config file.
                    # echo " - Testing existance of $MYEDGEAPP_ENV_FILE"
                    if test -f "$MYEDGEAPP_ENV_FILE"; then
                        export $(cat $MYEDGEAPP_ENV_FILE | xargs)
                        echo " ----> INTERNET_VIRTUAL_HOST entry: $INTERNET_URL"
                        INTERNET_URL_NOCOMMA="$INTERNET_URL"
                        MAIN_URL=$INTERNET_URL_NOCOMMA
                        INTERNET_URL=",$INTERNET_URL"
                    fi
                    if test -f "$APP_ENV_FILE"; then
                        echo " ----> APP_ENV_FILE entry: $APP_ENV_FILE"
                        # APP_ENV_FILE_FLAG=" --env-file=$APP_ENV_FILE"
                        APP_ENV_FILE_FLAG=""
                        export $(cat $APP_ENV_FILE | xargs)
                        INTERNET_URL=",$INTERNET_URL"
                    else
                        APP_ENV_FILE_FLAG=""
                    fi
                    if test -f "$AUTH_ENV_FILE"; then
                        echo " ----> AUTH_ENV_FILE entry: $AUTH_ENV_FILE"
                        # AUTH_ENV_FILE_FLAG="--env-file=$AUTH_ENV_FILE"
                        AUTH_ENV_FILE_FLAG=""
                        export $(cat $AUTH_ENV_FILE | xargs)
                        echo " ----> Building $(basename $d) basic auth token"
                        echo "Username: $USERNAME"
                        echo "Password: $PASSWORD"
                        htpasswd -nb $USERNAME $PASSWORD | tee ./module-configs/sec_tmp/$MAIN_URL
                    else
                        AUTH_ENV_FILE_FLAG=""
                    fi
                    export MAIN_URL="$MAIN_URL"
		            export INTERNET_URL="$INTERNET_URL"
		            echo "INTERNET_URL: $INTERNET_URL"
                    BUILD_ARCH=$(uname -m) docker-compose --env-file=$EDGEBOX_ENV_FILE$APP_ENV_FILE_FLAG -f $EDGEBOX_COMPOSE_FILE config > module-configs/$(basename $d).yml
                    if test -f "$EDGEBOX_POSTINSTALL_FILE"; then
                        # If POSTINSTALL_DONE_FILE exists and the content is the same as the EDGEBOX_POSTINSTALL_FILE, it means that the postinstall has already been executed. We don't want to execute it again.
                        INTERNET_URL="$MAIN_URL"
                        if test -f "$POSTINSTALL_DONE_FILE"; then
                            if cmp -s "$EDGEBOX_POSTINSTALL_FILE" "$POSTINSTALL_DONE_FILE"; then
                                echo " ----> Postinstall already executed for $(basename $d)"
                            else
                                echo " ----> Building $(basename $d) post-install"
                                cat $EDGEBOX_POSTINSTALL_FILE >> ./module-configs/postinstall.txt
                            fi
                        else
                            echo " ----> Building $(basename $d) post-install"
                            # cat $EDGEBOX_POSTINSTALL_FILE >> ./module-configs/postinstall.txt
                            while IFS= read -r line; do
                                echo $line
                                # Replace any env var in the line
                                eval "echo $line" >> ./module-configs/postinstall.txt
                            done < $EDGEBOX_POSTINSTALL_FILE
                        fi
                    fi
                else
                    echo " ----> EdgeApp -> $(basename $d) is not runnable. Skipping..."
                fi
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

        if ! [ "$2" = "--fast" ]; then
        publish_mdns_entries
        fi

        # Reset Basic Auth Tokens
        rm -rf module-configs/sec/* && mv module-configs/sec_tmp/* module-configs/sec/ || true && rm -rf module-configs/sec_tmp

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
        # if option is not --fast, then the option is unknown
        if ! [ "$1" = "--fast" ]; then
            usage "Unknown option '$1'"
        fi
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
